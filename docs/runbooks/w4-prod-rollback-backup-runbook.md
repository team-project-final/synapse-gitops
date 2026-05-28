# W4 prod 롤백·백업 Runbook

> RTO 30분 / RPO 1시간 (team-lead 합의). 1차 롤백=GitOps 코드 경로, DB=forward-only.
> 관련 설계: [W4 prod 설계 spec §5](../superpowers/specs/2026-05-27-w4-prod-design.md)

## 1. ArgoCD History 롤백 (FR-GO-405)

1. `argocd app history synapse-<svc>-prod` 로 직전 synced revision ID 확인
2. `argocd app rollback synapse-<svc>-prod <id>` (prod는 `gitops-admin` 계정)
3. `argocd app get synapse-<svc>-prod` → Synced/Healthy 확인

- 적용 대상: 워크로드/설정 회귀. 단발 1-step 롤백.
- prod는 manual sync라 rollback도 `gitops-admin` 권한 필요(`role:prod-deployer`).

## 2. git revert 롤백 (FR-GO-406)

1. 문제 커밋 `git revert <sha>` → revert PR 생성
2. main 머지 (PR 보호 게이트 통과)
3. sync: staging은 auto, prod는 `gitops-admin` 수동 `argocd app sync synapse-<svc>-prod`

- 적용 대상: 영구 롤백(소스 of truth 복원).

## 3. 이미지 롤백

- overlay `images[].newTag` 를 직전 태그로 되돌리는 PR (승격이 PR이므로 동일 경로) → 2와 동일 sync.

## 4. DB 스키마

- forward-only(Flyway). 위 메커니즘으로 스키마 롤백하지 않음. 데이터는 RDS 자동백업(PITR)로 복구.

## 5. Velero 복구 시뮬레이션 (FR-GO-408)

1. (드릴) `kubectl delete ns synapse-staging` 또는 일부 리소스 삭제
2. `velero restore create --from-backup <backup-name> --include-namespaces synapse-staging --wait`
3. `kubectl get pods -n synapse-staging` → 복구 확인

- etcd는 관리형 EKS=AWS 책임, 직접 snapshot 불가.
- 백업 정의: [velero-schedule.yaml](../../infra/monitoring/velero-schedule.yaml) (일일, synapse-prod/staging ns+PV).
- 백업 실패 알람: [prometheus-rules.yaml](../../infra/monitoring/prometheus-rules.yaml) `velero.rules` → Alertmanager Slack.

## 한계 (캡스톤)

- Velero 일일 스케줄 → 객체/PV RPO 최대 24h. DB는 RDS PITR가 RPO 1h 별도 보장.
- prod/staging 논리 분리 — Kafka 토픽/OpenSearch 인덱스 공유.
