# Runbook: W3 Staging 환경 + Observability 실행 가이드

> **대상**: gitops 트랙 담당자 (@VelkaressiaBlutkrone) 또는 후속 환경 확장 작업자
> **소요 시간**: 약 4일 (2026-05-26 ~ 2026-05-29, 5/25 부처님오신날 제외)
> **전제**: W2 완료 — dev 환경 5개 앱 Synced+Healthy, ESO 동작, 이미지 태그 자동 싱크 정상
>
> 💡 **W2 완료 상태 확인**: `argocd app list`로 5개 앱이 모두 `Synced / Healthy`인지 확인 후 진행.

---

## 0. 준비물 체크리스트

실행 전에 모두 확보:

- [ ] `kubectl` — EKS 클러스터 접근 가능 (`kubectl get nodes` 정상)
- [ ] `helm` v3.x — Prometheus/Loki 스택 설치용
- [ ] `argocd` CLI — 로그인 완료 (`argocd app list` 정상)
- [ ] `aws` CLI — Secrets Manager, Route53 접근 가능
- [ ] 작업 디렉토리: `synapse-gitops` 레포 루트, main 최신 sync 완료 (`git pull origin main`)
- [ ] W2 산출물 확인:
  - `argocd app list` — 5개 앱 `Synced / Healthy`
  - `kubectl get externalsecret -n synapse-dev` — 5개 ExternalSecret `SecretSynced`
  - 이미지 태그 자동 싱크 PR 히스토리 존재

도구 부재 시:
```bash
# macOS (Homebrew)
brew install helm kubernetes-cli argocd

# Windows (Chocolatey)
choco install kubernetes-helm kubernetes-cli argocd-cli

# Linux
# helm: https://helm.sh/docs/intro/install/
# argocd: https://argo-cd.readthedocs.io/en/stable/cli_installation/
```

---

## Step 7. Staging Overlay + ApplicationSet 확장 (2일)

dev 환경과 동일한 5개 앱을 staging 환경으로 확장하고, ApplicationSet matrix를 dev+staging 2환경으로 넓힌다. 승격 절차(dev -> staging)까지 검증.

📖 **[step7-staging-overlay.md](./step7-staging-overlay.md)** — 7-A 사전 분석 / 7-B staging overlay 작성 / 7-C ApplicationSet 확장 / 7-D 승격 시뮬레이션 + 검증 / 7-E 문서화. 총 약 7시간.

**요약**:
1. staging 네임스페이스 분리 (`synapse-staging`)
2. 5개 앱 각각 `apps/{app}/overlays/staging/kustomization.yaml` 작성 (replicas=2, 리소스 상향)
3. staging ExternalSecret 경로: `synapse/staging/{app}/*`
4. ApplicationSet generator에 staging 추가 → 5앱 x 2환경 = 10 Application
5. dev 변경 -> main merge -> staging 자동 반영 확인

**완료 조건**: `argocd app list`에서 10개 Application 모두 `Synced / Healthy`.

---

## Step 8. Observability 스택 구축 (2일)

kube-prometheus-stack + Loki/Promtail로 메트릭/로그 수집 파이프라인을 구축하고, 5개 앱 ServiceMonitor + 기본 알람 3개 + Grafana 대시보드 1개를 완성한다.

📖 **[step8-observability.md](./step8-observability.md)** — 8-A 사전 분석 / 8-B kube-prometheus-stack 설치 / 8-C ServiceMonitor 정의 / 8-D Loki+Promtail 설치 / 8-E 대시보드 작성 / 8-F 알람 설정+테스트. 총 약 5.5시간.

**요약**:
1. kube-prometheus-stack (Prometheus + Grafana + Alertmanager) Helm 설치
2. 5개 앱 ServiceMonitor — `/metrics` 또는 `/actuator/prometheus` 엔드포인트
3. Loki + Promtail DaemonSet 로그 수집
4. Synapse 개요 대시보드 (request rate, error rate, latency)
5. PrometheusRule 알람 3개: Pod 다운, 메모리 90%, 5xx 비율 5%
6. Alertmanager -> Slack 라우팅 검증

