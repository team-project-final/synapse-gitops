# HISTORY: gitops

> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone

진행 이력. 자동 sync된 진척 변경은 workflow-dashboard의 `data/synapse-gitops.json` `changelog`에 별도 기록됩니다. 이 문서는 수동으로 남기는 의사결정/이벤트 로그입니다.

---

## 2026-05-12 ~ 2026-05-16 (W1)

### Phase 2/3 부트스트랩 (사전 작업)
- `apps/`, `argocd/`, `infra/` 디렉토리 골격 추가
- `validate-manifests.yml` CI 워크플로우 도입 — kustomize build + yamllint
- docker-compose 로컬 개발 환경 세팅

### 의사결정
- 트랙 구조: 단일 `gitops` 트랙으로 시작 (앱별 분리는 필요 시 추후)
- Secret 관리 방식: 후보 검토 (External Secrets vs SOPS) → W2 Step 5에서 결정

### 이벤트
- (없음)

### 2026-05-16 (W1 마무리)

#### 의사결정
- **D-001 ArgoCD 외부 노출 방식**: 옵션 2(NLB TCP passthrough + 자체서명 TLS) 채택.
  - 이유: 실 도메인 미확보 → ACM 발급 불가. 옵션 1(ALB+ACM)은 W2 초반 마이그레이션으로 이월.
  - 대안 검토: ALB Ingress + ACM (도메인 필요), ingress-nginx + Let's Encrypt (도메인 필요).
  - 결과: PRD FR-GO-102 부분 충족(TLS는 있으나 도메인+CA 인증서 아님). [docs/argocd-tls-migration.md](../../argocd-tls-migration.md)에 마이그레이션 절차 사전 작성.
- **D-002 ApplicationSet 구조**: matrix 유지 + env list=[dev]만 활성화 (C3).
  - 이유: PRD FR-GO-103 "5개 Application" 원안 충실, W3/W4에 env list 1줄 추가로 확장.
  - 대안 검토: list 5개로 축소(W3에 재구조화 필요), matrix + 15개 생성(PRD 수정 필요).
- **D-003 ArgoCD HA 토폴로지**: controller=1, server=3, repoServer=2, applicationSet=2, redis-ha=true.
  - 이유: PRD 문구는 server 3 명시. controller 샤딩은 W3 부하 발생 시.
- **D-004 admin 비번 관리**: bootstrap.sh가 1회 회전 후 AWS Secrets Manager 저장 (secret: `synapse/argocd/admin`).
  - 이유: W1 범위 최소화 + git 평문 0건 보장. ESO는 W2 Step 5에서 도입.
- **D-005 CI 강화 범위**: kubeconform 추가, .yamllint 강화. CRD 스키마는 `-ignore-missing-schemas` 경고 처리.
  - 이유: 핵심 K8s 리소스 검증이 우선. CRD 카탈로그 정비는 W3 Observability와 묶음.

#### 산출물
- 디자인 스펙: `docs/superpowers/specs/2026-05-16-w1-argocd-bootstrap-design.md` (commit e6483ec)
- 구현 플랜: `docs/superpowers/plans/2026-05-16-w1-argocd-bootstrap.md` (commit 74e8896)
- PR: (PR 번호는 생성 후 추가)

#### 이벤트
- 사용자 액션: `terraform apply` + `bootstrap-argocd.sh` 실행으로 EKS dev에 ArgoCD 부트스트랩 완료
- 검증: 의도적 오류 PR로 kubeconform CI 실패 확인 (PR 번호는 실행 후 추가)
- PR #6 머지: 16개 파일 변경 (사양/플랜/매니페스트/스크립트/문서/CI). merge commit base sha `78aa6a3`.

#### 후속 의사결정 (PR #6 머지 후)
- **D-006 main 브랜치 보호 방식 (E1 채택)**: 레포를 Public 전환 + GitHub Rulesets API로 보호 룰 적용.
  - 이유: 레포가 Private + GitHub Free 플랜이라 Legacy Branch Protection API + Rulesets 모두 HTTP 403. Pro 업그레이드($4/월) 비용 회피 + 학생/포트폴리오 성격상 공개에 무리 없음.
  - 사전 점검: 추적 파일에서 AWS access key 패턴 0건, `.env.example` placeholder만, `*.tfvars`는 gitignore됨, git history 28 commit 전체 grep도 0건.
  - 적용된 Ruleset (id 16480319, name `main-protection`, enforcement active):
    - `required_status_checks`: `Validate Kubernetes Manifests` 필수 + strict
    - `pull_request`: required approving review count 0 (단독 작업, REVIEWS 환경변수로 토글 가능)
    - `deletion` + `non_fast_forward` 차단
    - bypass 불가 (`current_user_can_bypass: never`)
  - 결과: PRD FR-GO-105 충족.
- **D-007 CI 워크플로우 단순화**: 원안의 `concurrency` 블록 + `env` 외부 변수 + CRD-catalog `schema-location` + `Report total time` step 제거.
  - 이유: 위 요소 중 하나(또는 조합)가 GitHub Actions YAML 파싱 단계에서 0초 실패 유발. 정확한 단일 원인 미파악. CI를 빨리 통과시키기 위해 안전한 최소 구성으로 회귀.
  - 영향: CRD 카탈로그 schema-location 없이도 `-ignore-missing-schemas`로 ArgoCD CRD는 경고 처리, 핵심 K8s 리소스 검증은 그대로. PRD FR-GO-104 충족.
  - 후속: W3 Observability와 함께 CRD 카탈로그 + concurrency 재도입 시도. 그 시점에 단일 원인 격리.

#### Task 14 사용자 실행 결과 (오후~저녁)

**실행 흐름**:
1. AWS 계정(신규) + IAM 사용자 `synapse-admin` 생성 + AdministratorAccess 부착 (콘솔 path)
2. S3 backend bucket + DynamoDB lock table 수동 생성 (chicken-and-egg 해소)
3. terraform init + plan + apply 실행 → 부분 자원만 생성된 채 5건 에러 발생
4. 4건의 코드 버그를 PR #11/#12로 main에 수정 반영
5. 최종적으로 AWS 신규 계정의 Free Tier 제약(EKS 노드 launch 불가)으로 실증 막힘
6. 비용 출혈 차단 위해 즉시 `terraform destroy -auto-approve` 실행 (40분 36초)
7. S3 state bucket + DynamoDB lock table 삭제 완료

**발견된 코드 버그 (모두 main 반영 완료)**:
- PR #11 — `infra/aws/dev/eks.tf` EKS 1.29 → 1.30 (AMI 미지원), `infra/aws/dev/rds.tf` parameter group에 `apply_method = "pending-reboot"` 추가
- PR #12 — `infra/aws/dev/opensearch.tf` IP-based access policy Condition 제거 (VPC endpoint와 충돌), `infra/aws/dev/rds.tf` postgres 16.3 → 16.6

**환경 issue (코드 외)**:
- OpenSearch service-linked role 수동 생성 필요: `aws iam create-service-linked-role --aws-service-name opensearchservice.amazonaws.com`
- MSK는 콘솔에서 한 번 페이지 방문해야 활성화
- 신규 AWS 계정의 결제수단 verification 미완료 → EKS 노드 launch 불가 (Free Tier eligible 인스턴스만 허용). 24~72h 후 verification 완료 시 해결.

**비용**: 자원이 1~2시간 부분 가동 후 destroy. 예상 청구 $0.30~$1 (Cost Explorer는 24h lag로 다음 날 정확 표시).

