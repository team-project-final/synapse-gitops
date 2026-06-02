# Design: ArgoCD 부트스트랩 → dev/staging verify 5/5 (#91, FR-TL-402)

> **작성**: 2026-06-02 · **owner**: @VelkaressiaBlutkrone (gitops)
> **대상 이슈**: #91 [P0] ArgoCD 부트스트랩 → dev/staging verify-argocd-deploy 5/5 (FR-TL-402)
> **선행(완료)**: #87/#88/#89 (PR #90, D-045) — bastion/operator EKS 접근·cluster SG·브로커 ConfigMap
> **관련**: `scripts/bring-up.sh`(기존 오케스트레이터), shared `scripts/verify-argocd-deploy.sh`, `docs/runbooks/w1-argocd-bootstrap-runbook.md`

---

## 1. 배경 & 목표

#87/#88/#89 해소로 재apply된 클러스터에서 **ArgoCD 부트스트랩 → 서비스 sync → 배포 검증**이 가능해졌다(FR-TL-402의 실제 잔여). 기존 `scripts/bring-up.sh`가 이미 부트스트랩 전 과정(argocd/eso/oidc-fix/manifests/image-updater/observability)을 구현하므로, **본 작업은 신규 구축이 아니라 (a) PR #90과의 정합 + (b) RDS 증설 + (c) 실행·검증**이다.

**성공 정의**: 재apply window에서 부트스트랩 완료 후 `verify-argocd-deploy.sh synapse-dev` **5/5** + staging 수동 Sync **5/5** + 롤백 1회(<3분) → FR-TL-402 충족. 검증 후 destroy.

## 2. 비목표

- **image-updater E2E**(write-back)·**observability 스택 완전 검증** — bring-up에 phase는 있으나 5/5 핵심 아님. 선택 실행(시간 여유 시), 본 spec acceptance 아님.
- **서비스 코드 변경** — 5개 서비스 ECR 이미지(4~10개씩)는 이미 존재. 배포물은 서비스 owner 트랙. 본 spec은 gitops 부트스트랩 + 배포 검증.
- **실 도메인** — port-forward/tunnel 대체(W1 이월 유지).

## 3. 결정 사항 (브레인스토밍 확정)

| # | 결정 | 비고 |
|---|------|------|
| 검증 범위 | **dev 5/5 + staging Sync 5/5 + 롤백** (이슈 원안) | RDS 증설로 연결 확보 |
| RDS | **db.t3.small → db.t3.medium** | D-043: small은 dev+staging+prod 동시 연결 고갈. medium으로 dev+staging 여유 |
| 실행 도구 | 기존 `scripts/bring-up.sh` 재사용 + 정합 | 신규 부트스트랩 스크립트 작성 안 함 |
| 운영자 접근 | SSM 터널(`phase_tunnel`, 로컬 kubectl) | #87 access entry + 터널로 로컬 argocd/kubectl 도달 |

## 4. 컴포넌트 1 — RDS 증설 + bring-up.sh 정합 (코드)

**파일**: `infra/aws/dev/terraform.tfvars`, `scripts/bring-up.sh`

- **RDS**: `terraform.tfvars`의 `rds_instance_class = "db.t3.small"` → `"db.t3.medium"`.
- **`phase_access_entry` 제거**: `#87`의 `bootstrap_cluster_creator_admin_permissions = true`로 클러스터 생성자(=terraform 실행 주체 synapse-admin=운영자)가 이미 cluster admin. 운영자 access entry 별도 생성 불필요(중복).
- **`phase_sg` 제거**: `#89` terraform이 cluster SG → RDS/Redis/OpenSearch/MSK ingress 소유. `phase_sg`는 동일 규칙을 imperative로 재시도해 "already exists"만 출력하는 dead code.
- **`phase_kafka_config` 추가**: `#88` `infra/aws/dev/k8s-kafka-config/`(ns ×3 + kafka-brokers ConfigMap)을 **터널 kubeconfig로 적용**. `phase_manifests` **앞**에 배치(ArgoCD가 앱 배포 시 ConfigMap·ns 선존재 보장). PR #90 모듈의 provider `config_path`는 터널 kubeconfig 경로로 동작하도록 KUBECONFIG/-var 처리(plan에서 구체화).
- **`PHASES` 배열 갱신**: `(terraform tunnel argocd eso oidc-fix kafka-config manifests image-updater observability status)` — access-entry·sg 제거, kafka-config 삽입.

