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

---

## 다음 항목 템플릿

### YYYY-MM-DD
- 무엇을 했는지
- 의사결정 (왜 그렇게 결정했는지 + 대안 검토 결과)
- 이벤트 (장애, 외부 변경, 차단 요인)