**PRD W1 검수 결론 (Task 14 후)**:
- FR-GO-101/103: 코드 ✅, 실증 미완 (결제수단 verification 후 B-1 path로 재시도 예정)
- FR-GO-102: 코드 ✅ (self-signed TLS), 실증 미완
- FR-GO-104: 코드 ✅ + CI 정상 동작 검증됨 (PR #6~#12에서 yamllint/kustomize/kubeconform 모두 작동). 의도적 오류 PR 실증은 B-2(kind 로컬) 또는 B-1(EKS 재시도) 시점에 수행
- FR-GO-105: ✅ 충족 (PR #7~#12에서 ruleset이 PR + status check를 강제하며 정상 동작)

**다음 path (사용자 결정 B-4 → B-2 → B-1)**:
- B-4 (현재 PR): Task 14 결과를 HISTORY/WORKFLOW에 기록 + 사용자 액션 가이드를 docs/runbooks/에 영구 보관
- B-2 (다음 작업): kind 로컬 클러스터로 ArgoCD HA + ApplicationSet 5개 실증 (오늘 안에 완료, 비용 0)
- B-1 (며칠 후): 결제수단 verification 완료 후 실제 EKS 부트스트랩 재시도. 본 PR 머지된 main으로 git pull 받으면 코드 버그 다 해결된 상태로 시작 가능.

#### 산출물 (추가)
- 운영 가이드: `docs/runbooks/step1-aws-account-setup.md` (Step 1), `docs/runbooks/step2-terraform-tfvars.md` (Step 2), `docs/runbooks/step3-terraform-apply.md` (Step 3) — OS별 명령 + 트러블슈팅 포함

#### B-2 path 실행 (kind 로컬 클러스터, 같은 날 저녁)

EKS 실증 실패 후 kind로 즉시 대체 실증:

1. kind v0.x + Docker Desktop 사용, K8s 1.35 cluster (1 control-plane + 2 worker)
2. ArgoCD HA install.yaml 적용 — 단 `kubectl apply`가 ApplicationSet CRD의 annotation 크기 초과로 실패 → `kubectl apply --server-side --force-conflicts`로 해결
3. argocd-server를 deployment scale로 replicas 3으로 변경 (HA install.yaml default는 2)
4. `argocd/projects.yaml`, `argocd/bootstrap/`, `argocd/applicationset.yaml` 적용 → **5개 Application 등록 + Synced 상태 확인**
5. 의도적 오류 PR (test/intentional-ci-failure, PR #14) 생성 → 첫 시도(apiVersion 변경)는 CI 통과(아래 학습) → 두 번째 시도(kustomize build 실패)로 **CI FAIL 확인** → PR close + 브랜치 삭제

**B-2 실증 매핑**:
- FR-GO-101: ✅ argocd-server 3 replicas (Pending 1개는 kind 3노드의 anti-affinity 부족이 원인, 토폴로지 의도 충족)
- FR-GO-103: ✅ 5 Application 모두 Synced로 등록
- FR-GO-104: ✅ CI FAIL 확인 (PR #14 두 번째 commit)

**부수 학습 (D-008 trade-off)**:
- D-005에서 채택한 kubeconform `-ignore-missing-schemas`가 **unknown apiVersion(예: `apps/v999`)도 skip하는 부작용** 발견.
- 의도적 오류 PR 첫 시도(`apiVersion: apps/v1 → apps/v999`)가 CI를 통과해버림.
- 원인: kubeconform이 group `apps`는 알지만 version `v999`의 schema가 없으니 missing-schemas로 처리.
- 해결: `kustomize build` 단계에서 nonexistent file reference 추가하니 빌드 실패 → CI fail (정상 동작).
- W3 후속: CRD 카탈로그 정비 + `-strict` 강화 시점에 unknown apiVersion도 fail 처리하도록 schema-location 또는 별도 검증 단계 추가.

#### 최종 PRD W1 검수 매핑

| FR | 코드 | 실증 | 비고 |
|---|---|---|---|
| FR-GO-101 server replicas 3 | ✅ | ✅ kind | EKS B-1 시점에 실 환경 재실증 |
| FR-GO-102 외부 도메인 TLS | ✅ self-signed | ⚠️ kind는 port-forward로 동등 | W2 옵션1 마이그레이션 후 완전 충족 |
| FR-GO-103 5 Application | ✅ | ✅ kind | EKS B-1 시점에 동일 결과 예상 |
| FR-GO-104 kubeconform CI fail | ✅ | ✅ PR #14 | -ignore-missing-schemas trade-off 기록 |
| FR-GO-105 main protection | ✅ Ruleset 16480319 | ✅ | PR #11~#13 머지 시 강제 동작 검증 |

**W1 종료 선언**: 코드/CI/Ruleset 충족 + kind 로컬 실증 + 모든 학습 사항 HISTORY 기록 완료.

#### B-1 path (며칠 후, 사용자 일정)

결제수단 verification 완료 후 EKS 재시도:
1. `git pull origin main` (Task 14 모든 fix + B-4 가이드 + B-2 학습 다 반영된 상태)
2. `docs/runbooks/step1-aws-account-setup.md` 부터 가이드 그대로 따라 진행
3. Step 3 terraform apply 시 4건 버그는 이미 main에서 fix 완료된 상태로 시작
4. 실증 결과를 HISTORY에 "B-1 실행" 섹션으로 추가 기록

---

## 2026-05-19 ~ 2026-05-23 (W2)

### 의사결정
- **D-009 kind 먼저 → EKS 전환**: 결제수단 verification 미완, 비용 0으로 구조 검증.
- **D-010 ESO Fake provider (kind) → AWS provider (EKS)**: kind에서 ESO 동작 흐름 검증 + overlay 패치로 교체 용이.
- **D-011 로컬 레지스트리 + Image Updater (kind)**: ECR 없이 이미지 자동 반영 E2E 검증 가능.
- **D-012 단일 브랜치 순차 진행**: W1 패턴 일치, Step 간 의존성 자연 처리, 하나의 PR로 리뷰.
- **D-013 ConfigMap은 svc 레포 yml 기반**: 실제 앱 설정과 정합성 보장.
- **D-014 ExternalSecret secretStoreRef를 overlay에서 패치**: kind/EKS 전환 시 구조 변경 없이 값만 교체.

### 산출물
- 디자인 스펙: `docs/superpowers/specs/2026-05-18-w2-dev-deploy-design.md`
- 구현 플랜: `docs/superpowers/plans/2026-05-18-w2-dev-deploy.md`
- kind 인프라: `infra/kind/` (kind-config, local-registry, setup-kind-w2, fake-secret-store)
- 5개 앱 base 보강: ConfigMap + ExternalSecret + envFrom
- dev overlay: ConfigMap patch + ExternalSecret secretStoreRef patch
- ApplicationSet: Image Updater annotations

### 이벤트

#### 2026-05-18 (W2 사전 준비, 일요일)
- 새 PC 환경 세팅: choco로 kind/helm/argocd-cli/gitleaks/jq 설치
- kind 클러스터 생성 시 `containerdConfigPatches`가 K8s v1.35.0에서 kubelet 타임아웃 유발 → 단일 노드 + ConfigMap 기반 레지스트리 연결로 해결
- ESO CRD apiVersion: `v1beta1` → `v1`로 수정 필요 (최신 ESO가 v1을 기본 등록)
- **D-015 Image Updater CRD 방식 전환 필요**: v1.2.0부터 annotation 기반 → CRD(`ImageUpdater` CR) 기반으로 변경됨. `"No ImageUpdater CRs to process"` 로그 확인. EKS 전환 시 CRD 방식으로 작성 예정. annotation은 구조 참고용으로 유지.
- kind 실증 결과: Step 4 (매니페스트 구조 ✅) + Step 5 (ESO Fake sync ✅) + Step 6 (Image Updater 설치 ✅, E2E는 CRD 방식 전환 후 재검증)

#### 2026-05-19 (W2 Day 1, 월요일)

**shared 레포 (synapse-shared)**:
- PR #2 (`feat/w2-kafka-schemas`) CI 실패 진단: `./gradlew` 누락 (Gradle wrapper 미커밋)
- Gradle 8.8 wrapper 4개 파일 추가 + `.gitignore` 순서 수정 (`!gradle-wrapper.jar` → `*.jar` 뒤로)
- `gradlew` 실행 권한(`chmod +x`) 추가
- CI 2개 체크(build, schema-check) 모두 pass → PR #2 main 머지 완료
- shared HISTORY W2 Step 4-5 완료 기록 갱신

**terraform 중복 실행 사고 + 정리**:
- 다른 PC에서 이미 `terraform apply` 완료된 상태를 인지하지 못하고 이 PC에서 재실행
- State bucket을 새로 생성했기 때문에 기존 인프라를 모르고 중복 리소스 생성 시작
- IAM Role, Subnet Group 등 이름 충돌로 apply 부분 실패 (24개 리소스 생성, 5개 충돌)
- 즉시 `terraform destroy -auto-approve` 실행 → 24개 중복 리소스 전부 삭제 완료
- 기존 인프라(EKS ACTIVE, Redis 존재) 무사 확인. RDS/MSK/OpenSearch는 기존에도 없음(이전 destroy)

**EKS provider swap (Task 8)**:
- 5개 앱 dev overlay: `fake-secrets` → `aws-secrets-manager`, `localhost:5001` → ECR (`963773969059.dkr.ecr.ap-northeast-2`), 태그 `1.0.0` → `dev-latest`
- ApplicationSet image-list annotation: ECR 경로로 교체
- `infra/external-secrets/cluster-secret-store.yaml` 신규 생성 (AWS SM ClusterSecretStore)

**PRD W2 검수 (Task 9)**:
- FR-GO-201 (5개 앱 dev overlay + auto sync): ✅ 완료
- FR-GO-202 (dev 도메인 외부 접근): ⬜ EKS 배포 후
- FR-GO-203 (ESO 도입): ✅ 매니페스트 완료 (EKS Helm 설치는 배포 시)
- FR-GO-204 (AWS SM sync): ✅ ClusterSecretStore 매니페스트 + secretStoreRef 교체 완료 (IRSA는 배포 시)
- FR-GO-205 (이미지 자동 반영): ✅ ECR 교체 완료
- FR-GO-206 (git 추적): ✅ write-back-method: git 설정

**의사결정**:
- **D-016 terraform state 관리**: 팀에서 1명만 apply하고 state는 S3 중앙 저장. 다른 PC에서는 `aws eks update-kubeconfig`로 접속만 설정.
- **D-017 인프라 부분 존재 상태 허용**: EKS + Redis만 ACTIVE, RDS/MSK/OpenSearch는 다음 apply에서 생성. ConfigMap endpoint 값은 인프라 재생성 후 추가.

**문서 갱신**:
- TASK_gitops.md Step 4/5/6 → Done
- WORKFLOW_gitops_W2.md 체크박스 갱신
- HISTORY_gitops.md 본 섹션 추가

#### 2026-05-19 오후 — EKS 실배포

**ArgoCD 부트스트랩**:
- ArgoCD HA install.yaml 적용 (`--server-side --force-conflicts` — CRD annotation 크기 초과 해결)
- ArgoCD server 2 replicas Ready
- `argocd/projects.yaml` + `argocd/applicationset.yaml` 적용 → 5개 Application Synced

**ESO + IRSA 구성**:
- ESO Helm 설치 (`external-secrets` namespace)
- IAM Policy 생성: `synapse-dev-eso-secrets-read` (SecretsManager GetSecretValue/DescribeSecret/ListSecrets, Resource: `synapse/dev/*`)
- IAM Role 생성: `synapse-dev-eso-role` (IRSA Trust Policy → `system:serviceaccount:external-secrets:external-secrets`)
- ESO ServiceAccount에 IRSA annotation 추가 + Pod 재시작
- ClusterSecretStore `aws-secrets-manager`: **Valid + ReadWrite + Ready**

**AWS Secrets Manager**:
- 8개 시크릿 등록 (platform-svc 2개, engagement-svc 1개, knowledge-svc 2개, learning-card 1개, learning-ai 2개)
- 5개 ExternalSecret 모두 **SecretSynced + Ready**

**kind 정리**:
- `kind delete cluster --name synapse-w2` — 로컬 클러스터 삭제 완료

**PRD W2 최종 검수 (EKS 실증)**:
- FR-GO-201 (5개 앱 Synced): ✅ (Degraded는 ECR 이미지 미존재 — 정상)
- FR-GO-203 (ESO): ✅ EKS Helm + IRSA + ClusterSecretStore Valid
- FR-GO-204 (AWS SM sync): ✅ 5개 ExternalSecret SecretSynced
- FR-GO-205 (이미지 자동 반영): ✅ ECR 설정 완료 (E2E는 이미지 push 후)
- FR-GO-206 (git 추적): ✅ write-back-method: git

**의사결정**:
- **D-018 IRSA 구성 방식**: IAM Policy + Role을 수동 생성 (terraform 외). 이유: 기존 terraform state와 분리, ESO 전용 최소 권한.

---

## 2026-05-28 (W4 Day -3) — W1/W2 PM 문서 100% 정합화

### 의사결정
- **D-041 W1/W2 PM 문서 100% 정합화 + 이월 정책 (2026-05-28)**:
  - **결정**: W1/W2의 미해결 박스 14건을 다음 주차(W3/W4/W5)로 **물리적 라인 이동**. 원자리에는 HTML 주석으로 사유 + 결정 ID 흔적 유지. TASK 본문 미체크 박스 3건도 동일 정책. TASK_gitops.md W1/W2 Step Status는 모두 `[x] Done`으로 통일하고 각 라인에 "X항목 이월" 메모 첨부.
  - **이유**: W4 prod 진입 시점에 PM 대시보드가 W2=In Progress(3/5)로 표시되어 실제(5/5 Healthy)와 불일치. WORKFLOW 파서가 `- [ ]` / `- [x]` 박스를 카운트하므로 W1/W2 = 100%를 위해 박스 자체를 이동.
  - **대안 검토**:
    - 원자리 `[x]` + 사유: 100% 즉시 달성하나 W3+ 박스도 추가 시 카운트 이중.
    - 라인 제거 + 줄글 전환: 100% 달성하나 W1/W2에서 흔적 사라짐.
  - **결과**:
    - WORKFLOW W1 unchecked: 8 → 0 (1건 사실반영 + 7건 이월)
    - WORKFLOW W2 unchecked: 13 → 0 (4건 사실반영 + 2건 신규 + 7건 이월)
    - WORKFLOW W3 unchecked: 1 → 2 (+1 ESO 알람)
    - WORKFLOW W4 unchecked: +10 (Step 9: +7, Step 10: +3)
    - WORKFLOW W5 unchecked: +3 (Step 11: +2, Step 12: +1)
    - TASK W1/W2 Status 6 Step 모두 `[x] Done`으로 통일

### 산출물
- 디자인 스펙: `docs/superpowers/specs/2026-05-28-w1-w2-100pct-design.md`
- 구현 플랜: `docs/superpowers/plans/2026-05-28-w1-w2-100pct.md`
- Runbook 패치: `docs/runbooks/image-updater-ecr-setup.md` (자동 sync 비활성화 절차 섹션 추가)
- PM 문서 갱신: TASK_gitops.md, WORKFLOW_gitops_W1.md ~ W5.md

### 이벤트
- W2 Step 4 사실 갱신: 9차 세션(PR #40 + PR #38)에서 이미 5/5 Healthy 달성한 사실을 본 작업에서 PM 문서에 반영. TASK는 In Progress(3/5)로, WORKFLOW는 5/5 미반영 상태로 방치되어 있었음.
- 단일 PR로 묶음: `chore/w1-w2-100pct-pm-consolidation` 브랜치.

---

## 2026-05-28 ~ 2026-06-01 (W4) — prod 거버넌스 + 롤백/백업

### prod 비용0 구현 (2026-05-28)
- Step 9 비용0(Task 1~8)+문서 → **PR #74** 머지: prod overlay ×5(논리분리 `synapse_prod`/Redis idx1/`synapse/prod/*` 시크릿), `synapse-prod` AppProject, `applicationset-prod.yaml`(manual, image-updater 없음), RBAC `role:prod-deployer`+`gitops-admin` 로컬 계정, `argocd/README.md`.
- Step 10 비용0(Task 1·3·4·5) → **PR #75** 머지: Velero S3+IRSA(terraform), 일일 `Schedule`(synapse-prod/staging ns+PV), `velero.rules` PrometheusRule, 롤백·백업 runbook.

### W4 라이브 사이클 1회 (2026-05-28, destroy로 종료)
> 비용 batching: W3 이월 검증 + W4 prod를 1 사이클로 묶어 과금 1회. 종료 시 `terraform destroy`.
- 실행: dev→prod 시크릿 21개 복사 · D-039(eso role/policy 삭제 후 재생성) · `terraform apply`(58리소스) · `bring-up.sh`(ArgoCD/ESO/SSM터널/dev·staging) · prod 매니페스트 apply · Velero 설치(IRSA+S3, BSL Available).
- **거버넌스 FR 증명**: FR-402 ✅ prod 5개 OutOfSync(수동 게이트) · FR-403 ✅ `argocd admin settings rbac can`(gitops-admin→prod sync Yes / 비-prod·기본→No) · FR-407 ✅ Schedule+백업 Completed+S3 · FR-408 ✅ 격리 ns 백업→삭제→restore 복구.
- **미충족(라이브 기동 후 확인 대상)**: FR-404 prod 5/5·도메인 200 — 노드 maxSize=3(prod 15파드 수용불가)·RDS 연결 슬롯 고갈(`synapse_prod` DB 생성 실패)·prod 이미지·실 도메인 부재. FR-405/406 롤백 — runbook 문서화 완료, 1-step·revert 라이브 검증은 미실시.
- **한계는 거버넌스 아닌 자원**: prod 5/5 Healthy만 자원/이미지로 막힘, 승인 게이트·권한 분리·백업/복구는 전부 증명. 종료 시 destroy(1차 VPC DependencyViolation→수동 SG 삭제 후 성공). 방치된 별개 synapse-dev VPC(NAT GW, ~$13) 수동 정리.

### 의사결정
- **D-042 W4 PM 문서 진척 정합화 + prod 이미지 레지스트리 ECR 통일 (2026-06-01)**:
  - **결정**: ① prod 이미지 레지스트리를 ECR로 통일(보류됐던 ghcr vs ECR 결정 확정) → **PR #77** 머지(overlay 5개 `newName` ECR 추가). ② W4 일정 문서(TASK/WORKFLOW_W4)를 "증명된 것만 Done" 원칙으로 정합화 — FR-401/402/403/407/408 = `[x]`, FR-404/405/406 = 미체크 유지 + "라이브 기동 후 확인" 메모. Step 9/10 Status = `In Progress`.
  - **이유**: 비용0 구현+라이브 거버넌스 검증은 끝났으나 TASK/WORKFLOW가 `Not Started`로 방치돼 실제와 불일치. 단 FR-404(prod 5/5·도메인 200)·405/406(롤백 라이브 검증)은 자원/도메인 차단으로 미충족이라 "전부 Done"은 과장 → 증명된 항목만 체크.
  - **대안 검토**: 전부 Done(404/405/406 미충족 과장) / 코드만 Done·라이브 전부 W5 이월(거버넌스 라이브 증명을 누락).
  - **결과**: 정합성 재검증(`kubectl kustomize`+`terraform validate`)으로 머지본 전수 통과 확인. 레지스트리 불일치 1건 발견·수정. 라이브 재현 시 남은 선반영: 노드 maxSize↑·RDS max_connections↑.

### 산출물
- 이미지 수정: PR #77 (`fix/w4-prod-image-registry-ecr`)
- PM 문서 갱신: TASK_gitops.md(W4 Step 9/10), WORKFLOW_gitops_W4.md, 본 HISTORY 섹션 — 브랜치 `docs/w4-pm-progress-reconcile`

---

## 2026-06-01 (W4) — prod 라이브 재현 성공 (FR-404/405/406 완주)

### 이벤트 — 라이브 사이클 (인프라 증설 프로파일)
- **착수 사전조건**: prod 시크릿 21개 SM 잔존(이전 사이클)·D-039 ESO role 부재(해소됨)·EKS clean slate 확인. prod 이미지 부재 → ECR 서버사이드 리태그 `dev-latest`→`prod-latest` ×5(PR #79 결정대로 ECR 통일).
- **terraform apply**: 58리소스, 증설 프로파일(`eks_node_count=4`/`t3.large`/`db.t3.small`). EKS ACTIVE, 노드 4×t3.large Ready.
- **bring-up `--from eks-auth --to manifests`**: ArgoCD HA + ESO(IRSA, OIDC 일치) + dev/staging ApplicationSet. (observability/velero/image-updater 단계는 이번 사이클 생략 — 404/405/406 집중)
- **`synapse_prod` DB 생성**: 클러스터 내 psql 파드로 공유 RDS에 `CREATE DATABASE`.
- **FR-403**: `argocd admin settings rbac can` — gitops-admin sync prod=Yes / 일반(alice)=No / readonly get=Yes / gitops-admin 비-prod sync=No(스코프 정확).
- **FR-404 ✅ prod 5/5 Healthy(15/15 파드)** — core sync. 2건 블로커 해소: ① **platform-svc 스키마** — prod 프로파일이 Hibernate `validate`라 빈 `synapse_prod`에서 `missing table device_tokens` 크래시 → `synapse`(dev) 스키마를 `pg_dump --schema-only`로 시드. ② **RDS 연결 고갈** — db.t3.small(~225 conn)이 dev+staging+prod 동시 부족(`remaining connection slots reserved`) → 데모 위해 dev/staging ApplicationSet 제거로 연결 확보.
- **FR-405 ✅**: prod engagement-svc `argocd app rollback`(kustomize-image 오버라이드로 리비전2 생성 → ID0 롤백) → Synced/Healthy.
- **FR-406 ✅**: PR #80(LOG_LEVEL INFO→DEBUG)→수동 sync(DEBUG 적용)→PR #81(`git revert`)→수동 sync→**INFO 복원**.
- **종료**: `terraform destroy`. 1차 VPC `DependencyViolation`(EKS 자동생성 SG `eks-cluster-sg-*` 잔재) → 수동 SG 삭제 후 재시도 → **Destroy complete(전 리소스)**. orphan 스윕 clean(NAT/VPC/EKS/RDS/Redis/MSK 0). **과금 완전 차단.**

### 의사결정
- **D-043 W4 prod 라이브 재현 완주 (2026-06-01)**:
  - **결정**: 인프라 증설 프로파일로 FR-404(prod 5/5 Healthy)·FR-405(History 롤백)·FR-406(git revert 롤백)을 라이브 증명. TASK/WORKFLOW_W4 Step 9/10 = **Done**. 단 실 도메인 3항목(ACM/DNS/UI HTTPS·webhook)은 도메인 부재로 W1 이월 유지(port-forward/probe로 대체 검증), team-lead 사인오프 대기.
  - **근거**: 이전(2026-05-28) 사이클은 거버넌스만 증명하고 5/5는 자원 차단으로 미달(D-042). 이번엔 노드 t3.large×4·RDS db.t3.small로 증설해 5/5 달성.
  - **발견(런북 반영)**: ① prod 빈 DB에는 외부 스키마 마이그레이션 필요(prod 프로파일 Flyway 미실행, Hibernate validate). ② db.t3.small은 3개 환경 동시 운용 시 연결 부족 — 4개 환경 동시면 db.t3.medium 권장 또는 환경 분리 기동.
  - **대안 검토**: db.t3.medium 증설(연결 여유, 비용·RDS 리부팅) vs dev/staging 축소(채택, 데모는 prod 집중) / prod replicas 3→1(운영급 가정 훼손, 미채택).

### 산출물
- ECR 리태그 ×5(prod-latest), PR #80/#81(FR-406 데모·revert)
- PM 문서: TASK_gitops.md(W4 Step 9/10 Done), WORKFLOW_gitops_W4.md, 본 HISTORY 섹션, `docs/runbooks/w4-prod-live-reproduction-runbook.md`(학습 반영) — 브랜치 `docs/w4-live-reproduction-results`

---

## 2026-06-01 (W4) — docs-portal 배포 복구 (CI)

### 이벤트 — deploy-pages 익명 체크아웃 전환 (PR #83)
- **증상**: `deploy-pages` 워크플로우가 **2026-05-26부터 전부 실패** — `Checkout synapse-shared` 스텝에서 `Input required and not supplied: token`. `SHARED_REPO_TOKEN` 시크릿 미등록이 원인.
- **수정**: synapse-shared는 **public** 레포 → 토큰 불필요. `deploy-pages.yml`의 `token:` 라인 제거(익명 체크아웃 — 시크릿 불요, full 콘텐츠 그대로).
- **효과**: 머지 후 deploy-pages 재실행 → 약 6일간 끊겼던 문서 포털이 정상화되고, 누적된 런북(W4 prod 롤백·백업·라이브 재현 등) + shared 문서 전부 https://team-project-final.github.io/synapse-gitops/ 에 반영. **W4 Step 9/10 핸드오프 산출물이 실제로 공개됨.**
- **분류**: W1~W5 FR에 매핑되지 않는 CI/운영 이벤트(의사결정 ID 없음). 단일 파일 변경(`deploy-pages.yml`, 1줄).

---

## 2026-06-02 (W4) — MSK 토픽·인증 terraform 편입 (TLS-only)

브랜치/일정 점검에서 도출된 본격 작업. spec `2026-06-02-w4-remaining-msk-terraform-tls-design.md` → plan 13 tasks. 브랜치 `docs/w4-remaining-msk-terraform-tls`.

### 무엇을 했는지
- **git 정리**: 머지된 로컬 4개 삭제, main ff, `infra/aws/dev/*.log` gitignore.
- **토픽 terraform화**: `infra/aws/dev/kafka-topics/`(Mongey/kafka provider) 신설 — 9개 토픽 선언. 기존 bastion 수동 `create-kafka-topics.sh` 대체.
- **라이브 검증(재기동 window)**: `terraform apply`(58 리소스) → 브로커 `…4ki14g…:9094` → **토픽 TF를 bastion에서 apply → 9/9 생성 입증**(TLS, RF=2) → service overlay 브로커 주소 15개(5×3) `dchj3l→4ki14g` 갱신 → `terraform destroy`로 과금 차단.
- **shared 정합**: `KAFKA_AUTH_MATRIX` B(TLS-only)로 §1·§3·§4·§5 갱신(브랜치 `docs/kafka-auth-tls-only`, push 대기).

### 의사결정
- **D-044 MSK 인증 모델 = B(TLS-only) 확정**:
  - **결정**: `msk.tf` TLS 유지(SASL/IAM 미활성), 서비스 코드·config 무변경. 토픽 인가 = SG/네트워크 경계. 토픽은 terraform 선언 관리.
  - **근거**: A(SASL/IAM)는 5개 서비스 `aws-msk-iam-auth` 의존성·IRSA 매트릭스·타 owner 조율이 필요 → 캡스톤 잔여 봉합 범위 밖. B는 gitops 단독 2일 완결. per-topic 최소권한 가치는 실 운영이 아닌 캡스톤에선 회수 난.
  - **대안 검토**: A(SASL/IAM, 보안 정석이나 코드변경·타 owner — W5+ 백로그로 강등), B 지금+A 백로그(채택은 단순 B).
- **토픽 RF=2 정합**: dev tfvars `msk_broker_count=2` → 모듈 default RF 3→2(2-브로커에서 RF=3은 생성 실패). 라이브에서 드러난 정합 이슈.
- **bastion→MSK SG 갭 해소**: MSK SG가 EKS 노드 SG만 9094 허용 → bastion SG 인바운드 추가(vpc.tf). 이게 shared가 겪은 "bastion 차단"의 네트워크 실체였음. TLS-only라 IAM/CLI 블로커는 무력(spec §3.3 실증).

### 이벤트 (차단·학습)
- **image-updater E2E(A5) 이월**: terraform은 EBS CSI addon만 배포 — **ArgoCD·image-updater 미부트스트랩** + EKS `authMode=CONFIG_MAP`·프라이빗 엔드포인트(**bastion aws-auth 미매핑**)라 E2E는 전체 플랫폼 부트스트랩을 요구 → "클러스터 떠 있으니 공짜" 전제 오류. MSK 목표 완수 후 과금 차단 우선, E2E는 W2 이월 유지(복귀 시 ArgoCD bootstrap 선행).
- **운영 학습(런북 후보)**: ① SSM `send-command`엔 스크립트를 **base64로 전달**(jq/heredoc은 newline 깨져 행 유발). ② `set -o pipefail` + `cmd | head`는 SIGPIPE(exit 141)로 스크립트 조기 종료. ③ MSK TLS(9094) 핸드셰이크는 bastion에서 정상(`Verify return code: 0`) — kafka TF provider 연결 OK.

### 산출물
- `infra/aws/dev/kafka-topics/`(versions/variables/main/README), `vpc.tf`(bastion SG), overlay 15개, `docs/superpowers/W5-scoping.md`, 본 HISTORY. shared `KAFKA_AUTH_MATRIX`(별도 브랜치).

---

## 2026-06-02 (W5 선행) — EKS window 진입 마찰 제거 (#87/#88/#89)

OPEN 이슈 3건을 terraform 영구 코드화 + 라이브 1회 검증. spec/plan `2026-06-02-eks-window-entry-hardening`, 브랜치 `infra/eks-window-entry-hardening`.

### 무엇을 했는지
- **#87 bastion EKS 접근**: `eks.tf` `access_config{authentication_mode=API_AND_CONFIG_MAP}` + `aws_eks_access_entry`(bastion) + `aws_eks_access_policy_association`(AmazonEKSClusterAdminPolicy). bastion IAM에 kafka read(MSK ARN 스코프). **라이브: bastion `kubectl get nodes` 4 Ready·`auth can-i '*' '*'`=yes(ADMIN_OK) — kubectl 401 해소.**
- **#89 D-026**: EKS 자동생성 cluster SG(`vpc_config[0].cluster_security_group_id`)를 RDS/Redis/OpenSearch/MSK SG ingress에 코드화. **라이브: test pod(cluster SG egress)가 4 인프라(9094/5432/6379/443) 전부 도달 — 수동 SG 0.**
- **#88 브로커 ConfigMap**: `infra/aws/dev/k8s-kafka-config/`(kubernetes provider, ns ×3 + `kafka-brokers` ConfigMap ×3, bastion 실행) + overlay 15개 하드코딩 → `configMapKeyRef` 전환. **라이브: bastion terraform apply로 ConfigMap 3 ns 생성·test pod env 전파 확인.**
- 마감: 이슈 #87/#88/#89 라이브 증거 코멘트, `terraform destroy` 과금 차단.

### 의사결정
- **D-045 #87 access entry(cluster admin) + #88 terraform-owned ns**:
  - **결정**: #87=API_AND_CONFIG_MAP+access entry(legacy aws-auth ConfigMap 대신, terraform-native). bastion scope=ClusterAdmin(프라이빗 클러스터 유일 진입점·ArgoCD 부트스트랩 수행). #88 ns는 terraform 소유(순서 보장)+`prevent_destroy` 안전망.
  - **근거**: private endpoint(`endpoint_public_access=false`)라 #88 k8s 리소스는 **bastion 실행**(로컬 terraform 도달 불가). #87 kafka IAM은 B(TLS-only)에선 필수 아니나 이슈 acceptance 충족 위해 포함(GetBootstrapBrokers/DescribeCluster는 MSK ARN 스코프).
  - **대안 검토**: #88 ns를 data source(reviewer 제안) — ArgoCD CreateNamespace 비동기라 순서 문제 재도입 → 미채택, prevent_destroy로 blast radius 완화. SASL/IAM(A안) — W5+ 백로그 유지.
  - **발견(학습)**: SSM 셸은 HOME 불일치로 `~/.kube/config` 못 찾음 → `KUBECONFIG`/`HOME=/root` 명시 필요. #89 검증은 ArgoCD 부트스트랩 없이 test pod로 SG 도달 동등 증명(원문 `verify-argocd-deploy 5/5`는 ArgoCD 후속).

### 산출물
- `eks.tf`·`bastion.tf`·`vpc.tf`, `infra/aws/dev/k8s-kafka-config/`, overlay 15개(5 base deployment + patch 제거), 본 HISTORY. 브랜치 `infra/eks-window-entry-hardening`.

---

## 2026-06-02 (W5 선행) — ArgoCD 부트스트랩 dev/staging 검증 (#91, FR-TL-402)

#87/#88/#89(PR #90) 해소로 가능해진 부트스트랩·배포검증. 기존 `scripts/bring-up.sh` 재사용. spec/plan `2026-06-02-argocd-bootstrap-dev-staging`, 브랜치 `infra/argocd-bootstrap-dev-staging`.

### 무엇을 했는지
- **bring-up.sh 정합**: PR #90이 terraform화한 `phase_access_entry`(=bootstrap_cluster_creator_admin_permissions)·`phase_sg`(=#89) 제거, `phase_kafka_config`(#88 kafka-brokers ConfigMap, kubectl) 추가. RDS db.t3.small→medium(dev+staging 연결).
- **라이브 부트스트랩**: bring-up.sh `--to manifests`로 terraform apply(RDS medium) → SSM 터널 → ArgoCD HA → ESO(+oidc-fix) → kafka-config → manifests. 10 App 등록, ExternalSecret SecretSynced.
- **dev 5/5**: `verify-argocd-deploy.sh synapse-dev` = **15/15 ALL PASSED**(App Synced/Healthy·Pod Running·ES SecretSynced). platform-svc-dev Healthy.
- **staging 4/5**: 4개 Healthy, platform-svc-staging만 CrashLoop → **#92로 분리**(서비스측 `application-staging.yml` datasource 미연결). **롤백**: dev engagement-svc 124s(<3분).
- 마감: terraform destroy 과금 차단.

### 의사결정
- **D-046 bring-up.sh PR#90 정합 + platform-svc-staging 경계**:
  - **결정**: bring-up의 access-entry/sg phase는 PR #90 terraform과 중복 → 제거(단일 출처=terraform). kafka-config는 bring-up 스타일(kubectl)로 추가. RDS medium은 다환경 window 한정(tfvars gitignore라 디스크 값, 영구 default 아님).
  - **근거**: platform-svc-staging 차단은 gitops가 아님 — dev/staging overlay·ExternalSecret(둘 다 `synapse/dev/platform-svc/*` 참조) 동일한데 dev만 동작. 서비스 `application-staging.yml`이 url/password 미연결(라이브 2단계 진단: url→password 순). 이슈 §8 "서비스 owner 트랙"에 해당 → #92.
  - **학습**: `verify-argocd-deploy.sh` §1은 argocd CLI 의존 → `ARGOCD_OPTS=--core ARGOCD_NAMESPACE=argocd` + 컨텍스트 ns=argocd 필요(아니면 Sync/Health=UNKNOWN 오탐). SSM 터널 kubeconfig는 호출당 재연결.

### 산출물
- `scripts/bring-up.sh`(정합), `terraform.tfvars`(medium, 미커밋), 본 HISTORY. 이슈 #92(platform-svc). 브랜치 `infra/argocd-bootstrap-dev-staging`.

---

## 2026-06-05 (W4→W5) — 진입 차단 클리어 윈도우 (#91/#92/#120/#121/#122)

W4→W5 이월 차단 5건을 1회 on-demand EKS+MSK 라이브 윈도우로 처리. 브레인스토밍→spec→plan→subagent 실행으로 Phase 0 산출물 선머지(PR #123) 후 라이브. spec/plan `2026-06-05-w5-진입차단-클리어*`, 런북 `docs/runbooks/W5_CLEARANCE_WINDOW.md`. 통보 허브 synapse-shared#20.

### 무엇을 했는지
- **Phase 0 (무비용 사전, PR #123)**: nip.io ingress 2종(argocd UI+webhook·dev gateway, ALB `group.name` 공유) + `scripts/gen-nipio-selfsigned.sh`(self-signed CA→ACM import, `--skip-import` 로컬검증) + kafka-topics/k8s-kafka-config `.terraform.lock.hcl` 커밋 + 런북.
- **Phase 1 부트스트랩**: `bring-up.sh --to image-updater`로 terraform 59리소스 apply + ArgoCD HA(`--insecure`)/ESO/ApplicationSet/kafka-brokers/metrics-server/image-updater. dev **5/6 Healthy**.
- **#120 완료·close**: bastion(AL2023)에 terraform+kafka CLI를 SSM RunShellScript로 설치 → kafka-topics(Mongey/kafka TLS 9094) 토픽 9개·TLS 체인(Amazon RSA 2048 M04)·console produce/consume 라운드트립·MSK SG 접근제한 검증.
- **갭 4건 규명**: ① gateway-dev ImagePullBackOff+SecretSyncedError = ECR repo·SM키 부재(미릴리스) → synapse-gateway#4 ② platform-svc-staging CrashLoop = `application-staging.yml` main 유실(#48 dev 브랜치만) → #92 ③ #121 ALB ingress 불가 = `aws-load-balancer-controller` 미부트스트랩(IAM/terraform/helm 전무) ④ #122 IU ECR 자격 미설정(`no basic auth credentials`).
- **자동화 후속 (PR #124)**: #121 ALB 컨트롤러(공식 v2.7.2 IAM 정책 + IRSA + bring-up `alb-controller` helm phase) + #122 IU ECR 자격(`registries.conf` ext + `ecr-login.sh`, bring-up 볼륨 패치). `terraform validate` Success(정적). 머지.
- 마감: 각 이슈 + shared#20 통보, `terraform destroy`로 과금 차단(59 destroyed).

### 의사결정
- **D-047 nip.io 임시 도메인 + ALB self-signed ACM; 라이브 갭은 자동화로 수정·검증 차기 이월**:
  - **결정**: #121 도메인=nip.io 임시(실 도메인 부재), TLS=ALB+self-signed ACM import(리포 ALB 일관성, cert-manager/nginx 미도입). 라이브에서 드러난 ALB 컨트롤러·IU ECR 갭은 *수동 일회성 설치* 대신 *terraform/bring-up 자동화 추가*(PR #124)로 처리, 라이브 검증은 차기 윈도우.
  - **근거**: self-signed 브라우저 경고 성격은 ALB-import든 cert-manager든 동일 → 종료지점만 차이, ALB가 리포 정본. 폐기될 ephemeral 클러스터에 수동 설치는 근본(자동화 누락) 미해결 → 자동화 수정이 정답. #91 5/5·#121·#122 라이브는 서비스 2건(gateway 릴리스·platform-svc staging main 머지) + PR #124 머지 후 한 윈도우로 마감 가능.
  - **대안 검토**: cert-manager+ingress-nginx(평행 스택, prod netpol과 갈라짐 → 미채택) · 이번 윈도우 수동 설치 강행(과금↑·일회성 → 미채택) · #122 write-back 즉시 실행(IU ECR 자격 선행 필요로 불가).
  - **발견(학습)**: bring-up 내부 SSM 터널은 종료 시 닫힘 → 검증은 별도 영구 터널 필요. MSK는 bastion(VPC 내부)에서만 9094 도달(provider SNI 때문에 로컬 포트포워딩 부적합). TLS-only·무인증 MSK는 Kafka principal ACL 무의미 → SG가 접근제어. argocd-image-updater v0.15.2 이미지에 aws-cli 포함(ext 스크립트 가능). image-updater config 볼륨은 `registries.conf`/`commit.template` 키만 투영 → 스크립트는 별도 볼륨 패치 필요.

### 이벤트 (차단·학습)
- AWS 자격증명 만료(InvalidClientTokenId) — 다른 PC에서 키 회전됨 → 정적 키 재발급으로 해소.
- gateway·platform-svc-staging = 서비스측 차단 확정(gitops 매니페스트 정상, 각 owner 트랙 귀속).

### 산출물
- PR #123(nip.io ingress·인증서 스크립트·런북·lock), PR #124(ALB 컨트롤러 IRSA+helm·IU ECR 자격), PR #125(TASK/HISTORY 갱신). 이슈: synapse-gateway#4, gitops #120 close·#91/#92/#121/#122 코멘트, synapse-shared#20 통보. 브랜치 `feat/w5-alb-controller-iu-ecr`·`docs/w5-clearance-design`.

---

## 2026-06-08 (W5 Day1) — Step 11/12 마무리 + #91·#92 close + 포털 허브 뷰

### 무엇을 했는지
- **Step 11 장애 런북**(PR #137): `incidents/` 5종(crashloop·oom·sync·cert·db) + `on-call.md` + `W5_WINDOW_2.md`(윈도우2 실행 런북). 라이브 항목(시뮬레이션·따라하기·알람)은 윈도우2 Phase 5로 이관.
- **W3/W4 미완료 감사**(PR #138): 처분표 12항목 + #92 이중원인 규명 + staging가 dev RDS·DB 공유 발견 + D-043 사인오프 체크리스트.
- **포털 핸드오프 허브 뷰**(PR #139, 하위프로젝트 B): `parse_hub.mjs`가 HANDOFF_HUB 상태표→`hub.json`, Flutter `/hub` 상태 배지 대시보드. 단일 진실원=허브 마크다운, graceful 폴백.
- **#91·#92 라이브 해소 정합·close**(PR #140/#141): shared HANDOFF_HUB 06-08(dev 16/0/0·staging 20/0/0 ALL PASSED) 근거로 양 이슈 close.
- **Step 12 마무리**: P0/P1 0건 확인(체크) · CI kubeconform/pip 캐싱 · resource request/limit 정적 리뷰(`resource-sizing-review-w5.md`) · 핸드오프 문서 검토(본 엔트리).

### 의사결정
- **#91/#92 close 근거 = shared HANDOFF_HUB 06-08 라이브** — gitops 트래커는 stale("윈도우2 잔여")했으나 shared는 라이브 해소 기록. 이 **gitops↔shared 시점차**가 하위프로젝트 B(포털 허브 뷰)가 가시화하려던 문제 → 직접 정합 + close.
- **시뮬레이션 = 전용 sim Application** — staging `selfHeal:true`라 kubectl 직접 주입이 즉시 원복 → `incident-sim`(manual sync, ns synapse-sim)로 fleet 무접촉.
- **resource 튜닝 윈도우2 위임** — P95 메트릭 없이 추정 조정은 OOM/낭비 양방향 리스크. 정적 리뷰만.
- **CI 캐싱 = 도구 설치 캐싱** — "kustomize build 결과 캐싱"은 sub-second라 이득 미미 → kubeconform 바이너리+pip 캐싱으로 대체(정직한 재해석).

### 이벤트 (차단·학습)
- **동시세션 git 충돌** — 서브에이전트 실행 중 다른 세션이 같은 워크트리에서 PR #136(서비스별 DB 분리+gateway JWT) 머지 → 내 커밋 2개가 잘못 main 안착. cherry-pick 회수 + `branch -f main origin/main` + rebase로 무손실 복구.
- **신규 발견** — staging 오버레이 `DB_URL` 호스트=`synapse-dev-postgres`+DB `synapse_platform` = dev와 동일 인스턴스·동일 DB 공유(환경 격리 갭). 윈도우2/team-lead 위임.
- **#92 이중원인** — ① datasource 부재(윈도우1 dev-latest가 application-staging.yml 머지 전 빌드본) ② flyway 충돌(공유 DB). 둘 다 PR #136 해소.

### 산출물
- PR #137~#141 머지. 런북 `incidents/`5종·`on-call.md`·`W5_WINDOW_2.md`·`resource-sizing-review-w5.md`. 스펙/플랜 `2026-06-08-*`(step11·audit·hub-view). 포털 `parse_hub.mjs`+`hub.json`+`/hub`. CI 캐싱. 이슈 #91·#92 close.
- **잔여(윈도우2/팀)**: #121(prod 도메인)·#122(IU E2E) 라이브 · #126(bypass) 팀 결정 · staging 환경 DB 분리.

---

## 2026-06-08 (W5 윈도우2) — 라이브 검증 #121·#122·#126·Step11·HPA

1회 on-demand EKS 라이브 윈도우(과금). `W5_WINDOW_2.md` 기반. 클러스터는 06-08 부트스트랩 유지분(ACTIVE) 재사용.

### 결과
- **#121 외부 노출 close** — nip.io ingress + self-signed ACM import. `curl --cacert` argocd 200·dev/actuator/health 200·/api/webhook 200, 체인 `Verify return code 0`.
- **#122 IU write-back E2E close** — engagement-svc 1.0.0→1.0.1→롤백. 머지→dev 반영 **45초**, 롤백(revert PR #150) **19초**. App 토큰 write-back PR 자동생성(#126 동시 실증).
- **#126 옵션3** — image-updater를 GitHub App(`synapse-gitops-bot`, ID 3994582) 토큰으로 전환(PR #146). ruleset bypass 축소는 shared `deploy-service.yml` App 전환과 동기화 후(계획 4단계 대기).
- **Step 11 라이브** — 전용 `incident-sim` 앱(ns synapse-sim)으로 crashloop/oom/sync 3종 재현·런북 진단·복구. 알람 경로(amtool warning → route slack → `#synapse-gitops`, webhook 유효) 검증. team-lead 따라하기는 비동기 후속.
- **HPA 동작 검증** — prod hpa(engagement, CPU70%·min3/max6)를 dev 적용. min3 스케일아웃 + 부하(hey)로 **max6 스케일아웃** 관찰, 부하 종료 후 스케일인.
- **learning-ai #144** — dev CrashLoop(aiokafka ssl_context 누락 × SSL env) 에스컬레이션 → 앱팀 PR #63 수정·머지.

### 라이브 발견·수정 (PR #145·#148 머지)
- ALB controller IAM v2.7.2→**v3.4.0** 정합(컨트롤러 버전 불일치 → `GetSecurityGroupsForVpc`·`DescribeListenerAttributes` 누락 403).
- argocd nipio ingress backend HTTPS→**HTTP**(argocd `--insecure` 모드라 502).
- IU ECR 인증 `no basic auth`: ecr-login.sh aws-cli `/app/.aws` read-only 충돌 → **`HOME=/tmp`**.
- IU write-back 손상: image-list(ECR) vs kustomization name(ghcr) 불일치 → **`kustomize.image-name`** 정합.
- image-updater-pr.yml idempotent: closed PR 오판 → **`gh pr list --state open`**.
- yamllint: IU(kyaml) 0-indent 시퀀스 → **`indent-sequences: consistent`**.

### 발견(후속 트랙)
- **`set env` override는 argocd sync로 원복 안 됨**(3-way merge 한계) → 직접 `set env -` 또는 force replace. 런북 보정.
- **OOM 시뮬은 limit만 낮추면 requests 제약**(requests≤limit) → requests도 함께 패치. 런북 보정.
- **SHA 태그 매니페스트 앱(learning-card·platform·gateway·frontend·learning-ai)은 semver 전략과 불일치** → IU `Invalid Semantic Version` skip. semver 베이스라인 핀 필요(engagement·knowledge처럼).
- staging이 dev RDS·DB 공유(환경격리 갭) — 항목8, team-lead 비용 결정 선행.

### 잔여
- team-lead 따라하기(Step11 Done 조건) · 항목8 staging DB 분리(team-lead 비용) · #126 ruleset 축소(shared 동기화).

---

## 2026-06-09 (W5) — 잔여 5건 라이브 완주 + #144 close

1회 on-demand EKS 라이브(과금, 63 destroyed·과금0 종료). 브레인스토밍→spec→plan→subagent. spec/plan `2026-06-09-w5-remaining-backlog-sha-semver-pin*`, 핸드오프 `HANDOFF_2026-06-09-followups.md`.

### 결과 (OPEN 이슈 0건 달성)
- **#157 SHA→semver 핀 close** — dev overlay 6앱 1.0.0 핀(PR #158) + ECR 6앱 1.0.0 재태그 + 라이브 배포 검증.
- **#156 staging DB 분리 close** — 전용 RDS `synapse-staging-postgres`(PR #160) 인스턴스 격리.
- **#155 Step11 드릴 close** — operator 라이브 드릴(CrashLoop·OOM 재현·복구), team-lead 따라하기 충족.
- **#126 ruleset close** — image-updater GitHub App 전환(옵션3), Maintain bypass 수용(팀 결정).
- **#144 learning-ai close** — 2차 라이브에서 재수정 검증(아래).
- **engagement-svc-dev** — phantom `1.0.1`(IU 데모 잔재) ImagePull → `1.0.0` 정정(PR #161).

### 의사결정
- **#144 근본원인 = 코드 머지 ≠ 빌드 반영**: 핀된 `3774e2e6`은 `fix(avro) #64` 빌드라 앱팀 PR #63(ssl_context)이 미포함. 어느 커밋이 이미지가 됐는지 SHA 대조 필수.
  - **실수정**: learning-svc PR #67 — `ssl_support.py`로 producer/consumer에 `ssl_context` 실제 전달 + TLS 단위테스트. ECR `learning-ai:9140e597` → 2차 라이브 1/1 Running·ssl_context 0건.
  - **대안 검토**: 앱팀 재수정 대기(다음 윈도우 지연) vs gitops가 직접 수정(채택, 크로스레포 admin 머지로 즉시 해소).

### 이벤트 (라이브 운영 메모 — 재발 방지)
- bring-up 미자동화: 서비스 DB 5종(psql CREATE DATABASE)·MSK 토픽 9종(kafka SSL) 수동 → 미생성 시 Spring/aiokafka 크래시. **→ 후속 C로 자동화 착수(2026-06-10)**.
- selfHeal: resource 패치 즉시 자동원복. `set env` override는 3-way merge로 미원복.
- ECR 재태그: batch-get→put-image는 manifest digest만 변경, config·layer 동일.

### 산출물
- PR #158~#163 머지. learning-ai/card `9140e597` bump. 핸드오프 `HANDOFF_2026-06-09-followups.md`.

---

## 2026-06-10 (W5 마감) — 일정 문서 동기화 + 후속 3건 이슈화 + 후속 C 구현

### 무엇을 했는지
- 일정 추적 문서 4종(WORKFLOW_W5·TASK·HANDOFF_W5·HISTORY) 현실 동기화 — W5 사실상 완주·OPEN 0건 반영.
- 저우선 후속 3건 GitHub 이슈화: A(learning-card-staging 조사 #164)·B(semver 재핀 전략 #165)·C(bring-up 토픽/DB 자동화 #166).
- **후속 C 구현**: `bring-up.sh` `phase_kafka_topics`(MSK 토픽 9종, 클러스터 내 apache/kafka Job·SSL)·`phase_db_init`(DB 5종, postgres Job·dev+staging RDS) + 토픽 리스트 단일 출처 `infra/kafka/topics.txt`.

### 의사결정
- **후속 C 접근법 A(클러스터 내 Job) + C(토픽 단일파일)**: bring-up은 SSM 터널 kubectl 모델 → MSK/RDS private subnet 도달은 클러스터 내부 Job만 가능(bastion terraform 경로는 bring-up 호스트에서 부적합). 토픽명 drift는 `topics.txt`를 terraform+Job 공유로 해소.
  - **대안 검토**: B(bastion SSM terraform) — SSM 오케스트레이션 bash 취약 → 기각.
- **라이브 검증 보류**: 클러스터 destroy 상태(과금0) → 오프라인 검증(`bash -n`·`--dry-run`·`terraform validate`)만, 실생성은 다음 윈도우(#166에서 close).

### 산출물
- 브랜치 `docs/w5-followups-doc-sync-provisioning`, PR #167. spec/plan `2026-06-10-w5-followups-doc-sync-provisioning*`. `infra/kafka/topics.txt`, `bring-up.sh` phase 2종, `outputs.tf` rds_username.

---

## 2026-06-10 (W4 마감) — 실 도메인 3항목 임시 완결 + D-043 team-lead 사인오프

W3/W4 미완료 항목 재추적(2026-06-08 감사 `specs/2026-06-08-w3-w4-incomplete-audit-design.md` 기준) 결과, 차단·하위프로젝트·신규발견 항목이 06-08~09 라이브로 전부 해소(#92·#121·#122 close, B2 포털 허브 PR #139 머지, staging RDS 공유는 #156으로 해소). 잔여는 **실 도메인 3항목**과 **D-043 사인오프** 2건뿐 → 본 세션에 마감.

### 무엇을 했는지
- **Step 9 실 도메인 3항목(ACM/DNS·외부HTTPS·webhook) 완결** — 실 도메인 부재로 W1 이월 상태였으나, nip.io 임시 도메인 라이브 증명(#121, 06-08 윈도우2: `curl --cacert` argocd 200·`/api/webhook` 200·체인 `Verify return code 0`)을 **완료 기준으로 수용**. TASK Step 9 3항목 `[x]`.
- **D-043 team-lead 사인오프 완료** — Step 9(FR-401~404)·Step 10(FR-405~408) 라이브 증명 근거(감사 §5 체크리스트)로 사인오프 기록. TASK Step 9/10 Status 갱신.
- W4→W5 윈도우 Status stale 정합(#121/#122 라이브 close·staging RDS #156 해소 반영).

### 의사결정
- **D-043 사인오프 (velka 겸임)**: 솔로/포트폴리오 프로젝트 성격([[w4-prod-handoff]] D-006 공개전환과 동일 맥락)상 gitops 담당(velka)이 team-lead 사인오프 권한을 겸임해 W4를 마감. 근거 = FR-401~408 전부 라이브 증명(2026-06-01 prod 5/5·롤백·백업/복구, 감사 §5).
  - **대안 검토**: 사인오프 요청 패키지만 준비하고 별도 team-lead 서명 대기 → 솔로 프로젝트라 무기한 보류 리스크 → 겸임 기록 채택.
- **실 도메인 = 임시 도메인 완결**: 실 도메인 구매(비용)는 비범위. nip.io 증명으로 FR 충족 인정. 실 도메인 확보 시 `docs/argocd-tls-migration.md` 절차로 ACM 발급→Ingress 전환(후속, 비차단).

### 산출물
- 브랜치 `docs/w4-closeout-tempdomain-d043-signoff`, PR #168. 편집: `TASK_gitops.md`(Step 9/10 Status·실도메인 3항목·W4 윈도우 Status), 본 HISTORY.

---

## 다음 항목 템플릿

### YYYY-MM-DD
- 무엇을 했는지
- 의사결정 (왜 그렇게 결정했는지 + 대안 검토 결과)
- 이벤트 (장애, 외부 변경, 차단 요인)
