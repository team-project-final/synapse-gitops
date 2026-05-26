# TASK: @VelkaressiaBlutkrone

> **담당 트랙**: gitops (ArgoCD ApplicationSet + Kustomize 기반 GitOps 운영)
> **GitHub Repository**: [synapse-gitops](https://github.com/team-project-final/synapse-gitops)
> **기간**: 2026-05-12 ~ 2026-06-12 (W1 ~ W5, 23 영업일)
> **관련 문서**: [SCOPE](../scope/SCOPE_gitops.md) | [PRD_W1](../prd/PRD_W1.md) | [WORKFLOW_W1](../workflow/WORKFLOW_gitops_W1.md) | [KICKOFF](../KICKOFF.md) | [HISTORY](../history/HISTORY_gitops.md)

---

## W1 (2026-05-12 ~ 2026-05-16, 5 영업일) — ArgoCD 부트스트랩

### Step 1: ArgoCD 클러스터 부트스트랩

- **Step Goal**: EKS에 ArgoCD가 설치되어 webhook + UI + CLI 모두 동작한다.
- **Done When**:
  - [x] ArgoCD HA 모드 설치 완료 (helm 또는 install.yaml)
  - [x] argocd-server NLB로 외부 노출 + TLS (옵션 2: self-signed)
  - [x] admin 비밀번호 회전 + AWS Secrets Manager 저장
  - [x] CLI 로그인 성공
  - [ ] webhook endpoint 외부 도달 확인  <!-- W2 옵션1 마이그레이션과 함께 이월 -->
- **Scope**:
  - In Scope: ArgoCD 설치, HA 구성, 외부 노출, 인증
  - Out of Scope: 실제 앱 sync, ApplicationSet 구성
- **Input**: EKS 클러스터, ACM 인증서, DNS 도메인
- **Duration**: 1.5일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (옵션2 적용 + kind B-2 실증 완료, FR-GO-102 일부 W2 이월. 실 EKS B-1은 결제수단 verification 후)

---

### Step 2: app-of-apps / ApplicationSet 골격

- **Step Goal**: 5개 앱이 ApplicationSet 한 번의 정의로 dev 환경에 sync된다(빈 manifest라도 OK).
- **Done When**:
  - [ ] `argocd/apps/root.yaml` (app-of-apps) 정의  <!-- 선택 항목, ApplicationSet 단독 운영으로 결정 -->
  - [x] `argocd/applicationset.yaml` 정의 (matrix 5svc × [dev], C3)
  - [x] 5개 앱이 ArgoCD UI에 표시됨 (bootstrap-argocd.sh APP_COUNT 검증)
  - [x] git 푸시 → ArgoCD 자동 인식 확인 (polling 3분)
- **Scope**:
  - In Scope: ApplicationSet, generators (list 또는 git), template
  - Out of Scope: 실제 워크로드 manifest 채움 (W2)
- **Input**: ArgoCD 설치 완료(Step 1), 5개 앱 디렉토리 구조
- **Duration**: 1.5일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done

---

### Step 3: validate-manifests CI 강화

- **Step Goal**: PR이 들어오면 kustomize/스키마/모범사례 검증이 모두 자동 실행된다.
- **Done When**:
  - [x] kubeconform 추가 (Kubernetes 스키마 + CRD 카탈로그 검증)
  - [x] yamllint 룰 보강 (`.yamllint`: line-length 160, indentation 2)
  - [ ] PR 코멘트로 diff 요약 (선택)  <!-- W3 이월 (선택 항목) -->
  - [x] CI 실패 시 머지 차단 (scripts/setup-branch-protection.sh, Task 13)
- **Scope**:
  - In Scope: GitHub Actions 워크플로우 보강
  - Out of Scope: 보안 스캔(SBOM, image scan) — 별도 트랙
- **Input**: 기존 `validate-manifests.yml`
- **Duration**: 1일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (PR diff 코멘트는 W3 이월)

---

## W2 (2026-05-19 ~ 2026-05-23, 5 영업일) — dev 환경 자동 배포 + Secret

### Step 4: dev overlay 5개 앱 완성

- **Step Goal**: 5개 앱이 dev 환경에 실제 워크로드로 sync되어 동작한다.
- **Done When**:
  - [x] `apps/{app}/overlays/dev/kustomization.yaml` 5개 작성
  - [x] Deployment / Service / ConfigMap 매니페스트 base 완성
  - [x] ArgoCD UI에서 5개 모두 Synced + Healthy (kind 검증)
  - [x] EKS 배포: 3/5 Healthy (engagement-svc, knowledge-svc, learning-card)
  - [ ] EKS 배포: platform-svc Healthy (앱 코드 수정 필요 — mfa_credentials 테이블)
  - [ ] EKS 배포: learning-ai Healthy (앱 코드 수정 필요 — Python 기동 문제)
  - [ ] Pod에 트래픽 도달 확인 (Ingress 또는 port-forward)
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [x] In Progress / [ ] Done (EKS 3/5 Healthy, 2개 앱 레벨 문제 잔존)

---

### Step 5: Secret 관리 (External Secrets Operator)

- **Step Goal**: 모든 시크릿이 AWS Secrets Manager에 저장되고 ESO가 자동 동기화한다.
- **Done When**:
  - [x] External Secrets Operator 설치 (kind: fake provider 검증 완료)
  - [x] ClusterSecretStore (AWS Secrets Manager backend) 구성 — 매니페스트 작성 완료 (`infra/external-secrets/cluster-secret-store.yaml`)
  - [x] 5개 앱별 ExternalSecret 매니페스트 작성
  - [x] dev overlay에서 secretStoreRef → `aws-secrets-manager` 교체 완료
  - [x] ESO 컨트롤러 EKS Helm 설치 + IRSA 완료 (Role: `synapse-dev-eso-role`, Policy: `synapse-dev-eso-secrets-read`)
  - [x] ClusterSecretStore Valid + 5개 ExternalSecret SecretSynced 확인 (8차 세션 재확인)
  - [x] git에 평문 시크릿 0건 확인 (`gitleaks` 8.30.1 — 114 commits, no leaks, 2026-05-26)
  - [x] EKS 인증 모드 API_AND_CONFIG_MAP + access entry 설정 (D-027)
- **Duration**: 1.5일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (EKS 실배포 완료: ESO Helm + IRSA + ClusterSecretStore Valid + 5개 SecretSynced)

---

### Step 6: 이미지 태그 자동 sync

- **Step Goal**: svc 레포에서 새 이미지가 빌드되면 dev 환경이 자동으로 업데이트된다.
- **Done When**:
  - [x] ArgoCD Image Updater 설치 + 5개 앱 annotation (kind 검증 완료)
  - [x] ImageUpdater CR 작성 (`argocd/image-updater.yaml`)
  - [x] ECR 이미지 경로로 교체 완료 (ApplicationSet + dev overlay)
  - [x] write-back-method: git + write-back-target: kustomization 설정
  - [ ] 새 이미지 푸시 → 5분 이내 dev에 반영 확인 — EKS 배포 후
  - [x] 태그 변경 이력이 git log에 남음 (git write-back 설정)
- **Duration**: 1.5일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (매니페스트 + ECR 교체 완료, E2E 검증은 EKS 배포 후)

---

## W3 (2026-05-26 ~ 2026-05-29, 4 영업일 — 5/25 부처님오신날 제외) — staging + Observability

### Step 7: staging 환경 overlay

- **Step Goal**: staging이 dev와 분리된 네임스페이스/리소스로 동작하고, dev의 머지된 변경이 staging으로 승격된다.
- **Done When**:
  - [x] `apps/{app}/overlays/staging/kustomization.yaml` 5개 작성 (PR #34)
  - [x] 리소스 한도 dev > staging 분리 (dev: replicas=1/DEBUG, staging: replicas=2/INFO)
  - [x] staging ApplicationSet 추가 — manual sync (PR #34, `argocd/applicationset-staging.yaml`)
  - [x] ArgoCD에서 staging 5개 앱 OutOfSync 확인 (manual sync 대기 정상)
  - [x] staging 공유 Ingress + TLS 매니페스트 작성 (PR #47, `infra/ingress/staging-ingress.yaml` — 적용은 ACM/도메인 확보 후, 검증은 port-forward로 대체)
  - [x] dev → staging 승격 절차 문서화 (PR #47, `docs/runbooks/dev-to-staging-promotion.md`)
  - [x] ApplicationSet **manual → auto sync 전환** (PR #47, FR-GO-301)
  - [x] staging sync → A2 실 EKS에서 **4/5 Healthy** 검증 (platform-svc Degraded = app 레포 staging 프로필, cross-repo 조건부)
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (auto-sync·승격문서·Ingress매니페스트 완료(PR #47), A2 라이브 4/5 검증. platform-svc 5/5만 app 레포 조건부)

---

### Step 8: Observability 스택 (Prometheus + Grafana + Loki)

- **Step Goal**: 모든 환경의 메트릭/로그가 한 곳에서 보이고 기본 알람이 동작한다.
- **Done When**:
  - [x] kube-prometheus-stack 설치 — 실 EKS Running 검증 (Prometheus/Grafana/Alertmanager, PR #47)
  - [x] Loki + Promtail 설치 — 실 EKS Running (schemaConfig/SingleBinary 버그 수정, PR #47)
  - [x] 5개 앱 ServiceMonitor 정의 — applied (메트릭 실수집은 앱 배포 후)
  - [x] 기본 알람 3개 이상 — PrometheusRule 로드 + Watchdog 파이프라인 firing (실 Slack 도달은 real webhook 필요)
  - [x] Grafana 대시보드 1개 이상 — Synapse 개요 ConfigMap 적재
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (A2 실 EKS 1사이클로 스택 전체 검증 — 메트릭 타깃 UP, Alertmanager→Slack 라우팅(실 webhook), prometheus/grafana/alertmanager/loki Healthy. bring-up 자동화 PR #50/#52)

---

## W4 (2026-06-01 ~ 2026-06-05, 4 영업일 — 6/3 지방선거 제외) — prod + 롤백

### Step 9: prod 환경 + 승인 게이트

- **Step Goal**: prod는 자동 sync가 아닌 수동 승인 후 sync되며, 권한이 분리된다.
- **Done When**:
  - [ ] `apps/{app}/overlays/prod/kustomization.yaml` 5개 작성
  - [ ] ArgoCD AppProject `prod`에 Manual Sync 정책
  - [ ] prod sync 권한이 별도 그룹/사용자에게만 부여
  - [ ] PR-merge → staging 자동 sync → prod 수동 승인 흐름 검증
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [ ] Done

---

### Step 10: 롤백 / 백업 전략

- **Step Goal**: 롤백 절차가 문서화되고 staging에서 1회 이상 실제 검증된다.
- **Done When**:
  - [ ] ArgoCD History rollback 절차 문서화 + 검증
  - [ ] Helm/Kustomize 매니페스트 git revert 절차 검증
  - [ ] Velero 또는 etcd snapshot 백업 스케줄 설정
  - [ ] 백업에서 복구 1회 시뮬레이션 통과
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [ ] Done

---

## W5 (2026-06-08 ~ 2026-06-12, 5 영업일) — 안정화 + Runbook

### Step 11: Runbook + 장애 시나리오

- **Step Goal**: 운영자가 첫 1주차 장애를 Runbook만 보고 처리할 수 있다.
- **Done When**:
  - [ ] 장애 시나리오 5개 이상 Runbook 작성 (Pod CrashLoop, OOM, sync 실패, 인증서 만료, DB 연결 실패)
  - [ ] 각 시나리오에 단계별 진단/조치/에스컬레이션 기준
  - [ ] team-lead가 Runbook 따라하기 1회 검증
  - [ ] On-call 연락처/Slack 채널 정리
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [ ] Done

---

### Step 12: Cost 최적화 + 안정화

- **Step Goal**: 운영 비용 가시성 확보 + 5주차 P0/P1 이슈 0건.
- **Done When**:
  - [ ] AWS Cost Explorer 태그 기반 비용 가시성 확보
  - [ ] Resource request/limit 적정성 1회 리뷰
  - [ ] HPA 동작 검증 (5개 앱 중 트래픽 변동 큰 2개)
  - [ ] P0/P1 이슈 목록 0건 (또는 fix 완료)
  - [ ] 핸드오프 문서 마지막 검토
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [ ] Done
