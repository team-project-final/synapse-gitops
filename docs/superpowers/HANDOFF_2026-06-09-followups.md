# 핸드오프: 2026-06-09 세션 — W5 잔여 완료 + 저우선 후속

> **작성**: 2026-06-09 · **상태**: W5 잔여 5건 전부 처리, **OPEN 이슈 0건** · **다음 세션 대상**: 저우선 후속 3건
> **정본 허브**: synapse-shared `HANDOFF_HUB.md`(team-lead 유지)

---

## 1. 이번 세션 작업 요약

브레인스토밍 → spec → plan → subagent 실행으로 W5 잔여 백로그를 정리·완주.

### 머지된 PR (synapse-gitops)
| PR | 내용 |
|----|------|
| #158 | dev overlay 6앱 SHA/dev-latest → semver `1.0.0` 핀 |
| #159 | HANDOFF_W5 잔여 정본 표 + spec/plan |
| #160 | staging 전용 RDS(`synapse-staging-postgres`) terraform + 오버레이 5앱 전환 |
| #161 | engagement-svc dev overlay `1.0.1`→`1.0.0`(phantom 태그 정정) |
| #162 | HANDOFF_W5 표 라이브 결과 정합 |

### 이슈 처리 (전부 close)
| 이슈 | 처리 |
|------|------|
| #126 ruleset | 옵션3 App전환 완료, Maintain bypass 수용(팀 결정) |
| #155 Step11 드릴 | operator 라이브 드릴(CrashLoop·OOM 재현·복구) |
| #156 staging DB 분리 | 전용 RDS 인스턴스 격리 구현·검증 |
| #157 SHA→semver 핀 | ECR 6앱 1.0.0 재태그 + 라이브 배포 검증 |
| **#144 learning-ai** | **2차 라이브에서 fix 검증·close**(아래) |

