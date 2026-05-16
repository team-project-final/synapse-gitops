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

---

## 다음 항목 템플릿

### YYYY-MM-DD
- 무엇을 했는지
- 의사결정 (왜 그렇게 결정했는지 + 대안 검토 결과)
- 이벤트 (장애, 외부 변경, 차단 요인)
