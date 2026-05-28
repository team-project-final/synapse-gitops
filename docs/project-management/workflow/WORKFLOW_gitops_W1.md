# WORKFLOW: @VelkaressiaBlutkrone — Week 1

> **Task 문서**: [TASK_gitops.md](../task/TASK_gitops.md)
> **기간**: 2026-05-12 ~ 2026-05-16, 5 영업일
> **주제**: ArgoCD 부트스트랩 + ApplicationSet 골격 + CI 검증

---

## Step 1: ArgoCD 클러스터 부트스트랩

### 1.1 사전 분석
- [x] EKS 클러스터 버전/노드 그룹 확인 (1.28+ — 1.29 선택)
- [x] kubeconfig 접근 권한 점검 (kubectl get nodes 성공)
- [x] ArgoCD HA 토폴로지 결정 (server=3, controller=1, repoServer=2, applicationSet=2, redis-ha=true → D-003)
- [x] 외부 노출 방식 결정 (NLB TCP passthrough + self-signed TLS, 옵션 2 → D-001)

### 1.2 매니페스트 작성
- [x] argocd 네임스페이스 매니페스트 (Helm `create_namespace=true`)
- [x] ArgoCD Helm values 커스터마이즈 (`infra/aws/dev/argocd.tf` local.argocd_values)
- [x] argocd-server Service 외부 노출 (LoadBalancer + AWS NLB annotation)
<!-- 2026-05-28 D-041로 W4 Step 9 (prod 도메인 흐름)로 이월:
     - ACM 인증서 ARN 매핑 (HTTPS 종료)
     - DNS 레코드 정의 (argocd.<도메인>)
     사유: D-001 옵션2(self-signed) 채택 시점에 W2 마이그레이션으로 이월 표시했으나 도메인 미확보. W4 prod 도메인 확보와 함께 처리. -->

### 1.3 적용 + 검증
- [x] 매니페스트 dev 클러스터 적용 (terraform apply, Task 14)
- [x] argocd-server Pod Ready 확인 (bootstrap-argocd.sh 3/8)
- [x] argocd CLI 로그인 성공 (bootstrap-argocd.sh 5/8)
<!-- 2026-05-28 D-041로 W4 Step 9 (prod 도메인 흐름)로 이월:
     - 외부 도메인으로 UI 접속 + TLS 인증서 유효
     - webhook endpoint 외부 도달 (curl 또는 GitHub webhook ping)
     사유: 도메인 미확보. W4 prod 도메인 확보와 함께 처리. -->

### 1.4 보안 + 문서화
- [x] admin 비밀번호 회전 + AWS Secrets Manager에 저장 (bootstrap-argocd.sh 5/8, secret: synapse/argocd/admin)
- [x] RBAC 정책 정의 (admin/readonly — `argocd/bootstrap/rbac-cm.yaml`. dev 등급은 W2 SSO 후 추가)
- [x] README에 접속 방법 + 로그인 절차 기록 (`README.md`, `argocd/README.md`)
- [x] HISTORY에 의사결정 기록 (D-001 ~ D-005)

**Step 1 Status**: [ ] Not Started / [ ] In Progress / [x] Done (옵션2 코드 완료, FR-GO-102 일부 W2 이월. **kind 로컬 클러스터로 B-2 실증 완료 (server replicas 3 동작, FR-GO-101 충족)**. 실 EKS는 B-1 path로 결제수단 verification 후 재시도 예정. 상세 흐름/학습은 HISTORY 2026-05-16 참고)

---

## Step 2: app-of-apps / ApplicationSet 골격

### 1.1 사전 분석
- [x] app-of-apps vs ApplicationSet 패턴 결정 (ApplicationSet 채택)
- [x] generator 종류 결정 (matrix: list × list)
- [x] 5개 앱의 디렉토리 구조 표준화 합의 (apps/<app>/{base,overlays/{dev,staging,prod}})
- [x] sync 정책 정의 (dev=auto-sync prune selfHeal, staging/prod은 W3/W4에서 분기 재도입)

