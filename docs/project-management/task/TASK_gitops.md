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
  <!-- 2026-05-28 D-041로 W4 Step 9 (prod 도메인 흐름)로 이월: webhook endpoint 외부 도달 확인 + ACM/DNS/외부 TLS (4항목) -->
- **Scope**:
  - In Scope: ArgoCD 설치, HA 구성, 외부 노출, 인증
  - Out of Scope: 실제 앱 sync, ApplicationSet 구성
- **Input**: EKS 클러스터, ACM 인증서, DNS 도메인
- **Duration**: 1.5일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (옵션2 적용 + kind B-2 실증. FR-GO-102 4항목[ACM/DNS/외부TLS/webhook] W4 Step 9로 이월 — D-041)

---

### Step 2: app-of-apps / ApplicationSet 골격

- **Step Goal**: 5개 앱이 ApplicationSet 한 번의 정의로 dev 환경에 sync된다(빈 manifest라도 OK).
- **Done When**:
  <!-- 2026-05-28 D-002로 ApplicationSet 단독 채택 — `argocd/apps/root.yaml` (app-of-apps) 항목 제거. PRD FR-GO-103 충족 방식 결정됨. -->
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

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (root.yaml은 D-002로 채택 안 함, 선택 항목 정리 — D-041)

---

### Step 3: validate-manifests CI 강화

