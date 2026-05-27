# WORKFLOW: @VelkaressiaBlutkrone — Week 3

> **Task 문서**: [TASK_gitops.md](../task/TASK_gitops.md)
> **기간**: 2026-05-26 ~ 2026-05-29, 4 영업일 (5/25 부처님오신날 제외)
> **주제**: staging 환경 + Observability 스택

---

## Step 7: staging 환경 overlay

### 1.1 사전 분석
- [x] staging 네임스페이스 분리 (`synapse-staging`)
- [x] dev → staging 승격 트리거 결정 (auto-sync — main 머지 시)
- [x] staging 리소스 산정 (replicas=2)
- [~] staging 전용 도메인 — 결정됨(`staging-<app>.<도메인>`), ACM 인증서 확보 후 Ingress 적용

### 1.2 staging overlay 작성
- [x] apps/<app>/overlays/staging/kustomization.yaml × 5
- [x] staging replicaCount=2, resources 적정값
- [x] staging ExternalSecret 경로 적용
- [x] staging Ingress 매니페스트 (`infra/ingress/staging-ingress.yaml`, TLS는 ACM 후)

### 1.3 ApplicationSet 확장
- [x] generator 매트릭스(apps × envs) 확장
- [x] dev/staging 각 5개 앱 Application 자동 생성
- [x] sync policy: dev auto, **staging auto** (prod는 W4 manual)

### 1.4 적용 + 검증 + 문서화
- [x] git push → 10개 Application (5앱 × 2환경) 자동 생성
- [x] dev → staging 승격 (auto-sync 전환 — main 머지 시 자동)
- [~] staging 헬스체크 — A2 실 EKS에서 **4/5 Healthy** (platform-svc Degraded = cross-repo 앱 레포). 도메인 헬스체크는 port-forward로 대체(ACM/도메인 확보 후 Ingress)
- [x] 승격 절차 README 작성 (`dev-to-staging-promotion.md`)

**Step 7 Status**: [ ] Not Started / [ ] In Progress / [x] Done (auto-sync·승격문서·Ingress매니페스트 완료, A2 라이브 4/5 검증. platform-svc 5/5는 app 레포 조건부)

---

## Step 8: Observability 스택 (Prometheus + Grafana + Loki)

### 1.1 사전 분석
- [x] kube-prometheus-stack 사용 결정
- [x] 로그 백엔드 = Loki 결정
- [x] 보존 기간 (Prometheus 15일, Loki 30일)
- [x] 알람 채널 = Slack 결정

### 1.2 메트릭 스택 설치
- [x] kube-prometheus-stack helm 적용 (A2 실 EKS Running)
- [x] Grafana admin 비밀번호 → ExternalSecret (ESO, A2 동기화 확인)
- [~] Grafana 외부 노출 — port-forward로 검증 (TLS/SSO는 ACM/도메인 후)
- [x] 5개 앱 ServiceMonitor 정의
- [x] /actuator/prometheus 스크레이프 확인 (A2 타깃 대부분 UP)

### 1.3 로그 스택 + 대시보드
- [x] Loki + Promtail 설치 (A2 실 EKS Running)
- [x] 로그 수집 (Promtail DaemonSet, EBS CSI 영속화)
- [x] Grafana 대시보드 (Synapse 개요)
- [ ] 앱별 상세 대시보드 — 선택, 미작성(W5 백로그)

### 1.4 알람 + 문서화
- [x] PrometheusRule: Pod 다운 5분 → critical
- [x] PrometheusRule: 메모리 90% 10분 → warning
- [x] PrometheusRule: 5xx 5% 5분 → critical
- [x] Alertmanager → Slack 라우팅 (실 webhook, A2 라우팅 확인)
- [x] 알람 발화 → slack receiver 라우팅 확인 (채널 수신은 눈 확인)
- [x] 대시보드/알람 README (`infra/monitoring/README.md`)

**Step 8 Status**: [ ] Not Started / [ ] In Progress / [x] Done (A2 실 EKS에서 스택 전체 검증 — metrics UP, Slack 라우팅, prometheus/grafana/alertmanager/loki Healthy)

---

## 정리·마감 (2026-05-27) — Day2~3 비용 0 트랙

> Step 7/8(staging+observability)은 Day1 완료. 아래는 잔여·이월/문서·포털/로컬·PM 정리(상세: HANDOFF_W3 §1, `docs/superpowers/plans/2026-05-27-w3-consolidation.md`). 비용 0 항목 완료, 라이브 검증(A3/A4/A5)은 조건부/W4. *(아래는 진척 체크박스 아님 — 참고 목록)*

- A1 cross-repo work order 발행 (PR #60, `synapse-platform-svc#37`)
- A2 ESO IRSA terraform화 (PR #61)
- A3 노드 capacity 3→4 (PR #62, 라이브 5/5 조건부)
- A4 staging ACM/TLS terraform (PR #63, 라이브 Route53 zone 필요)
- A5 image-updater A안 준비 (PR #64, write-back E2E 조건부)
- C1 미추적 아티팩트 제거 + 가이드 안착 확인 (PR #65)
- C2 local-k8s README 정합 (PR #66)
- C3 브랜치 프루닝 (로컬 8 + 원격 자동삭제)
- B1 docs-portal 콘텐츠 이미 main 안착 확인
- C4 PM 문서 정합 (본 갱신)
- W4 이월: Step 9 prod+승인게이트, Step 10 롤백/백업, B2 포털 핸드오프 허브 뷰, (조건부 미실행 시) A3/A4/A5 라이브 검증