### #144 (learning-ai ssl_context) 해결 경위 — 핵심 교훈
1. 1차 라이브: 핀된 learning-ai(=`3774e2e6`)가 **여전히 ssl_context CrashLoop** → "앱팀 PR #63 fix 무효" 입증.
2. 원인 규명: `3774e2e6`은 `fix(avro) #64` 빌드라 **ssl_context 수정이 애초에 미포함**(PR #63이 그 이미지에 안 들어감). **교훈: 코드 머지 ≠ 빌드 반영 — 어느 커밋이 이미지가 됐는지 SHA 대조 필수.**
3. 실수정: `synapse-learning-svc` PR #67 — 신규 `app/kafka/ssl_support.py`(`kafka_ssl_context()`=SSL시 `create_ssl_context()`) + producer/consumer에 `ssl_context=` 전달 + **TLS 단위테스트**(SSL시 `ssl_context≠None` 단언, 앱팀이 빠뜨렸던 검증). mypy `no-any-return`은 `cast`로 해소.
4. CI green → admin 머지(리뷰 우회, velka 승인) → deploy.yml이 ECR `learning-ai:9140e597` 푸시 + gitops bump.
5. 2차 라이브: `9140e597` 배포 → **learning-ai 1/1 Running·RESTARTS 0·Healthy, ssl_context 에러 0건** → **#144 close**.

### 라이브 윈도우 운영 메모 (재발 방지)
- **bring-up이 자동생성 안 하는 것**: ① 서비스별 DB 5종(`synapse_platform/engagement/knowledge/learning/ai`) — psql `CREATE DATABASE` 수동(미생성 시 Spring `database does not exist` 크래시) ② **MSK 토픽 9종** — 미생성 시 aiokafka 컨슈머 `UnknownTopicOrPartitionError` 크래시(Spring은 경고만).
- **selfHeal/ApplicationSet**: resource 패치(limit 등) 즉시 자동원복(드리프트 복구). `set env` override는 3-way merge로 미원복 → 직접 제거.
- **ECR 재태그**: `batch-get-image`→`put-image`는 매니페스트 재직렬화 → manifest digest 달라지나 config·layer 동일. 검증은 config digest 대조.
- **MSK 토픽 생성(2차 윈도우 검증분)**: 클러스터 내 `apache/kafka:3.9.0` 파드 + `security.protocol=SSL` client.properties로 `kafka-topics.sh --bootstrap-server <b-1..:9094,b-2..:9094> --create --partitions 3 --replication-factor 2`.

---

## 2. 저우선 후속 3건 (다음 세션 이관)

### 후속 A — learning-card-staging 조사
- **증상**: `synapse-learning-card-staging` = Degraded(라이브 윈도우). staging RDS 연결은 정상(JDBC 로그로 `synapse_learning` 확인 → DB 무관). dev는 Healthy.
- **정적 분석(완료)**: staging overlay는 dev 대비 **replica 2 · profile `staging` · `newTag: dev-latest`**(dev=9140e597). 차이가 크래시 원인일 수 있음.
- **다음 세션 next-action**: 라이브 윈도우에서 `kubectl -n synapse-staging logs deploy/learning-card --previous --tail=50` 로 크래시 근본원인 확인. 가설: ① `dev-latest`가 가리키는 이미지 문제 ② staging 프로파일 설정 ③ replica 2 리소스. (DB·Kafka 토픽 선생성 후 관찰.)
- **우선순위**: 낮음(staging 한정, dev 정상).

### 후속 B — learning-ai/card semver 재핀 (선택)
- **현재**: deploy-service.yml write-back으로 learning-ai/card dev overlay = SHA `9140e597`(#157 semver 1.0.0 핀에서 회귀).
- **영향**: IU `semver` 전략에서 이 2앱 `Invalid Semantic Version` skip(자동 업데이트 안 됨). engagement·knowledge·platform·gateway·frontend는 1.0.0 유지.
- **근본 긴장**: `deploy-service.yml`(shared)이 **SHA 태깅** ↔ IU `semver` 전략 충돌. 매 배포마다 SHA로 회귀 → semver 핀은 일시적.
- **옵션**:
  - (a) **임시**: ECR `9140e597`→`1.0.0` 재태그 + overlay `1.0.0` 정정(1회, 다음 배포에 또 회귀).
  - (b) **근본**: `deploy-service.yml`을 semver 태깅으로 전환(shared, 크로스레포 — #126처럼 팀 조율).
  - (c) **근본**: IU 전략을 `digest`(또는 `newest-build`)로 전환(전 앱, mutable 태그 추적).
- **다음 세션 next-action**: 팀과 SHA vs semver 전략 정리(b/c) → 결정 후 일괄 적용. 그 전까진 (a)도 무의미(회귀).
- **우선순위**: 낮음(런타임 영향 없음, IU 자동업데이트만).

### 후속 C — Kafka 토픽 자동 프로비저닝
- **현재**: bring-up이 MSK 토픽 9종을 자동생성 안 함 → 매 윈도우 수동(클러스터 내 kafka 파드 또는 bastion). 미생성 시 aiokafka 컨슈머(learning-ai) 크래시.
- **정본**: `infra/aws/dev/kafka-topics/`(Mongey/kafka provider, bastion 실행) terraform이 토픽 9종 선언 — 단 bring-up에 미통합.
- **다음 세션 next-action**: `scripts/bring-up.sh`에 토픽 생성 phase 추가. 두 경로:
  - bastion SSM로 `terraform -chdir=infra/aws/dev/kafka-topics apply`(정본 declarative), 또는
  - 클러스터 내 kafka Job(`apache/kafka` + SSL, 위 §1 명령). DB 5종 생성도 함께 자동화 검토(동일 성격).
- **우선순위**: 낮음~중(매 윈도우 반복 수작업 제거 — 라이브 효율).

---

## 3. 레포 상태

- **OPEN 이슈**: **0건** (#144 포함 W5 잔여 전부 close).
- **main HEAD**: PR #162 머지분 + deploy bump(learning-ai/card → `9140e597`).
- **CI**: main 보호(PR + `validate`/diff-comment/parse).
- **클러스터**: destroy 완료(과금 0). S3 state + DynamoDB lock만 유지.
- **설계/플랜**: `docs/superpowers/specs/2026-06-09-*`, `docs/superpowers/plans/2026-06-09-*`.

### 다음 라이브 윈도우 체크리스트 (반복 수작업)
1. `bash scripts/bring-up.sh --to manifests`
2. 터널: `source scripts/lib/eks-tunnel.sh; tunnel_up`
3. **DB 5종 생성**(psql 파드, dev + staging RDS 각각)
4. **Kafka 토픽 9종 생성**(kafka 파드 SSL) ← 후속 C로 자동화 대상
5. 검증 → `bash scripts/bring-up.sh --destroy`
