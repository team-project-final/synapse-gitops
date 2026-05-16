# PRD: W3 (synapse-gitops)

> **기간**: 2026-05-26 ~ 2026-05-29 (5/25 부처님오신날 제외, 4 영업일)
> **트랙**: gitops
> **담당**: @VelkaressiaBlutkrone

## 요구사항 목록

| 요구사항 ID | 제목 | 우선순위 | 검수 기준 |
|---|---|---|---|
| FR-GO-301 | 5개 앱 staging overlay 작성 + 자동 sync | P0 | ArgoCD에서 5개 staging Application Synced + Healthy |
| FR-GO-302 | dev → staging 승격 절차 문서화 + 1회 실행 | P0 | README에 절차 명시, 실행 이력 git log 확인 |
| FR-GO-303 | kube-prometheus-stack 설치 | P0 | Prometheus + Grafana + Alertmanager 모두 Running |
| FR-GO-304 | 5개 앱 ServiceMonitor 정의 + 메트릭 수집 | P0 | Grafana Explore에서 5개 앱 메트릭 조회 가능 |
| FR-GO-305 | 로그 수집 스택(Loki 또는 CloudWatch) 설치 | P1 | 5개 앱 로그가 한 곳에서 조회됨 |
| FR-GO-306 | 기본 알람 3개 이상 + 채널 도달 검증 | P0 | Pod 다운/메모리/5xx 알람 발생 시 Slack/PD 도달 |
| FR-GO-307 | Synapse 개요 Grafana 대시보드 | P1 | 5앱 상태 + 트래픽 + 에러율 한 화면 표시 |
