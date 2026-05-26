# dev → staging 승격 절차

> staging은 main 브랜치를 auto-sync한다 (ApplicationSet `synapse-apps-staging`). 승격 = main에 머지하면 자동 반영.

## 절차

1. 변경을 feature 브랜치에서 작업 → PR 생성
2. CI(`validate-manifests`) 통과 + 리뷰 승인
3. main 머지 → ArgoCD가 staging ApplicationSet을 통해 5분 이내 자동 sync (polling 또는 webhook)
4. 검증: `argocd app get synapse-<svc>-staging` → `Synced / Healthy`
5. staging 도메인 헬스체크:
   ```bash
   curl -s https://staging-<svc>.<domain>/actuator/health
   ```

## 롤백

- `git revert <merge-commit>` → main 푸시 → staging 자동 복구
- 상세 롤백 전략은 W4 롤백 런북(`w4-prod-rollback-runbook.md`) 참조

## 참고

- dev → staging 차이: replicas(1→2), LOG_LEVEL(DEBUG→INFO), SPRING_PROFILES_ACTIVE(dev→staging)
- staging ExternalSecret 경로: `synapse/staging/<svc>/*` (현재 dev 데이터스토어 공유 — 규모 확장 시 분리)
