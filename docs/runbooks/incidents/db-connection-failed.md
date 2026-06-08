# Incident: DB 연결 실패

> 대상: RDS PostgreSQL (백엔드 5svc — learning-ai만 Python/asyncpg, 나머지 4 Spring/Flyway) — dev/staging/prod 가 단일 인스턴스(db.t3.small)를 **서비스별 DB로 분리** (`synapse_platform`/`synapse_engagement`/`synapse_knowledge`/`synapse_learning`/`synapse_ai`, PR #136)
> 관련 실사례: T-030, T-031, T-040(D-026), T-073 패턴 + W4 학습(연결 한도) + W5 Day1(flyway 충돌)

## 증상

- 앱 로그: `Connection refused` / `connection timed out` / `HikariPool ... Connection is not available`
- 기동 실패(CrashLoop)면 → 먼저 `pod-crashloop.md` 체크리스트 1·2번과 교차 확인
- `flyway_schema_history ... checksum mismatch` (다른 서비스가 같은 DB의 이력을 검증 — DB 분리 누락 신호, #92)
- 다중 서비스 동시 발생이면 인프라 공통 원인(SG/RDS/연결 고갈) 가능성 높음

## 진단 (순서대로 — 진단 트리)

```bash
# 0. 에러 원문 확보
kubectl logs deploy/<svc> -n <ns> --tail=200 | grep -iE "connection|refused|timeout|hikari|flyway|checksum"
```

### 1. RDS 인스턴스 상태

```bash
aws rds describe-db-instances --region ap-northeast-2 \
  --query 'DBInstances[].{id:DBInstanceIdentifier,status:DBInstanceStatus,ep:Endpoint.Address}'
```
`available` 아니면 → AWS 콘솔 이벤트 확인, 복구 대기 또는 L2.

### 2. Security Group (T-040, D-026 — 본 프로젝트 최빈 원인)

EKS **cluster SG**가 RDS SG 인바운드에 있어야 한다 (terraform화 완료 — PR #90 이후엔 드물지만, 수동 인프라 변경 후 재발 가능):

```bash
CLUSTER_SG=$(aws eks describe-cluster --name <cluster> --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 describe-security-groups --group-ids <RDS_SG> \
  --query 'SecurityGroups[].IpPermissions[].UserIdGroupPairs[].GroupId'
# CLUSTER_SG 가 목록에 없으면 → infra terraform 의 SG 규칙 확인 후 apply
```

### 3. DB 분리·엔드포인트·시크릿 정합 (T-073 패턴 + #92)

서비스가 자기 DB(`synapse_<svc>`)를 가리키는지 + 엔드포인트가 일치하는지 확인:

```bash
kubectl get cm <svc>-config -n <ns> -o jsonpath='{.data.DATABASE_NAME}'   # synapse_<svc> 여야 함
# URL은 ConfigMap <svc>-config 에 평문(base64 아님). 키 이름이 서비스마다 다름:
#   platform-svc → DB_URL · learning-ai → LEARNING_AI_DATABASE_URL · 나머지 3 → SPRING_DATASOURCE_URL
kubectl get cm <svc>-config -n <ns> -o jsonpath='{.data.SPRING_DATASOURCE_URL}'   # platform=DB_URL, learning-ai=LEARNING_AI_DATABASE_URL
# ↑ 1번에서 확인한 실제 RDS 엔드포인트 + /synapse_<svc> 인지 확인
```
- DB가 `synapse`(공유)로 남아 있으면 → overlay의 `DATABASE_NAME`/`SPRING_DATASOURCE_URL`을 `synapse_<svc>`로 수정 (PR #136 패턴). flyway checksum 충돌의 근본 원인.
- 엔드포인트 불일치 → AWS SM 값 갱신 → ExternalSecret force-sync (pod-crashloop.md 조치 참조).
- 대상 DB 자체가 RDS에 없으면 → DBA/인프라가 `CREATE DATABASE synapse_<svc>` 선행 (PR #136은 5개 DB 생성 전제).

### 4. ESO 동기화 상태 (T-030/031)

```bash
kubectl get clustersecretstore aws-secrets-manager   # Ready=True
kubectl get externalsecret -n <ns>                   # 전부 SecretSynced
```

### 5. 연결 수 고갈 (W4 학습 — db.t3.small 한도)

dev+staging+prod 동시 기동 시 연결 한도 초과 이력 있음 (W4 prod 재현 때 dev/staging 축소로 대응). DB 분리로 DB 수는 늘었으나 인스턴스 연결 한도는 동일:

```bash
# CloudWatch 현재 연결 수
aws cloudwatch get-metric-statistics --namespace AWS/RDS \
  --metric-name DatabaseConnections --dimensions Name=DBInstanceIdentifier,Value=<RDS_ID> \
  --start-time "$(date -u -d '-15 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" \
  --period 300 --statistics Maximum
```

## 조치

| 원인 | 조치 |
|---|---|
| RDS 비가용 | AWS 이벤트 대기/복구, 장기화 시 L2 |
| SG 미허용 | terraform SG 규칙 복원 → apply (수동 콘솔 수정 금지) |
| DB 미분리(`synapse` 공유) | overlay `DATABASE_NAME`/URL을 `synapse_<svc>`로 (PR #136), 대상 DB 선행 생성 |
| 시크릿 불일치 | SM 갱신 → ExternalSecret force-sync → rollout restart |
| 연결 고갈 | 즉시: 비핵심 환경 replica 축소(git 경유). 구조: 인스턴스 증설 또는 Hikari pool 상한 조정 — team-lead 비용 결정 |

## 에스컬레이션 기준

- **전 서비스 동시 DB 장애** → 즉시 L2
- 연결 고갈 재발 (환경 축소로 임시 대응 중) → L2, 인스턴스 사이징 결정 요청
- RDS 자체 장애 1시간+ → L2 + AWS Support 검토

## 회피 방법

- SG는 terraform 단일 소스 유지 (D-026 — PR #90에서 terraform화 완료, 콘솔 수동 변경 금지)
- 신규 Spring svc 온보딩 시 전용 `synapse_<svc>` DB 생성 + overlay DATABASE_NAME 분리 (PR #136 패턴) — flyway 충돌 예방
- 윈도우에서 3환경 동시 기동 시 연결 수 모니터링을 체크리스트에 포함
- (후보) `DatabaseConnections` CloudWatch 알람 → Slack

## 사후 점검

- [ ] 원인을 Discovery Log(T-항목)에 기록
- [ ] 시크릿 갱신 시 다른 환경의 동일 키도 점검
- [ ] 연결 고갈이었다면 당시 환경별 replica 구성을 HISTORY에 기록 (Step 12 사이징 입력)
