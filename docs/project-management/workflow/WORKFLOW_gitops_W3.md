# WORKFLOW: @VelkaressiaBlutkrone — Week 3

> **Task 문서**: [TASK_gitops.md](../task/TASK_gitops.md)
> **기간**: 2026-05-26 ~ 2026-05-29, 4 영업일 (5/25 부처님오신날 제외)
> **주제**: staging 환경 + Observability 스택

---

## Step 7: staging 환경 overlay

### 1.1 사전 분석
- [ ] staging 클러스터/네임스페이스 분리 정책 결정
- [ ] dev → staging 승격 트리거 결정 (자동 vs 수동 머지)
- [ ] staging 트래픽 규모 추정 + 리소스 산정
- [ ] staging 전용 도메인 (staging-<app>.<도메인>)

### 1.2 staging overlay 작성
- [ ] apps/<app>/overlays/staging/kustomization.yaml × 5
- [ ] staging replicaCount=2, resources 적정값
- [ ] staging ExternalSecret (synapse/staging/<app>/* 경로)
- [ ] staging Ingress + TLS

### 1.3 ApplicationSet 확장
- [ ] generator를 매트릭스(apps × envs)로 확장
- [ ] dev/staging 각 환경에 5개 앱 Application 자동 생성
- [ ] sync policy: dev auto, staging auto (prod는 W4에서 manual)

### 1.4 적용 + 검증 + 문서화
- [ ] git push → 10개 Application (5앱 × 2환경) 모두 Synced
- [ ] dev → staging 승격 1회 시뮬레이션
- [ ] staging 도메인으로 5개 앱 헬스체크 통과
- [ ] 승격 절차 README 작성

**Step 7 Status**: [ ] Not Started / [ ] In Progress / [ ] Done

---

## Step 8: Observability 스택 (Prometheus + Grafana + Loki)

### 1.1 사전 분석
- [ ] kube-prometheus-stack vs 개별 설치 결정
- [ ] 로그 수집 백엔드 결정 (Loki vs CloudWatch vs Elasticsearch)
- [ ] 메트릭/로그 보존 기간 (Prometheus 15일, Loki 30일 등)
- [ ] 알람 채널 결정 (Slack vs PagerDuty vs Email)

### 1.2 메트릭 스택 설치
- [ ] kube-prometheus-stack helm 또는 매니페스트 적용
- [ ] Grafana admin 비밀번호 → ExternalSecret 연동
- [ ] Grafana 외부 노출 + TLS + SSO
- [ ] 5개 앱 ServiceMonitor / PodMonitor 정의
- [ ] /actuator/prometheus 또는 동등 endpoint 스크레이프 확인

### 1.3 로그 스택 + 대시보드
- [ ] Loki + Promtail 또는 CloudWatch agent 설치
- [ ] 5개 앱 로그 수집 확인 (Grafana Explore에서 조회 가능)
- [ ] Grafana 대시보드 1개 이상 (Synapse 개요: 5앱 상태, 트래픽, 5xx)
- [ ] 앱별 상세 대시보드 1개 이상 (예: platform-svc)

### 1.4 알람 + 문서화
- [ ] PrometheusRule: 앱 Pod 다운 5분 이상 → critical
- [ ] PrometheusRule: 메모리 90% 이상 10분 → warning
- [ ] PrometheusRule: 5xx 비율 5% 이상 5분 → critical
- [ ] Alertmanager 라우팅 (Slack 채널 또는 PagerDuty)
- [ ] 알람 1건 의도적 발생 → 채널 도달 확인
- [ ] 대시보드/알람 README 작성

**Step 8 Status**: [ ] Not Started / [ ] In Progress / [ ] Done