### 1.2 매니페스트 작성
- [x] argocd/projects.yaml (AppProject 정의, synapse-* namespace 한정)
- [x] argocd/applicationset.yaml (matrix: 5 svc × [dev] = 5 Application, C3)
- [x] 각 app의 source/destination/syncPolicy 템플릿 (`spec.template`)
<!-- 2026-05-28 D-002로 ApplicationSet 단독 채택 — `argocd/apps/root.yaml` 항목 제거 (선택 항목, 채택 안 됨). -->

### 1.3 적용 + 검증
- [x] ApplicationSet 매니페스트 적용 (bootstrap-argocd.sh 8/8)
- [x] ArgoCD UI에 5개 Application 표시 확인 (bootstrap-argocd.sh APP_COUNT 검증)
- [x] 각 Application의 source가 올바른 경로 가리키는지 확인 (`argocd app get` 출력)
- [x] git push → ArgoCD 자동 인식 (polling interval 3분, webhook은 W2 이월)

### 1.4 문서화
- [x] argocd/README.md에 ApplicationSet 사용법
- [x] 새 앱 추가 절차 문서화 (argocd/README.md "새 앱 추가 절차")
- [x] generator 변경 시 영향 범위 명시 (argocd/README.md "환경 추가 (W3, W4)")

**Step 2 Status**: [ ] Not Started / [ ] In Progress / [x] Done

---

## Step 3: validate-manifests CI 강화

### 1.1 사전 분석
- [x] 현재 CI(`validate-manifests.yml`) 동작 범위 점검 (kustomize build + yamllint relaxed 확인 완료)
- [x] 추가 검증 도구 후보 비교 (kubeconform vs kubeval — kubeconform 채택, D-005)
<!-- 2026-05-28 D-041로 W5 Step 11 (Runbook + 안정화)로 이월: PR 영향 범위(diff) 코멘트 도구 후보. 사유: 선택 항목, W3 이월 표시 후 W3에서 미진행. -->
- [x] branch protection 룰 적용 범위 결정 (필수 status check + REVIEWS 토글, scripts/setup-branch-protection.sh)

### 1.2 워크플로우 보강
- [x] yamllint 룰 강화 (`.yamllint` — line-length 160, indentation 2, truthy disable)
- [x] kubeconform 단계 추가 (CRD-catalog schema 포함, `-strict -ignore-missing-schemas`)
<!-- 2026-05-28 D-041로 이월:
     - kustomize build 결과 캐싱 (속도 개선) → W5 Step 12 (Cost 최적화 + 안정화)
     - PR diff 코멘트 액션 추가 → W5 Step 11 (Runbook + 안정화)
     사유: 선택 항목, W3 이월 표시 후 미진행. -->

### 1.3 적용 + 검증
- [x] 의도적 오류 PR로 검증 (잘못된 apiVersion → CI 실패 확인 — Task 14 step 8 실행)
- [x] 정상 PR로 검증 (CI 통과 — feature/w1-argocd-bootstrap-finalize PR로 검증)
- [x] main 브랜치 보호 규칙에 필수 체크 추가 (Public 전환 + GitHub Ruleset `main-protection` id 16480319, scripts/setup-branch-protection.sh로 재현 가능 — D-006)
- [x] CI 평균 실행 시간 측정 (`echo "Total: ${SECONDS}s"` 추가, 첫 PR에서 측정)

### 1.4 문서화
- [x] README에 CI 검증 단계 명시 (`README.md` "CI 검증" 섹션)
- [x] 실패 시 디버깅 가이드 (CONTRIBUTING.md "문제 해결")
- [x] CONTRIBUTING.md + `.github/PULL_REQUEST_TEMPLATE.md` 작성

**Step 3 Status**: [ ] Not Started / [ ] In Progress / [x] Done (PR diff 코멘트 + kustomize 캐싱은 W3 이월)