**Acceptance (컴포넌트 1)**:
- [ ] tfvars RDS medium.
- [ ] bring-up.sh에서 phase_access_entry·phase_sg 제거(PHASES 배열 포함), phase_kafka_config 추가(manifests 앞).
- [ ] `bash scripts/bring-up.sh --dry-run` 류로 phase 순서/구문 확인(무과금).

## 5. 컴포넌트 2 — 부트스트랩 실행 (라이브 window)

정합된 bring-up.sh 순서:
`terraform(apply, RDS medium) → tunnel(SSM 포트포워딩) → argocd(HA install --server-side + --insecure) → eso(helm + IRSA) → oidc-fix(ESO role OIDC 갱신) → kafka-config(#88 ConfigMap) → manifests(ClusterSecretStore + projects + applicationset dev auto-sync + staging) → wait ExternalSecret Ready/Synced·Healthy`.

**Acceptance (컴포넌트 2)**:
- [ ] 라이브: bring-up.sh로 ArgoCD HA + ESO + 5개 App(dev) 등록, ExternalSecret SecretSynced.
- [ ] dev App 5개 Synced·Healthy 도달.

## 6. 컴포넌트 3 — 검증 + 알려진 caveat

- `bash scripts/verify-argocd-deploy.sh synapse-dev` → **5/5 PASS**(체크: App Sync=Synced·Health=Healthy / Pod Running·restarts≤3 / ExternalSecret SecretSynced).
- staging: `argocd app sync synapse-<svc>-staging`(수동, AppProject staging=manual) → `verify-argocd-deploy.sh synapse-staging` **5/5** + **롤백 1회**(`argocd app rollback` 또는 git revert→sync, <3분).
- **알려진 caveat (window 처리)**:
  - **platform-svc 스키마**: W4(D-043) prod 프로파일 Hibernate `validate`가 빈 DB에서 `missing table` 크래시 → `pg_dump --schema-only` 시드 필요였음. **dev/staging 프로파일이 `ddl-auto=update`/Flyway면 무관**. window 착수 시 platform-svc dev 프로파일 확인 → 필요 시 스키마 시드(fallback 런북 절차 준비).
  - **연결 수**: db.t3.medium(~한도 상향)으로 dev+staging 동시 수용. 그래도 압박 시 replicas/풀 축소.

**Acceptance (컴포넌트 3)**:
- [ ] dev 5/5 PASS 캡처.
- [ ] staging 5/5 PASS + 롤백 1회(<3분) 캡처.

## 7. 컴포넌트 4 — 마감

- 이슈 #91 결과 코멘트(증거) + close(PR Closes).
- `terraform destroy`(또는 `bring-up.sh --destroy`) 과금 차단.
- HISTORY **D-046**, PR.

**Acceptance (컴포넌트 4)**:
- [ ] #91 close, destroy로 과금 0, HISTORY D-046, PR.

## 8. 미해결/의존

- **서비스 배포물 최신성**: ECR 이미지는 존재하나 최신 Kafka 통합 코드(engagement Consumer·knowledge Producer 등) 반영은 서비스 owner 트랙. 본 spec은 현 ECR 이미지로 부트스트랩·5/5(Synced·Healthy·Running) 검증. Kafka 이벤트 E2E 동작은 별도(서비스 준비도 의존).
- **터널 안정성**: SSM 포트포워딩(`scripts/lib/eks-tunnel.sh`)이 장시간 유지돼야 manifests/verify 수행. 끊기면 재연결(`--from manifests` 재개).
- **#88 ConfigMap의 터널 적용**: PR #90 모듈은 bastion(`~/.kube/config`) 전제 → 터널 실행 시 KUBECONFIG 경로 정합 필요(plan에서 처리).
