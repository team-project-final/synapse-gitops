## 변경 요약
<!-- 무엇을, 왜 -->

## 영향 범위
- [ ] dev 환경
- [ ] staging 환경
- [ ] prod 환경
- [ ] CI / 빌드만
- [ ] 문서만

## 로컬 검증
- [ ] `yamllint -c .yamllint apps/ argocd/ infra/` 통과
- [ ] `kustomize build apps/<svc>/overlays/<env>` 통과
- [ ] `kustomize build ... | kubeconform -strict -ignore-missing-schemas` 통과
- [ ] (해당 시) `terraform fmt -check && terraform validate` 통과
- [ ] (해당 시) `bash -n scripts/*.sh` 통과

## ArgoCD Sync 영향
- [ ] 자동 sync로 즉시 반영됨
- [ ] 수동 sync 필요
- [ ] sync 영향 없음

## 관련 문서
<!-- TASK / WORKFLOW / HISTORY / 스펙 / 플랜 링크 -->
