# PRD: W5 (synapse-gitops)

> **기간**: 2026-06-08 ~ 2026-06-12, 5 영업일
> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone

## 요구사항 목록

| 요구사항 ID | 제목 | 우선순위 | 검수 기준 |
|---|---|---|---|
| FR-GO-501 | 장애 시나리오 Runbook 5종 작성 | P0 | docs/runbook/ 아래 5개 마크다운 파일 존재 |
| FR-GO-502 | Runbook 따라하기 검증 (team-lead) | P0 | 1개 시나리오 이상 외부인이 따라하기 성공 |
| FR-GO-503 | staging 환경 장애 시뮬레이션 3건 이상 통과 | P0 | Pod kill / OOM / sync 실패 복구 성공 |
| FR-GO-504 | On-call 연락처 + 알람 라우팅 정리 | P1 | 알람 1건 의도적 발생 → On-call 도달 확인 |
| FR-GO-505 | 5개 앱 resources requests/limits 적정화 | P1 | P95 사용량 대비 50~80% 범위로 조정 |
| FR-GO-506 | HPA 정의 + 동작 검증 (2개 앱) | P1 | 부하 발생 시 replica 증가, 정상화 시 감소 |
| FR-GO-507 | AWS Cost 태그 정책 적용 + 가시성 확보 | P2 | Cost Explorer에서 Project=synapse 필터로 비용 확인 |
| FR-GO-508 | 핸드오프 문서 최종 검토 + 사인오프 | P0 | team-lead 사인오프 + HISTORY 회고 기록 |
