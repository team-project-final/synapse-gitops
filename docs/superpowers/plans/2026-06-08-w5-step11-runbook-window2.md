# W5 Step 11 장애 Runbook + 검증 윈도우 2 — 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Step 11 장애 Runbook 산출물(incidents 5종 + on-call) 작성·머지 + 윈도우 2 실행 런북(`W5_WINDOW_2.md`) 확정 + TASK 문서 정합.

**Architecture:** 전부 문서 작업(비용 0). 스펙 `docs/superpowers/specs/2026-06-08-w5-step11-runbook-window2-design.md`의 단계 A+B. 윈도우 실행(단계 C)은 본 계획 범위 밖(차기 세션). 브랜치 `docs/w5-step11-window2`(스펙 커밋 614fe72 위에 계속).

**Tech Stack:** Markdown 런북, kubectl/argocd/aws CLI 명령(문서 내), 검증은 섹션 grep + 기존 CI(yamllint는 docs 비대상이므로 비차단).

**전제 사실 (작성 시 그대로 사용):**
- 네임스페이스: `synapse-dev` / `synapse-staging` / `synapse-prod` / `argocd` / `monitoring`
- dev fleet 7: platform-svc, engagement-svc, knowledge-svc, learning-card, learning-ai, gateway, frontend
- staging fleet 7: 5svc + frontend + schema-registry (gateway는 dev 전용)
- ArgoCD App 명명: `synapse-<svc>-dev` / `synapse-<svc>-staging`
- dev/staging ApplicationSet은 `automated + prune + selfHeal: true` → **kubectl 직접 수정은 즉시 원복됨**
- Slack 알람 채널: `#synapse-gitops` (Alertmanager receiver, `infra/monitoring/kube-prometheus-stack-values.yaml:51`)
- 리전: `ap-northeast-2`, ECR: `<ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/<svc>`
- ArgoCD CLI는 SSM 터널(`scripts/lib/eks-tunnel.sh`) + `argocd --core` + `ARGOCD_NAMESPACE=argocd` 전제
- bring-up 페이즈: `terraform eks-auth tunnel argocd eso oidc-fix alb-controller kafka-config manifests metrics-server image-updater observability status` (+`--destroy`)
- IU write-back: `image-updater-<svc>` 브랜치 → `.github/workflows/image-updater-pr.yml`이 PR 자동 생성(GITOPS_TOKEN)

---

### Task 1: `docs/runbooks/incidents/pod-crashloop.md`

**Files:**
- Create: `docs/runbooks/incidents/pod-crashloop.md`

- [ ] **Step 1: 파일 작성** — 아래 내용 그대로 생성

````markdown
# Incident: Pod CrashLoopBackOff

> 대상 환경: synapse-dev / synapse-staging / synapse-prod (EKS)
> 관련 실사례: T-050, T-051, T-052, T-054, T-055, T-056, T-057, T-072 (`docs/runbooks/troubleshooting-infra.md`)

## 증상

- `kubectl get pods -n <ns>` 에서 STATUS `CrashLoopBackOff`, RESTARTS 증가
- ArgoCD UI에서 해당 App `Degraded` (Synced 상태여도 발생 — T-053)
- Alertmanager → `#synapse-gitops` 에 KubePodCrashLooping 계열 알람

## 진단

실행 전 컨텍스트 확인: `kubectl config current-context`

```bash
# 1. 대상 식별
kubectl get pods -n <ns> | grep -v Running
# 2. 이벤트·종료 사유
kubectl describe pod <pod> -n <ns>          # Events, Last State, Exit Code
# 3. 직전 컨테이너 로그 (핵심)
kubectl logs <pod> -n <ns> --previous --tail=100
```

로그 에러를 **프로젝트 빈발 원인 체크리스트** 순으로 대조:

| # | 로그 패턴 | 원인 (실사례) | 확인 명령 |
|---|---|---|---|
| 1 | `Could not resolve placeholder '<KEY>'` | ExternalSecret 미동기화 / SM 키 부재 (T-030/031/054) | `kubectl get externalsecret -n <ns>` → SecretSynced 아닌 항목 |
| 2 | `missing table` / `missing column` / Flyway 에러 | DB 스키마 미시드 — prod는 Hibernate validate (T-050/056, D-024) | 해당 svc Flyway 이력·DB 스키마 확인 |
| 3 | `AES secret key must be 32 bytes` | SM 시크릿 형식 오류 (T-055, D-030) | SM 값이 Base64 32B인지 |
| 4 | 기동은 되나 probe 실패 반복 | 포트 불일치 (T-051) 또는 probe 타이밍 (T-052, D-028) | containerPort vs probe port vs Service targetPort; initialDelay |
| 5 | 정상 로그인데 구버전 동작 | 구 이미지 캐시 (T-057/072) | Pod imageID(digest) vs ECR 최신 digest |

> local-k8s(minikube)는 별도: kafka `enableServiceLinks`, 이미지 로드 이슈 — `local-k8s/README.md` 참조.

## 조치

