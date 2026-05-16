# WORKFLOW: @VelkaressiaBlutkrone — Week 1

> **Task 문서**: [TASK_gitops.md](../task/TASK_gitops.md)
> **기간**: 2026-05-12 ~ 2026-05-16, 5 영업일
> **주제**: ArgoCD 부트스트랩 + ApplicationSet 골격 + CI 검증

---

## Step 1: ArgoCD 클러스터 부트스트랩

### 1.1 사전 분석
- [ ] EKS 클러스터 버전/노드 그룹 확인 (1.28+)
- [ ] kubeconfig 접근 권한 점검 (kubectl get nodes 성공)
- [ ] ArgoCD HA 토폴로지 결정 (replica 3, redis HA)
- [ ] 외부 노출 방식 결정 (NLB vs ALB vs Ingress)

### 1.2 매니페스트 작성
- [ ] argocd 네임스페이스 매니페스트
- [ ] ArgoCD Helm values 또는 install.yaml 커스터마이즈
- [ ] argocd-server Service 외부 노출 (LoadBalancer 또는 Ingress)
- [ ] ACM 인증서 ARN 매핑 (HTTPS 종료)
- [ ] DNS 레코드 정의 (argocd.<도메인>)

### 1.3 적용 + 검증
- [ ] 매니페스트 dev 클러스터 적용
- [ ] argocd-server Pod Ready 확인
- [ ] argocd CLI 로그인 성공
- [ ] 외부 도메인으로 UI 접속 + TLS 인증서 유효
- [ ] webhook endpoint 외부 도달 (curl 또는 GitHub webhook ping)

### 1.4 보안 + 문서화
- [ ] admin 비밀번호 회전 + 1Password/Secrets Manager에 저장
- [ ] RBAC 정책 정의 (admin/dev/readonly)
- [ ] README에 접속 방법 + 로그인 절차 기록
- [ ] HISTORY에 의사결정 기록

**Step 1 Status**: [ ] Not Started / [ ] In Progress / [ ] Done

---

## Step 2: app-of-apps / ApplicationSet 골격

### 1.1 사전 분석
- [ ] app-of-apps vs ApplicationSet 패턴 결정 (ApplicationSet 권장)
- [ ] generator 종류 결정 (list / git / cluster)
- [ ] 5개 앱의 디렉토리 구조 표준화 합의 (apps/<app>/{base,overlays/{dev,staging,prod}})
- [ ] sync 정책 정의 (auto-sync, prune, selfHeal)

### 1.2 매니페스트 작성
- [ ] argocd/projects/synapse.yaml (AppProject 정의)
- [ ] argocd/applicationsets/synapse-apps.yaml (list generator, 5개 앱)
- [ ] 각 app의 source/destination/syncPolicy 템플릿
- [ ] argocd/apps/root.yaml (선택, app-of-apps 진입점)

### 1.3 적용 + 검증
- [ ] ApplicationSet 매니페스트 적용
- [ ] ArgoCD UI에 5개 Application 표시 확인
- [ ] 각 Application의 source가 올바른 경로 가리키는지 확인
- [ ] git push → ArgoCD 자동 인식 (refresh interval 또는 webhook)

### 1.4 문서화
- [ ] argocd/README.md에 ApplicationSet 사용법
- [ ] 새 앱 추가 절차 문서화
- [ ] generator 변경 시 영향 범위 명시

**Step 2 Status**: [ ] Not Started / [ ] In Progress / [ ] Done

---

## Step 3: validate-manifests CI 강화

### 1.1 사전 분석
- [ ] 현재 CI(`validate-manifests.yml`) 동작 범위 점검
- [ ] 추가 검증 도구 후보 비교 (kubeconform vs kubeval)
- [ ] PR 영향 범위(diff) 코멘트 도구 후보 (Atlantis, kustomize-diff GH action 등)
- [ ] branch protection 룰 적용 범위 결정

### 1.2 워크플로우 보강
- [ ] yamllint 룰 강화 (.yamllint 설정)
- [ ] kubeconform 단계 추가 (모든 overlay 빌드 후 검증)
- [ ] kustomize build 결과 캐싱 (속도 개선, 선택)
- [ ] PR diff 코멘트 액션 추가 (선택)

### 1.3 적용 + 검증
- [ ] 의도적 오류 PR로 검증 (잘못된 apiVersion → CI 실패 확인)
- [ ] 정상 PR로 검증 (CI 통과 + diff 코멘트 표시)
- [ ] main 브랜치 보호 규칙에 필수 체크 추가
- [ ] CI 평균 실행 시간 측정 (목표 5분 이내)

### 1.4 문서화
- [ ] README에 CI 검증 단계 명시
- [ ] 실패 시 디버깅 가이드 (로컬 재현 방법)
- [ ] CONTRIBUTING.md 또는 .github/PULL_REQUEST_TEMPLATE.md 작성

**Step 3 Status**: [ ] Not Started / [ ] In Progress / [ ] Done
