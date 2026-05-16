# PRD: W2 (synapse-gitops)

> **기간**: 2026-05-19 ~ 2026-05-23
> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone

## 요구사항 목록

| 요구사항 ID | 제목 | 우선순위 | 검수 기준 |
|---|---|---|---|
| FR-GO-201 | 5개 앱 dev overlay 작성 + 자동 sync | P0 | ArgoCD UI에서 5개 앱 모두 Synced + Healthy |
| FR-GO-202 | dev 도메인으로 5개 앱 외부 접근 가능 | P0 | dev-<app>.<도메인> 헬스체크 200 |
| FR-GO-203 | External Secrets Operator 도입 | P0 | git에 평문 시크릿 0건, ESO sync 정상 |
| FR-GO-204 | AWS Secrets Manager에서 5개 앱 시크릿 sync | P0 | 5개 ExternalSecret 모두 SecretSynced=True |
| FR-GO-205 | 새 이미지 푸시 시 dev 자동 반영 | P1 | 5분 이내 신규 이미지가 dev Pod에 반영됨 |
| FR-GO-206 | 이미지 태그 변경 이력이 git log에 남음 | P1 | git log로 추적 가능 |