1. 원인 특정 후 **수정은 git 경유** (dev/staging은 selfHeal — kubectl 수정 즉시 원복됨):
   - 매니페스트 원인 → `apps/<svc>/overlays/<env>/` 수정 → PR → 머지 → auto sync (prod는 수동 sync)
   - SM 시크릿 원인 → AWS SM 값 수정 → ExternalSecret 강제 갱신:
     ```bash
     kubectl annotate externalsecret <name> -n <ns> force-sync="$(date +%s)" --overwrite
     kubectl rollout restart deploy/<svc> -n <ns>
     ```
   - 서비스 코드/스키마 원인 → 해당 서비스 레포에 이슈 이관 (`synapse-<svc>` 레포)
2. 복구 확인: `kubectl get pods -n <ns> -w` → Running + READY, ArgoCD Healthy

## 에스컬레이션 기준

- L1 30분 내 원인 미특정 → L2 (team-lead)
- 다중 서비스 동시 CrashLoop (인프라 공통 원인 의심: ESO/DB/MSK) → **즉시 L2**
- 서비스 코드 원인 → 해당 서비스 레포 이슈 + 서비스 담당 멘션

## 회피 방법

- PR 단계에서 kubeconform/yamllint/렌더 diff CI가 매니페스트 오류 차단 (`validate-manifests.yml`)
- 신규 svc 온보딩 시 `docs/runbooks/frontend-deploy-prereqs.md` 선행조건 체크 (ECR·SM 시드)
- probe 설정은 Spring 기동 시간 반영 (D-028: initialDelaySeconds/startupProbe)

## 사후 점검

- [ ] 새 원인이면 `troubleshooting-infra.md` Discovery Log에 T-항목 추가
- [ ] 재발성 원인이면 본 런북 체크리스트에 행 추가
- [ ] 해당 환경 fleet 전체 Healthy 재확인
````

- [ ] **Step 2: 섹션 검증**

Run: `bash -c 'grep -c "^## " docs/runbooks/incidents/pod-crashloop.md'`
Expected: `6` (증상/진단/조치/에스컬레이션 기준/회피 방법/사후 점검)

- [ ] **Step 3: 커밋**

```bash
git add docs/runbooks/incidents/pod-crashloop.md
git commit -m "docs(incident): Pod CrashLoopBackOff 런북 — 프로젝트 실사례 기반 진단 체크리스트"
```

---

### Task 2: `docs/runbooks/incidents/oom-killed.md`

**Files:**
- Create: `docs/runbooks/incidents/oom-killed.md`

- [ ] **Step 1: 파일 작성** — 아래 내용 그대로 생성

````markdown
# Incident: OOMKilled

> 대상 환경: synapse-dev / synapse-staging / synapse-prod (EKS)
> 배경: W4에서 리소스 한도 기반 환경 운영 학습 (노드 t3.large×4 증설 이력)

## 증상

- Pod 재시작 반복 + `kubectl describe pod` 의 Last State: `Terminated, Reason: OOMKilled, Exit Code: 137`
- 메모리 사용량이 limit 근접 후 급락하는 그래프 반복 (Grafana)

## 진단

```bash
# 1. OOMKilled 대상 식별
kubectl get pods -n <ns> -o json | jq -r '.items[] | select(.status.containerStatuses[]?.lastState.terminated.reason=="OOMKilled") | .metadata.name'
# 2. 현재 사용량 vs limit
kubectl top pods -n <ns>
kubectl get deploy <svc> -n <ns> -o jsonpath='{.spec.template.spec.containers[0].resources}'
# 3. 추세 확인 — Grafana "Synapse 개요" 대시보드 메모리 패널에서 P95 확인
```

- Java 서비스(5svc + gateway)는 힙 외 메모리(metaspace/direct buffer) 포함해 limit을 초과할 수 있음 — JVM 옵션(`-XX:MaxRAMPercentage`) 확인.
- 기동 직후 OOM이면 limit 절대 부족, 장시간 후 OOM이면 릭 의심.

## 조치

**limit 상향은 반드시 git 경유** — dev/staging은 selfHeal이라 `kubectl patch`가 즉시 원복된다 (긴급 패치 불가, sim 환경 제외).

1. `apps/<svc>/overlays/<env>/kustomization.yaml` 의 리소스 패치에서 `resources.limits.memory`를 **P95 × 1.3** 으로 상향
2. PR → CI(렌더 diff 코멘트로 변경 확인) → 머지 → dev/staging auto sync (prod 수동 sync)
3. 복구 확인: `kubectl top pods -n <ns>` 사용량/limit 비율 < 0.8

장시간 후 재발(릭 의심)이면 limit 상향은 임시조치 — 힙덤프와 함께 서비스 레포로 이관.

## 에스컬레이션 기준

- limit 상향 후에도 24h 내 재발 → L2 + 해당 서비스 레포 이슈 (메모리 릭 조사)
- 동일 시간대 다중 서비스 OOM (노드 메모리 압박 의심) → **즉시 L2**, 노드 capacity 검토 (W3 A3 이력: 노드 3→4 증설)

## 회피 방법

- Step 12 "Resource request/limit 적정성 리뷰"에서 전 svc P95 기준 재산정
- Grafana 메모리 패널 + Alertmanager 메모리 사용률 알람 (PrometheusRule)

## 사후 점검

- [ ] 변경한 limit 값과 근거(P95)를 PR 본문에 기록
- [ ] `troubleshooting-infra.md` Discovery Log 추가 (신규 패턴인 경우)
- [ ] 동일 svc의 다른 환경(staging/prod) limit도 함께 점검
````