**완료 조건**: Grafana UI에서 5앱 메트릭 조회 + 로그 검색 + 알람 1건 Slack 도달.

---

## 검증 체크리스트 (PRD W3 기준)

### Staging 환경 (Step 7)

- [ ] `argocd app list` 출력에 10개 Application 표시 (5앱 x dev + 5앱 x staging)
- [ ] 10개 모두 `Synced / Healthy`
- [ ] `kubectl get pods -n synapse-staging` — 5개 앱 pod 각 2개씩 Running
- [ ] staging 도메인 헬스체크 통과: `curl -s https://staging-platform-svc.<domain>/health`
- [ ] 승격 절차: dev 변경 PR merge -> staging 자동 반영 확인 (5분 이내)

### Observability (Step 8)

- [ ] `kubectl get pods -n monitoring` — Prometheus, Grafana, Alertmanager Running
- [ ] `kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail` — 노드 수만큼 Running
- [ ] Grafana UI 접속 가능 (admin 로그인 성공)
- [ ] Grafana -> Explore -> Prometheus data source에서 5앱 메트릭 조회
- [ ] Grafana -> Explore -> Loki data source에서 로그 검색 가능
- [ ] ServiceMonitor 5개: `kubectl get servicemonitor -n monitoring`
- [ ] PrometheusRule 알람 3개 이상: `kubectl get prometheusrule -n monitoring`
- [ ] Grafana 대시보드 1개 이상: Synapse 개요
- [ ] Alertmanager -> Slack 알람 1건 도달 확인

---

## 트러블슈팅

### ApplicationSet에서 staging Application이 생성 안 됨

```bash
kubectl get applicationset -n argocd
kubectl describe applicationset synapse-apps -n argocd
# generator matrix 평가 에러 확인 — env list에 staging이 빠졌는지, path가 올바른지 점검
```

### staging 네임스페이스 pod이 Pending

```bash
kubectl describe pod -n synapse-staging <pod-name>
# 자원 부족 → 노드 그룹 scaling 또는 resource request 조정
# ExternalSecret 실패 → kubectl get externalsecret -n synapse-staging
```

### Grafana 접속 불가

```bash
# port-forward로 직접 접속 시도
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

# Ingress 사용 시 — Ingress 리소스 상태 확인
kubectl get ingress -n monitoring
kubectl describe ingress -n monitoring
```

### ServiceMonitor가 메트릭을 수집 안 함

```bash
# Prometheus targets 페이지에서 확인
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# 브라우저: http://localhost:9090/targets

# selector label 불일치가 가장 흔한 원인
kubectl get svc -n synapse-dev --show-labels
kubectl get servicemonitor -n monitoring -o yaml | grep -A5 selector
```

### 알람이 Slack에 안 옴

```bash
# Alertmanager 상태 확인
kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring
# 브라우저: http://localhost:9093/#/alerts

# Slack webhook URL 검증
kubectl get secret alertmanager-config -n monitoring -o jsonpath='{.data.slack-webhook-url}' | base64 -d

# Alertmanager config 확인
kubectl get secret kube-prometheus-stack-alertmanager -n monitoring -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d
```

---

## 일정 배분 (4일)

| 날짜 | 단계 | 예상 시간 |
|------|------|-----------|
| 05-26 (월) | 7-A 사전 분석 + 7-B staging overlay 작성 | 3.5시간 |
| 05-27 (화) | 7-C ApplicationSet 확장 + 7-D 승격 시뮬레이션 + 7-E 문서화 | 3.5시간 |
| 05-28 (수) | 8-A 사전 분석 + 8-B kube-prometheus-stack + 8-C ServiceMonitor | 2.5시간 |
| 05-29 (목) | 8-D Loki+Promtail + 8-E 대시보드 + 8-F 알람 설정+테스트 | 3시간 |

---

## 도움 요청

- 본 runbook의 단계가 막힐 때: HISTORY에 "도움 요청" 항목으로 기록 + Slack #synapse-gitops 채널
- ArgoCD ApplicationSet: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
- kube-prometheus-stack: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- Loki: https://grafana.com/docs/loki/latest/