- **Step Goal**: PR이 들어오면 kustomize/스키마/모범사례 검증이 모두 자동 실행된다.
- **Done When**:
  - [x] kubeconform 추가 (Kubernetes 스키마 + CRD 카탈로그 검증)
  - [x] yamllint 룰 보강 (`.yamllint`: line-length 160, indentation 2)
  <!-- 2026-05-28 D-041로 W5 Step 11/12로 이월: PR 코멘트로 diff 요약 (선택) — W3 이월 표시 후 미진행. -->
  <!-- 2026-06-08: PR diff 요약은 기구현 확인 — validate-manifests.yml diff-comment job(47a7c67, PR #129 동작). Step 11에서 완료 처리. -->
  - [x] CI 실패 시 머지 차단 (scripts/setup-branch-protection.sh, Task 13)
- **Scope**:
  - In Scope: GitHub Actions 워크플로우 보강
  - Out of Scope: 보안 스캔(SBOM, image scan) — 별도 트랙
- **Input**: 기존 `validate-manifests.yml`
- **Duration**: 1일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (PR diff 코멘트·kustomize 캐싱 3항목 W5 Step 11/12로 이월 — D-041)

---

## W2 (2026-05-19 ~ 2026-05-23, 5 영업일) — dev 환경 자동 배포 + Secret

### Step 4: dev overlay 5개 앱 완성

- **Step Goal**: 5개 앱이 dev 환경에 실제 워크로드로 sync되어 동작한다.
- **Done When**:
  - [x] `apps/{app}/overlays/dev/kustomization.yaml` 5개 작성
  - [x] Deployment / Service / ConfigMap 매니페스트 base 완성
  - [x] ArgoCD UI에서 5개 모두 Synced + Healthy (kind 검증)
  - [x] EKS 배포: 3/5 Healthy (engagement-svc, knowledge-svc, learning-card)
  - [x] EKS 배포: platform-svc Healthy (9차 세션: ExternalSecret 11개 + ConfigMap 3개 + Flyway V28 + AES Base64 32B — PR #40)
  - [x] EKS 배포: learning-ai Healthy (9차 세션: 포트 8000→8090 통일 — PR #38)
  - [x] Pod에 트래픽 도달 확인 (S4: knowledge-svc `/actuator/health` → HTTP 200/UP, port-forward, 2026-05-26)
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (EKS 5/5 Healthy — PR #38 + PR #40. dev 도메인 패턴/Ingress/도메인 도달 3항목 W4 Step 9로 이월 — D-041)

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

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (EKS 실배포 완료: ESO Helm + IRSA + ClusterSecretStore Valid + 5개 SecretSynced. ESO sync 실패 알람 1항목 W3 Step 8로 이월 — D-041)

---

### Step 6: 이미지 태그 자동 sync

- **Step Goal**: svc 레포에서 새 이미지가 빌드되면 dev 환경이 자동으로 업데이트된다.
- **Done When**:
  - [x] ArgoCD Image Updater 설치 + 5개 앱 annotation (kind 검증 완료)
  - [x] ImageUpdater CR 작성 (`argocd/image-updater.yaml`)
  - [x] ECR 이미지 경로로 교체 완료 (ApplicationSet + dev overlay)
  - [x] write-back-method: git + write-back-target: kustomization 설정
  - [~] 새 이미지 푸시 → dev 반영(S6 EKS): image-updater 설치(v0.15.2)+ECR IRSA+pullsecret 인증+git repo-cred **검증 완료**, ECR 태그 리스팅 성공. write-back E2E는 **2중 블록** — ① dev overlay가 `dev-latest`(semver 전략 불일치) ② **main 보호 ruleset이 직접 push 거부**(PR 필수, bypass 없음). **결정: dev/staging=A(전용 봇 bypass), prod(W4+)=B(PR write-back)** — 실행 절차·A/B: `docs/runbooks/image-updater-ecr-setup.md`. 라이브 완주는 차기 세션(과금).
  - [x] 태그 변경 이력이 git log에 남음 (git write-back 설정)
- **Duration**: 1.5일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (매니페스트 + ECR 교체 + 자동 sync 비활성화·svc팀 공유 문서화 완료. 이미지 E2E 3항목 W4 Step 10으로 이월 — D-041)
<!-- 2026-06-05: W4→W5 클리어 윈도우에서 IU ECR 자격 미설정(no basic auth) 규명+수정(PR #124). 라이브 write-back E2E는 차기 윈도우. ↓ W4→W5 진입 차단 클리어 §, gitops#122 -->

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

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (auto-sync·승격문서·Ingress매니페스트 완료(PR #47), A2 라이브 4/5 검증. **staging 5/5 06-08 라이브 달성** — platform-svc CrashLoop #92 해소(근본원인=공유 DB flyway 충돌, PR #136), `verify-argocd-deploy.sh staging 20/0/0 ALL PASSED`(shared HANDOFF_HUB). #92 close)

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

### W3 정리·마감 (2026-05-27, Day2~3) — 비용 0 트랙

> Step 7/8은 Day1 완료. 남은 3일을 정리·마감으로 운영(설계/플랜: `docs/superpowers/{specs,plans}/2026-05-27-w3-consolidation*`, 상세 결과: HANDOFF_W3 §1).

- **잔여·이월(코드 완료, 라이브 조건부/W4)**: A1 cross-repo work order(PR #60·`synapse-platform-svc#37`) · A2 ESO IRSA terraform(PR #61) · A3 노드 3→4(PR #62) · A4 staging ACM/TLS terraform(PR #63) · A5 image-updater A안 준비(PR #64)
- **문서·포털·로컬·위생**: C1 아티팩트 정리+가이드 안착 확인(PR #65) · C2 local-k8s README 정합(PR #66) · C3 브랜치 프루닝 · B1 docs-portal 콘텐츠 이미 안착 · C4 PM 정합
- **W4 이월**: Step 9 prod+승인게이트 · Step 10 롤백/백업 · B2 포털 핸드오프 허브 뷰(파이프라인 확장 필요) · (조건부 미실행 시) A3/A4/A5 라이브 검증
- **W2 S4 보강**: engagement-svc Pending → 노드 capacity terraform화(A3)로 해소 경로 확보, 라이브 5/5는 조건부 사이클

---

## W4 (2026-06-01 ~ 2026-06-05, 4 영업일 — 6/3 지방선거 제외) — prod + 롤백

### Step 9: prod 환경 + 승인 게이트

- **Step Goal**: prod는 자동 sync가 아닌 수동 승인 후 sync되며, 권한이 분리된다.
- **Done When**:
  - [x] `apps/{app}/overlays/prod/kustomization.yaml` 5개 작성 (PR #74, 렌더 5/5 OK, 이미지 ECR 통일 PR #77)
  - [x] ArgoCD AppProject `prod`에 Manual Sync 정책 (`synapse-prod` AppProject + `applicationset-prod.yaml` automated 없음, FR-402)
  - [x] prod sync 권한이 별도 그룹/사용자에게만 부여 (`role:prod-deployer`/`gitops-admin`, 라이브 rbac can 평가, FR-403)
  - [x] PR-merge → staging 자동 sync → prod 수동 승인 흐름 검증 (라이브 OutOfSync → gitops-admin 수동 sync, FR-404)
  - [x] **첫 prod 배포 5/5 Healthy** — 2026-06-01 라이브 재현: synapse-prod 15/15 파드, 5개 앱 Synced/Healthy (FR-404). 도메인 200은 readiness probe Healthy(=/actuator/health 200)로 대체(실 도메인 미적용)
  <!-- 2026-06-01 라이브 재현(D-043): 인프라 증설(노드 t3.large×4 / RDS db.t3.small)로 FR-404 달성. 단 2건 워크어라운드 — ① platform-svc는 prod 프로파일이 Hibernate validate라 빈 synapse_prod에 스키마 시드 필요 ② db.t3.small이 dev+staging+prod 동시 연결 부족 → 데모 위해 dev/staging 축소. 상세: docs/runbooks/w4-prod-live-reproduction-runbook.md -->
  - [ ] ACM 인증서 ARN 매핑 + DNS 레코드 (argocd + 5앱 prod 도메인) — W1 이월 (D-041). 실 도메인 부재 — port-forward/probe로 대체 검증
  - [ ] 외부 도메인으로 ArgoCD UI HTTPS 접속 + TLS valid — W1 이월 (D-041). 실 도메인 부재
  - [ ] webhook endpoint 외부 도달 확인 — W1 이월 (D-041). 실 도메인 부재
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (FR-401~404 전부 라이브 증명 — 2026-06-01 prod 5/5 Healthy. 실 도메인 3항목만 W1 이월 잔존(port-forward 대체). team-lead 합의 대기 — D-043)
<!-- 2026-06-05: 실 도메인 3항목(#121)은 nip.io 임시 도메인으로 진행 — nip.io ingress+self-signed(PR #123) + ALB 컨트롤러 부트스트랩(PR #124). 라이브 외부도달·webhook은 차기 윈도우. ↓ W4→W5 진입 차단 클리어 §, gitops#121 -->

---

### Step 10: 롤백 / 백업 전략

- **Step Goal**: 롤백 절차가 문서화되고 staging에서 1회 이상 실제 검증된다.
- **Done When**:
  - [x] ArgoCD History rollback 절차 문서화 + 검증 — 2026-06-01 라이브: prod engagement-svc `argocd app rollback` 1-step → Synced/Healthy (FR-405)
  - [x] Helm/Kustomize 매니페스트 git revert 절차 검증 — 2026-06-01 라이브: PR #80(LOG_LEVEL DEBUG)→sync→PR #81(git revert)→sync→INFO 복원 (FR-406)
  - [x] Velero 또는 etcd snapshot 백업 스케줄 설정 — Velero S3+IRSA(terraform)+일일 Schedule, 라이브 백업 Completed+S3 (PR #75, FR-407)
  - [x] 백업에서 복구 1회 시뮬레이션 통과 — 격리 ns 삭제 → velero restore 복구 확인 (FR-408)
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [x] Done (롤백 405/406 라이브 검증(2026-06-01) + 백업/복구 407/408 + 매니페스트/런북/알람 Done. team-lead 사인오프 대기 — D-043)

---

### W4→W5 진입 차단 클리어 윈도우 (2026-06-05, on-demand EKS+MSK)

> W4→W5 이월 차단 5건(gitops #91/#92/#120/#121/#122)을 1회 on-demand 라이브 윈도우로 처리.
> 설계/플랜: `docs/superpowers/{specs,plans}/2026-06-05-w5-진입차단-클리어*` · 런북: `docs/runbooks/W5_CLEARANCE_WINDOW.md` · 통보 허브: synapse-shared#20.

- [x] **#120 MSK 토픽/TLS/produce-consume/SG 접근제한** — bastion terraform(Mongey/kafka, TLS 9094): 토픽 9개·TLS 체인(Amazon RSA 2048 M04)·console produce/consume 라운드트립·SG 네트워크 접근제한(무인증 TLS-only라 ACL 아닌 SG가 메커니즘) 검증 → **close**.
- [x] **gitops 부트스트랩 + dev 5/6 Healthy** — ArgoCD HA(`--insecure`)/ESO/ApplicationSet/kafka-brokers/metrics-server/image-updater 기동. (`verify-argocd-deploy.sh`는 shared·team-lead 실행)
- [~] **#121 외부 노출 (ACM/DNS/Ingress/webhook, W1·Step 9 이월)** — 코드 완료·main 머지: nip.io ingress + self-signed 인증서 스크립트(PR #123) + **aws-load-balancer-controller 부트스트랩 IRSA+helm(PR #124)**. 라이브 검증은 차기 윈도우 — 실제 차단은 *ALB 컨트롤러 미부트스트랩*이었음(gitops#121).
- [~] **#122 Image Updater write-back E2E (W4 Step 6/10 이월)** — ECR 자격 미설정(`no basic auth credentials`) 규명 + 수정: `registries.conf` ext 스크립트 + `ecr-login.sh`(PR #124). 라이브 E2E는 차기 윈도우(gitops#122).
- [x] **#91 dev/staging 5/5 — 06-08 라이브 달성·close** — EKS 재apply → `verify-argocd-deploy.sh` **dev 16/0/0 · staging 20/0/0 ALL PASSED** + 롤백 124s(06-02, <3분). 이전 차단 gateway-dev(JWT 매핑, PR #136)·platform-svc-staging(#92) 모두 Healthy(shared HANDOFF_HUB §1).
- [x] **#92 platform-svc-staging — 06-08 라이브 해소·close** — ① datasource(`application-staging.yml` main `${DB_URL}`) + ② flyway 충돌(공유 DB) 모두 PR #136으로 해소. 06-08 EKS 재apply `verify-argocd-deploy.sh staging 20/0/0 ALL PASSED`, platform-svc staging Healthy(shared HANDOFF_HUB §1). 잔존 관찰=staging가 dev RDS·DB 공유(§4 감사, 환경격리는 별도).
- 검증 후 `terraform destroy`로 과금 차단.

**Status**: 진행 중 — #120 **Done·close**. **#91·#92 06-08 라이브 달성·close**(EKS 재apply → dev 16/0/0·staging 20/0/0 ALL PASSED, gateway JWT·platform DB 분리 PR #136, shared HANDOFF_HUB §1). #121/#122 gitops 코드 main 머지(PR #123/#124), 라이브 검증만 차기 on-demand 윈도우(`W5_WINDOW_2.md`).

---

## W5 (2026-06-08 ~ 2026-06-12, 5 영업일) — 안정화 + Runbook

### Step 11: Runbook + 장애 시나리오

- **Step Goal**: 운영자가 첫 1주차 장애를 Runbook만 보고 처리할 수 있다.
- **Done When**:
  - [x] 장애 시나리오 5개 이상 Runbook 작성 (Pod CrashLoop, OOM, sync 실패, 인증서 만료, DB 연결 실패) — `docs/runbooks/incidents/` 5종
  - [x] 각 시나리오에 단계별 진단/조치/에스컬레이션 기준 — 6섹션 골격(증상/진단/조치/에스컬레이션/회피/사후)
  - [ ] team-lead가 Runbook 따라하기 1회 검증 — 윈도우 2 Phase 5 (`docs/runbooks/W5_WINDOW_2.md`)
  - [x] On-call 연락처/Slack 채널 정리 — `docs/runbooks/on-call.md` (2레벨 간소화, 알람 경로 테스트만 윈도우 항목)
  - [x] PR 코멘트로 diff 요약 GitHub Action 도입 (선택) — W1 이월 (D-041) — 기구현 확인: `validate-manifests.yml` diff-comment job (커밋 47a7c67), PR #129 동작 확인
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [x] In Progress / [ ] Done (문서 산출물 완료. 시뮬레이션·team-lead 검증·알람 테스트는 윈도우 2 Phase 5 — 2026-06-08 스펙)
<!-- 2026-06-08: 장애 런북 5종(incidents/)·on-call·윈도우 2 런북(W5_WINDOW_2.md) 머지. 라이브 3항목(시뮬레이션·따라하기·알람)은 차기 on-demand 윈도우. 설계: docs/superpowers/specs/2026-06-08-w5-step11-runbook-window2-design.md -->

---

### Step 12: Cost 최적화 + 안정화

- **Step Goal**: 운영 비용 가시성 확보 + 5주차 P0/P1 이슈 0건.
- **Done When**:
  - [ ] AWS Cost Explorer 태그 기반 비용 가시성 확보
  - [x] Resource request/limit 적정성 1회 리뷰 — 2026-06-08 정적 리뷰 완료(`docs/runbooks/resource-sizing-review-w5.md`): Java 5종 limit 512Mi 균일·tight(OOM 리스크)·서비스/환경 미차등 발견. P95 기반 튜닝은 윈도우2(메트릭) 위임
  - [ ] HPA 동작 검증 (5개 앱 중 트래픽 변동 큰 2개)
  - [x] P0/P1 이슈 목록 0건 (또는 fix 완료) — 2026-06-08 확인: 열린 P0/P1 0건(#91 P0·#92 P1 close). 잔존 OPEN 3건(#121/#122 윈도우2·#126 ops)은 P0/P1 아님
  - [ ] 핸드오프 문서 마지막 검토
  - [x] kustomize build 결과 캐싱 (CI 속도 개선, 선택) — W1 이월 (D-041). 2026-06-08: build는 sub-second라 이득 미미 → 실제 비용인 kubeconform 바이너리 + pip(yamllint) 캐싱으로 대체 적용(`validate-manifests.yml`)
- **Duration**: 2일
- **Assignee**: @VelkaressiaBlutkrone
- **Reviewer**: @team-lead

**Status**: [ ] Not Started / [ ] In Progress / [ ] Done