- [ ] **Step 2: 섹션 검증**

Run: `bash -c 'grep -c "^## " docs/runbooks/incidents/oom-killed.md'`
Expected: `6`

- [ ] **Step 3: 커밋**

```bash
git add docs/runbooks/incidents/oom-killed.md
git commit -m "docs(incident): OOMKilled 런북 — P95 기반 limit 상향, git 경유 원칙"
```

---

### Task 3: `docs/runbooks/incidents/argocd-sync-failed.md`

**Files:**
- Create: `docs/runbooks/incidents/argocd-sync-failed.md`

- [ ] **Step 1: 파일 작성** — 아래 내용 그대로 생성

````markdown
# Incident: ArgoCD Sync 실패

> 대상 환경: ArgoCD (ns `argocd`) — dev/staging auto sync, prod manual
> 관련 실사례: T-020, T-021, T-022, T-070 (`docs/runbooks/troubleshooting-infra.md`)
> CLI 전제: SSM 터널(`scripts/lib/eks-tunnel.sh`) + `argocd --core`, `export ARGOCD_NAMESPACE=argocd`

## 증상

- App이 `OutOfSync` 지속 또는 sync operation `Failed`
- ArgoCD UI 에러 배너 / `argocd app get` 의 CONDITIONS 에러
- IU write-back의 경우: `image-updater-<svc>` 브랜치는 갱신되는데 main에 반영 안 됨

## 진단

```bash
# 1. 실패 앱 식별
argocd app list | grep -vE "Synced.*Healthy"
# 2. 실패 원인 (operation 메시지가 1차 근거)
argocd app get <app> --show-operation
argocd app diff <app>
# 3. 로컬 재현 — manifest 원인인지 즉시 판별
kustomize build apps/<svc>/overlays/<env>
```

빈발 원인 체크리스트:

| # | 에러 패턴 | 원인 (실사례) | 조치 방향 |
|---|---|---|---|
| 1 | `namespaces "<ns>" not found` | 네임스페이스 부재 (T-070) | ns 매니페스트 추가 또는 syncOption `CreateNamespace=true` |
| 2 | `metadata.annotations: Too long` | CRD apply 방식 (T-020) | `--server-side` 적용 |
| 3 | `no matches for kind` | CRD 미설치 (T-021) | 선행 CRD/컨트롤러 설치 확인 (bring-up 페이즈 순서) |
| 4 | server-side `conflict` | 필드 소유권 충돌 (T-022) | `--force-conflicts` 또는 소유자 정리 |
| 5 | AppProject 거부 (`not permitted`) | sourceRepos/destinations 제약 | `argocd proj get <proj>` 로 허용 범위 확인 |
| 6 | kustomize build 실패 | overlay 참조 오류 | 3번 로컬 재현 결과의 에러 라인 수정 |

