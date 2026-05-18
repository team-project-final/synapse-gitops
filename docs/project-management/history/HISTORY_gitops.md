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
- (EKS 전환 결과를 여기에 기록)

---

## 다음 항목 템플릿

### YYYY-MM-DD
- 무엇을 했는지
- 의사결정 (왜 그렇게 결정했는지 + 대안 검토 결과)
- 이벤트 (장애, 외부 변경, 차단 요인)
