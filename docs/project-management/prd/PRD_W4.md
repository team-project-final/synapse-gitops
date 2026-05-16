# PRD: W4 (synapse-gitops)

> **기간**: 2026-06-01 ~ 2026-06-05 (6/3 지방선거 제외, 4 영업일)
> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone

## 요구사항 목록

| 요구사항 ID | 제목 | 우선순위 | 검수 기준 |
|---|---|---|---|
| FR-GO-401 | 5개 앱 prod overlay 작성 | P0 | apps/<app>/overlays/prod/kustomization.yaml × 5 존재 |
| FR-GO-402 | prod는 Manual Sync 정책 적용 | P0 | 자동 sync 비활성, 명시적 sync만 허용 |
| FR-GO-403 | prod sync 권한 분리 | P0 | gitops-admin 그룹만 prod sync 가능 |
| FR-GO-404 | 첫 prod 배포 1회 실행 + 검증 | P0 | 5개 앱 prod 도메인 200 응답 |
| FR-GO-405 | ArgoCD History 롤백 절차 검증 | P0 | staging에서 1 step rollback 성공 |
| FR-GO-406 | git revert 기반 롤백 절차 검증 | P0 | staging에서 revert PR → sync → 이전 상태 복원 |
| FR-GO-407 | Velero 일일 백업 스케줄 동작 | P1 | 24시간 내 1회 이상 백업 성공 + S3 저장 확인 |
| FR-GO-408 | 백업으로부터 네임스페이스 복구 시뮬레이션 | P1 | staging에서 ns 삭제 → Velero 복구 성공 |