**IU write-back 미반영** (PR write-back 경로, PR #127):

```bash
# 브랜치는 push됐는가
git ls-remote origin 'image-updater-*'
# PR 자동 생성 워크플로가 돌았는가
gh run list --workflow=image-updater-pr.yml --limit 5
```
- 브랜치 없음 → image-updater Pod 로그 확인 (`kubectl logs -n argocd deploy/argocd-image-updater`) — ECR 자격(`no basic auth credentials`, gitops#122 이력) 여부
- 브랜치 있고 PR 없음 → `GITOPS_TOKEN` 시크릿 만료/권한 확인 (repo Settings → Secrets)

## 조치

1. manifest 원인 → 수정 PR → 머지 → 재sync (`argocd app sync <app>`)
2. 일시 장애(네트워크 등) → `argocd app sync <app> --retry-limit 3`
3. prod는 수동 승인 게이트 유지 — 수정 머지 후에도 **gitops-admin이 명시적으로 sync**

## 에스컬레이션 기준

- 단일 앱 30분 미해결 → L2
- **전 앱 동시 OutOfSync/Unknown** (application-controller·repo-server 장애 의심) → 즉시 L2 + `kubectl get pods -n argocd` 상태 첨부

## 회피 방법

- PR 전 `kustomize build` 로컬 실행 습관 — CI(`validate-manifests.yml`)와 동일 검증
- CRD 포함 인프라는 bring-up 페이즈 순서에 등록 (수동 apply 금지)

## 사후 점검

- [ ] 신규 에러 패턴이면 본 런북 표 + `troubleshooting-infra.md` Discovery Log 추가
- [ ] sync 실패가 잦은 앱은 syncOptions/retry 정책 재검토
````

- [ ] **Step 2: 섹션 검증**

Run: `bash -c 'grep -c "^## " docs/runbooks/incidents/argocd-sync-failed.md'`
Expected: `6`

- [ ] **Step 3: 커밋**

```bash
git add docs/runbooks/incidents/argocd-sync-failed.md
git commit -m "docs(incident): ArgoCD sync 실패 런북 — 빈발 원인 표 + IU PR write-back 진단"
```

---

### Task 4: `docs/runbooks/incidents/cert-expired.md`

**Files:**
- Create: `docs/runbooks/incidents/cert-expired.md`

- [ ] **Step 1: 파일 작성** — 아래 내용 그대로 생성

````markdown
# Incident: TLS 인증서 만료

> 대상 스택: **ALB + self-signed ACM import** (cert-manager 미도입 — 2026-06-05 W5 클리어 설계 결정)
> 관련 자산: `infra/ingress/nipio/*.yaml`, `scripts/gen-nipio-selfsigned.sh`, `.nipio-certs/`(gitignore)
> ⚠️ ACM **import 인증서는 자동 갱신이 없다** — 만료는 "발생하는" 장애가 아니라 "예정된" 장애다.

## 증상

- `curl --cacert .nipio-certs/ca.crt https://argocd.<IP>.nip.io` → `certificate has expired`
- 브라우저 인증서 만료 경고 / ALB 리스너의 인증서 오류
- GitHub webhook 전송 실패 (TLS 검증 거부)

## 진단

```bash
# 1. 실제 서빙 중인 인증서 만료일
openssl s_client -connect argocd.<IP>.nip.io:443 -servername argocd.<IP>.nip.io </dev/null 2>/dev/null \
  | openssl x509 -noout -dates
# 2. ACM 쪽 만료일 대조
aws acm list-certificates --region ap-northeast-2 \
  --query 'CertificateSummaryList[].{arn:CertificateArn,domain:DomainName,exp:NotAfter}'
aws acm describe-certificate --certificate-arn <ARN> --query 'Certificate.NotAfter'
# 3. ingress가 어떤 ARN을 쓰는지
kubectl get ingress -A -o yaml | grep certificate-arn
```

## 조치

### A. nip.io ALB 인증서 (주 경로)

```bash
# 1. 현재 ALB DNS 확인
kubectl get ingress -A   # ADDRESS 컬럼
# 2. 재발급 + ACM 재임포트 (새 ARN 출력)
bash scripts/gen-nipio-selfsigned.sh <ALB_DNS>   # → CERT_ARN=arn:aws:acm:...
# 3. ingress의 certificate-arn 교체
#    - 상시 운영 중이면: infra/ingress/nipio/*.yaml 수정 → PR → 머지 → sync
#    - 윈도우(폐기 전제) 중이면: kubectl annotate 로 직접 교체 후 윈도우 종료 시 destroy
# 4. 검증
curl --cacert .nipio-certs/ca.crt https://argocd.<IP>.nip.io   # 200 + 체인 유효
```

> ALB IP가 바뀌었으면 nip.io 호스트도 무효 — 스크립트가 새 IP 기준 SAN으로 재생성하므로 ingress의 host도 함께 치환한다.

### B. ArgoCD NLB self-signed (W1 유산 경로 사용 시)

기본 접근은 SSM 터널 + `--insecure`라 외부 TLS 비의존. NLB 노출을 유지 중인 경우에만:

```bash
kubectl delete secret argocd-server-tls -n argocd   # 재생성 트리거 (자체 생성 경로)
kubectl rollout restart deploy/argocd-server -n argocd
```

### C. 만료된 구 인증서 정리

```bash
aws acm delete-certificate --certificate-arn <OLD_ARN>   # ingress 참조 해제 후
```

## 에스컬레이션 기준

- 재발급 후에도 체인 검증 실패 (SAN/IP 불일치 반복) → L2
- 공인 인증서(실 도메인) 전환 결정 필요 시 → team-lead (비용·도메인 확보 결정)

## 회피 방법

- **만료 30일 전 점검**: ACM `NotAfter` 확인을 윈도우 Phase 0 체크리스트에 포함
- nip.io self-signed는 **윈도우 1회성·폐기 전제** — 장기 운영 전환 시 실 도메인 + 공인 ACM으로 교체 (TASK Step 9 이월 항목)
- (후보) CloudWatch Events + ACM 만료 알람 → Slack — 실 도메인 전환 시 도입

## 사후 점검

- [ ] 새 ARN이 git의 ingress 매니페스트와 일치하는지 (윈도우 외 상시 운영 시)
- [ ] `.nipio-certs/` 로컬 파일이 커밋되지 않았는지 (`git status` — gitignore 확인)
- [ ] webhook 외부 도달 재검증 (GitHub ping → `/api/webhook` 200)
````

- [ ] **Step 2: 섹션 검증**

Run: `bash -c 'grep -c "^## " docs/runbooks/incidents/cert-expired.md'`
Expected: `6`

- [ ] **Step 3: 커밋**

```bash
git add docs/runbooks/incidents/cert-expired.md
git commit -m "docs(incident): TLS 인증서 만료 런북 — self-signed ACM import 실스택 기준"
```

---

### Task 5: `docs/runbooks/incidents/db-connection-failed.md`

**Files:**
- Create: `docs/runbooks/incidents/db-connection-failed.md`

- [ ] **Step 1: 파일 작성** — 아래 내용 그대로 생성

````markdown
# Incident: DB 연결 실패

> 대상: RDS (Spring 5svc) — dev/staging/prod 가 단일 인스턴스(db.t3.small)의 스키마 분리 구조
> 관련 실사례: T-030, T-031, T-040(D-026), T-073 패턴 + W4 학습(연결 한도)

## 증상

- 앱 로그: `Connection refused` / `connection timed out` / `HikariPool ... Connection is not available`
- 기동 실패(CrashLoop)면 → 먼저 `pod-crashloop.md` 체크리스트 1·2번과 교차 확인
- 다중 서비스 동시 발생이면 인프라 공통 원인(SG/RDS/연결 고갈) 가능성 높음

## 진단 (순서대로 — 진단 트리)

```bash
# 0. 에러 원문 확보
kubectl logs deploy/<svc> -n <ns> --tail=200 | grep -iE "connection|refused|timeout|hikari"
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

### 3. 엔드포인트·시크릿 정합 (T-073 패턴)

인프라 재생성 시 엔드포인트가 바뀌었는데 SM 시크릿이 구 주소인 경우:

```bash
kubectl get secret <svc-secret> -n <ns> -o jsonpath='{.data.SPRING_DATASOURCE_URL}' | base64 -d
# ↑ 1번에서 확인한 실제 RDS 엔드포인트와 비교
```
불일치 → AWS SM 값 갱신 → ExternalSecret force-sync (pod-crashloop.md 조치 참조).

### 4. ESO 동기화 상태 (T-030/031)

```bash
kubectl get clustersecretstore aws-secrets-manager   # Ready=True
kubectl get externalsecret -n <ns>                   # 전부 SecretSynced
```

### 5. 연결 수 고갈 (W4 학습 — db.t3.small 한도)

dev+staging+prod 동시 기동 시 연결 한도 초과 이력 있음 (W4 prod 재현 때 dev/staging 축소로 대응):

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
| 시크릿 불일치 | SM 갱신 → ExternalSecret force-sync → rollout restart |
| 연결 고갈 | 즉시: 비핵심 환경 replica 축소(git 경유). 구조: 인스턴스 증설 또는 Hikari pool 상한 조정 — team-lead 비용 결정 |

## 에스컬레이션 기준

- **전 서비스 동시 DB 장애** → 즉시 L2
- 연결 고갈 재발 (환경 축소로 임시 대응 중) → L2, 인스턴스 사이징 결정 요청
- RDS 자체 장애 1시간+ → L2 + AWS Support 검토

## 회피 방법

- SG는 terraform 단일 소스 유지 (D-026 — PR #90에서 terraform화 완료, 콘솔 수동 변경 금지)
- 윈도우에서 3환경 동시 기동 시 연결 수 모니터링을 체크리스트에 포함
- (후보) `DatabaseConnections` CloudWatch 알람 → Slack

## 사후 점검

- [ ] 원인을 Discovery Log(T-항목)에 기록
- [ ] 시크릿 갱신 시 다른 환경의 동일 키도 점검
- [ ] 연결 고갈이었다면 당시 환경별 replica 구성을 HISTORY에 기록 (Step 12 사이징 입력)
````

- [ ] **Step 2: 섹션 검증**

Run: `bash -c 'grep -c "^## " docs/runbooks/incidents/db-connection-failed.md'`
Expected: `6` (증상/진단/조치/에스컬레이션/회피/사후 — `### 1.` 하위 절은 미포함)

- [ ] **Step 3: 커밋**

```bash
git add docs/runbooks/incidents/db-connection-failed.md
git commit -m "docs(incident): DB 연결 실패 런북 — SG/시크릿/연결한도 진단 트리"
```

---

### Task 6: `docs/runbooks/on-call.md`

**Files:**
- Create: `docs/runbooks/on-call.md`

- [ ] **Step 1: 파일 작성** — 아래 내용 그대로 생성

````markdown
# On-call 체계 (gitops 트랙)

> 실제 팀 구성(트랙 1인 + team-lead) 기준 2레벨 간소화 — 2026-06-08 설계 결정.
> 알람 경로: Alertmanager → Slack `#synapse-gitops` (W3 Step 8에서 실 webhook 검증 완료)

## 에스컬레이션 레벨

| 레벨 | 담당 | 조건 | 응답 SLA | 해결 SLA |
|---|---|---|---|---|
| L1 | gitops 트랙 담당 (@VelkaressiaBlutkrone) | 알람 발생 / 이슈 접수 | 5분 (업무시간) | 30분 시도 후 판단 |
| L2 | team-lead | L1 30분 미해결 · 다중 서비스 영향 · 비용/사이징 결정 필요 | 10분 | 2시간 |

**즉시 L2 조건** (L1 시도 생략):
- 전 서비스 동시 장애 (DB/ESO/ArgoCD 컨트롤러 등 공통 인프라)
- prod 환경 장애
- 비용 결정이 필요한 조치 (인스턴스 증설, 노드 증설)

## 채널

| 용도 | 채널 |
|---|---|
| 알람 수신·1차 소통 | Slack `#synapse-gitops` |
| 장애 기록·서비스팀 이관 | GitHub 이슈 (`synapse-gitops`, 서비스 원인은 해당 `synapse-<svc>` 레포) |
| 크로스 트랙 통보 | `synapse-shared` 이슈 허브 (예: shared#20 패턴) |

## 야간/주말 정책

| 시간대 | 정책 |
|---|---|
| 평일 09:00–18:00 | L1 즉시 대응 |
| 평일 야간 | critical만 대응, warning은 다음 영업일 |
| 주말/공휴일 | critical만 대응 (L2 직행 가능) |

> critical = prod 장애·전 서비스 영향. 그 외는 warning으로 간주.

## 장애 유형 → 런북 인덱스

| 증상 | 런북 |
|---|---|
| Pod 재시작 반복 (CrashLoopBackOff) | [incidents/pod-crashloop.md](./incidents/pod-crashloop.md) |
| OOMKilled (Exit 137) | [incidents/oom-killed.md](./incidents/oom-killed.md) |
| OutOfSync 지속·sync Failed | [incidents/argocd-sync-failed.md](./incidents/argocd-sync-failed.md) |
| 인증서 만료·TLS 오류 | [incidents/cert-expired.md](./incidents/cert-expired.md) |
| DB connection refused/timeout | [incidents/db-connection-failed.md](./incidents/db-connection-failed.md) |
| 그 외 인프라 이슈 | [troubleshooting-infra.md](./troubleshooting-infra.md) (T-카탈로그) |

## 알람 경로 테스트 — ⚠️ 윈도우 실행 항목 (클러스터 필요)

```bash
# Alertmanager pod명 확인 (릴리스명에 따라 다름)
kubectl get pods -n monitoring | grep alertmanager
# 테스트 알람 주입 — severity=warning 사용 (실 on-call 소음 방지)
kubectl exec -n monitoring <alertmanager-pod> -- amtool alert add \
  alertname=OncallPathTest severity=warning namespace=synapse-staging \
  --annotation=summary="on-call 경로 테스트 (무시 가능)" \
  --alertmanager.url=http://localhost:9093
# → Slack #synapse-gitops 수신 확인 (W5_WINDOW_2.md Phase 5)
```

## 사후 (포스트모템) 규칙

- 30분 이상 장애·prod 장애는 GitHub 이슈에 타임라인 기록 (감지→진단→조치→복구 시각)
- 신규 원인은 `troubleshooting-infra.md` Discovery Log에 T-항목 추가
- 런북이 부족했다면 해당 incidents 문서를 같은 PR에서 보강
````

- [ ] **Step 2: 섹션 검증**

Run: `bash -c 'grep -c "^## " docs/runbooks/on-call.md'`
Expected: `6`

- [ ] **Step 3: 커밋**

```bash
git add docs/runbooks/on-call.md
git commit -m "docs(runbook): on-call 체계 — 2레벨 간소화 + 장애 런북 인덱스"
```

---

### Task 7: `docs/runbooks/W5_WINDOW_2.md`

**Files:**
- Create: `docs/runbooks/W5_WINDOW_2.md`

- [ ] **Step 1: 파일 작성** — 아래 내용 그대로 생성

````markdown
# W5 검증 윈도우 2 — 실행 런북

대상: #91 #92 #121 #122 + Step 11 라이브 항목 / 통보 허브: synapse-shared#20
원칙: Phase 0는 무비용(윈도우 전). Phase 1 진입 시 과금 ON → Phase 6 destroy로 차단.
선행: 윈도우 1 결과(`W5_CLEARANCE_WINDOW.md`, 2026-06-05) — #120 close, #121/#122 코드 머지(PR #124), IU PR write-back 전환(PR #127).

## Phase 0 — 선결 조건 확인 (무비용, 윈도우 전)

- [ ] gateway ECR 이미지 존재: `aws ecr describe-images --repository-name synapse/gateway --query 'imageDetails[].imageTags' --region ap-northeast-2`
- [ ] gateway SM 시크릿 시드: `aws secretsmanager describe-secret --secret-id synapse/dev/gateway/redis-password` (미시드면 gateway팀에 윈도우 전 요청 — gateway#4)
- [ ] platform-svc dev-latest 재빌드 확인: ECR `imagePushedAt` > `application-staging.yml` main 머지 시각
- [ ] frontend ECR 이미지 존재 (06-07 bump 3건 — 형식적 재확인)
- [ ] `GITOPS_TOKEN` 시크릿 유효 (repo Settings → Secrets, IU PR write-back 필수)
- [ ] ACM import IAM 권한 + 리전(ap-northeast-2) 점검 (윈도우 1과 동일)
- [ ] team-lead 일정 협의 — Phase 5 따라하기 검증 (불가 시 폴백: 비동기 후속)
- [ ] sim 브랜치 준비: `git checkout -b sim/incident-window2 origin/main` → `apps/engagement-svc/overlays/staging/kustomization.yaml` 의 namespace를 `synapse-sim` 으로 변경 후 push (main 머지 금지)

## Phase 1 — bring-up (과금 ON)

- [ ] `bash scripts/bring-up.sh` — alb-controller·image-updater 페이즈 포함 (PR #124 경로 **첫 라이브 검증**)
- [ ] ALB 컨트롤러 기동: `kubectl get deploy -n kube-system aws-load-balancer-controller` → Available
- [ ] IU ECR 자격: `kubectl logs -n argocd deploy/argocd-image-updater | grep -i "basic auth"` → 에러 없음
- [ ] `kubectl get applications -n argocd` — dev 7 + staging 7 + prod 7 등록 확인

## Phase 2 — #91/#92 fleet 검증

- [ ] (team-lead) `bash scripts/verify-argocd-deploy.sh synapse-dev` → **7앱 ALL PASSED** (5svc+gateway+frontend)
- [ ] gateway-dev 기동 확인 — 윈도우 1 갭(ECR·SM) 해소 검증 (gateway#4)
- [ ] staging sync 확인 (auto) → `verify-argocd-deploy.sh synapse-staging` → **7앱** (5svc+frontend+schema-registry)
- [ ] platform-svc-staging Running (= #92 해소: application-staging.yml main 머지본 반영)
- [ ] 롤백 1회: `kubectl -n synapse-dev rollout undo deploy/<svc>` → 복구 <3분
- [ ] → #91·#92 close (결과 코멘트)

## Phase 3 — #121 외부 노출 완주 (ALB 의존 · Phase 4와 병행 가능)

- [ ] nip.io ingress 2종 apply (cert-arn 미설정 → ALB 프로비저닝 트리거)
- [ ] `kubectl get ingress -A` → 공유 ALB DNS 확보 (group.name=synapse-nipio)
- [ ] `bash scripts/gen-nipio-selfsigned.sh <ALB_DNS>` → `CERT_ARN=...`
- [ ] ingress `<ALB_IP>`·`<ACM_ARN>` 치환 → 재apply
- [ ] `curl --cacert .nipio-certs/ca.crt https://argocd.<IP>.nip.io` → 200 + 체인 유효
- [ ] `curl --cacert .nipio-certs/ca.crt https://dev.<IP>.nip.io/actuator/health` → gateway 도달
- [ ] GitHub webhook ping → `/api/webhook` 200
- [ ] → #121 close

## Phase 4 — #122 IU write-back E2E (Phase 3과 병행 가능)

- [ ] 대상 svc의 ECR에 새 태그 푸시 (IU 전략에 맞춰 — 기존 매니페스트 재태그):
  ```bash
  MANIFEST=$(aws ecr batch-get-image --repository-name synapse/<svc> --image-ids imageTag=dev-latest --query 'images[0].imageManifest' --output text)
  aws ecr put-image --repository-name synapse/<svc> --image-tag <new-tag> --image-manifest "$MANIFEST"
  ```
- [ ] IU 감지 → `image-updater-<svc>` 브랜치 push 확인: `git ls-remote origin 'image-updater-*'`
- [ ] `image-updater-pr.yml` 이 PR 자동 생성 (#127 경로 **첫 라이브 검증**): `gh pr list --head image-updater-<svc>`
- [ ] PR 머지 → dev 반영 시간 측정 (푸시→Pod 교체) → **≤5분** 기록
- [ ] 롤백: write-back 커밋 revert PR → 이전 태그 복귀 확인
- [ ] → #122 close

## Phase 5 — Step 11 라이브 항목 (Phase 2 완료 후)

> 시뮬레이션은 **전용 sim Application** — staging은 selfHeal=true라 직접 주입 불가(즉시 원복). fleet 무접촉.

- [ ] 스냅샷: `kubectl get pods -n synapse-staging -o wide > /tmp/staging-before.txt`
- [ ] sim 앱 생성 (manual sync — selfHeal 없음):
  ```bash
  argocd app create incident-sim \
    --repo https://github.com/team-project-final/synapse-gitops \
    --revision sim/incident-window2 \
    --path apps/engagement-svc/overlays/staging \
    --dest-server https://kubernetes.default.svc --dest-namespace synapse-sim \
    --sync-option CreateNamespace=true
  argocd app sync incident-sim   # 기동 확인 (Java svc — ESO/RDS/MSK 실의존 동작)
  ```
- [ ] **시나리오 1 CrashLoop**: `kubectl set env deploy/engagement-svc -n synapse-sim SPRING_DATASOURCE_URL=jdbc:broken` → `incidents/pod-crashloop.md` 따라 진단 → 원복(`kubectl set env ... SPRING_DATASOURCE_URL-` 후 re-sync)
- [ ] **시나리오 2 OOM**: limit 10Mi 패치 → `incidents/oom-killed.md` 따라 진단 → `argocd app sync incident-sim` 으로 원복
  ```bash
  kubectl patch deploy engagement-svc -n synapse-sim --type=json \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"10Mi"}]'
  ```
- [ ] **시나리오 3 sync 실패**: sim 브랜치에 존재하지 않는 리소스 참조 커밋 push → `argocd app sync incident-sim` Failed → `incidents/argocd-sync-failed.md` 따라 진단 → revert push → sync OK
- [ ] **team-lead 따라하기**: 시나리오 1택 재현 → team-lead가 런북만 보고 독립 복구 (1회 통과 = Step 11 검증 완료. 당일 불가 시: 비동기 후속으로 분리 기록)
- [ ] **알람 경로 테스트**: `on-call.md` 절차 (amtool warning) → Slack `#synapse-gitops` 수신 확인
- [ ] 정리: `argocd app delete incident-sim --yes` → `kubectl delete ns synapse-sim` → `git push origin --delete sim/incident-window2`
- [ ] fleet 무접촉 확인: `diff /tmp/staging-before.txt <(kubectl get pods -n synapse-staging -o wide)`

## Phase 6 — 마감

- [ ] 이슈별 결과 코멘트: #91 #92 #121 #122 (+close), gateway#4 결과 통보
- [ ] synapse-shared#20 통보 코멘트
- [ ] `TASK_gitops.md` Step 11 라이브 항목 체크 + `HISTORY_gitops.md` 윈도우 2 기록
- [ ] `bash scripts/bring-up.sh --destroy` → `terraform -chdir=infra/aws/dev show` 빈 상태 확인
````

- [ ] **Step 2: Phase 구조 검증**

Run: `bash -c 'grep -c "^## Phase" docs/runbooks/W5_WINDOW_2.md'`
Expected: `7` (Phase 0~6)

- [ ] **Step 3: 커밋**

```bash
git add docs/runbooks/W5_WINDOW_2.md
git commit -m "docs(runbook): W5 검증 윈도우 2 — #91/#92/#121/#122 + Step 11 라이브 항목 통합 (Phase 0~6)"
```

---

### Task 8: TASK 문서 정합 + 가이드 주석

**Files:**
- Modify: `docs/project-management/task/TASK_gitops.md` (Step 3 주석, Step 11 섹션)
- Modify: `docs/runbooks/step11-operational-runbook.md` (상단 결정 변경 공지)

- [ ] **Step 1: TASK_gitops.md Step 11 갱신**

Step 11의 Done When과 Status를 다음으로 교체 (라인 246~255 부근):

```markdown
- **Done When**:
  - [x] 장애 시나리오 5개 이상 Runbook 작성 (Pod CrashLoop, OOM, sync 실패, 인증서 만료, DB 연결 실패) — `docs/runbooks/incidents/` 5종
  - [x] 각 시나리오에 단계별 진단/조치/에스컬레이션 기준 — 6섹션 골격(증상/진단/조치/에스컬레이션/회피/사후)
  - [ ] team-lead가 Runbook 따라하기 1회 검증 — 윈도우 2 Phase 5 (`docs/runbooks/W5_WINDOW_2.md`)
  - [x] On-call 연락처/Slack 채널 정리 — `docs/runbooks/on-call.md` (2레벨 간소화, 알람 경로 테스트만 윈도우 항목)
  - [x] PR 코멘트로 diff 요약 GitHub Action 도입 (선택) — W1 이월 (D-041) — 기구현 확인: `validate-manifests.yml` diff-comment job (커밋 47a7c67), PR #129 동작 확인
```

Status 라인을 다음으로 교체:

```markdown
**Status**: [ ] Not Started / [x] In Progress / [ ] Done (문서 산출물 완료. 시뮬레이션·team-lead 검증·알람 테스트는 윈도우 2 Phase 5 — 2026-06-08 스펙)
```

- [ ] **Step 2: TASK_gitops.md Step 3 주석 갱신**

라인 59의 기존 주석 아래(또는 해당 주석을 다음으로 교체):

```markdown
  <!-- 2026-06-08: PR diff 요약은 기구현 확인 — validate-manifests.yml diff-comment job(47a7c67). Step 11에서 완료 처리. -->
```

- [ ] **Step 3: step11-operational-runbook.md 상단 공지 추가**

제목 바로 아래 blockquote 다음에 추가:

```markdown
> **2026-06-08 결정 변경 (스펙: `docs/superpowers/specs/2026-06-08-w5-step11-runbook-window2-design.md`):**
> ① 11-B 산출물 작성 완료 — `incidents/` 5종 + `on-call.md` (인증서 시나리오는 cert-manager가 아닌 **self-signed ACM import 실스택** 기준).
> ② 11-C 시뮬레이션의 staging 직접 주입 방식은 **selfHeal=true와 충돌해 폐기** — 전용 sim Application 방식으로 대체 (`W5_WINDOW_2.md` Phase 5).
> ③ 11-D는 실제 팀 구성 기준 2레벨로 간소화 (PagerDuty 제외) — `on-call.md`.
```

- [ ] **Step 4: 커밋**

```bash
git add docs/project-management/task/TASK_gitops.md docs/runbooks/step11-operational-runbook.md
git commit -m "docs(task): Step 11 진행 반영 — 문서 산출물 완료, 라이브 항목은 윈도우 2 이관"
```

---

### Task 9: 최종 검증 + PR

**Files:** 없음 (검증·푸시만)

- [ ] **Step 1: 산출물 존재·섹션 일괄 검증**

```bash
ls docs/runbooks/incidents/   # 5개 파일
for f in docs/runbooks/incidents/*.md; do
  echo "=== $f ==="; grep -c "^## " "$f"
done   # 각 6 이상
grep -c "^## Phase" docs/runbooks/W5_WINDOW_2.md   # 7
```

- [ ] **Step 2: 상호 링크 무결성**

```bash
grep -o 'incidents/[a-z-]*\.md' docs/runbooks/on-call.md | sort -u   # 5개 전부 존재하는 파일명인지 대조
```

- [ ] **Step 3: push + PR 생성**

```bash
git push -u origin docs/w5-step11-window2
gh pr create --title "docs(w5): Step 11 장애 런북 5종 + on-call + 검증 윈도우 2 런북" --body "..."
```

PR 본문에 포함: 스펙 링크, incidents 5종 + on-call + W5_WINDOW_2 요약, TASK Step 11 진행 상태, 윈도우 2는 차기 세션 실행(과금) 명시.

- [ ] **Step 4: CI 통과 확인 후 머지**

Run: `gh pr checks --watch`
Expected: validate-manifests 통과 (docs만 변경 — kustomize/yamllint 영향 없음)
