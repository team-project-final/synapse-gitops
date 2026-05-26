# Synapse 관측 스택 (monitoring)

W3 Step 8 산출물. `monitoring` 네임스페이스에 Prometheus + Grafana + Alertmanager + Loki를 구성한다.

## 구성 요소

| 파일 | 역할 |
|---|---|
| `kube-prometheus-stack-values.yaml` | Prometheus/Grafana/Alertmanager helm 값 + Slack 라우팅 |
| `loki-values.yaml` | Loki 단일 바이너리 + Promtail |
| `servicemonitor-synapse.yaml` | Spring 4앱(`/actuator/prometheus`) + learning-ai(`/metrics`) 스크레이프 |
| `prometheus-rules.yaml` | 알람 3개 — Pod 다운 / 메모리 90% / 5xx 5% |
| `grafana-dashboard-synapse.yaml` | "Synapse 개요" 대시보드 (sidecar 자동 임포트) |
| `grafana-admin-externalsecret.yaml` | Grafana admin 자격증명 (AWS SM) |
| `alertmanager-slack-externalsecret.yaml` | Slack webhook URL (AWS SM) |

## 설치 순서 (라이브 세션)

```bash
# 0) 네임스페이스 + 시크릿
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f infra/monitoring/grafana-admin-externalsecret.yaml \
               -f infra/monitoring/alertmanager-slack-externalsecret.yaml

# 1) 메트릭 스택
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f infra/monitoring/kube-prometheus-stack-values.yaml

# 2) 스크레이프/알람/대시보드
kubectl apply -f infra/monitoring/servicemonitor-synapse.yaml \
               -f infra/monitoring/prometheus-rules.yaml \
               -f infra/monitoring/grafana-dashboard-synapse.yaml

# 3) 로그 스택
helm repo add grafana https://grafana.github.io/helm-charts && helm repo update
helm install loki grafana/loki -n monitoring -f infra/monitoring/loki-values.yaml
helm install promtail grafana/promtail -n monitoring \
  --set "config.clients[0].url=http://loki-gateway/loki/api/v1/push"
```

## 사전 요구

- AWS Secrets Manager: `synapse/monitoring/grafana`, `synapse/monitoring/alertmanager`
- ESO ClusterSecretStore `aws-secrets-manager` Valid
- 앱이 메트릭 엔드포인트 노출 (Spring: micrometer-registry-prometheus + `management.endpoints.web.exposure.include=prometheus`)

## GitOps 백로그 (W4/W5)

helm 릴리스(kube-prometheus-stack, loki)를 ArgoCD Application으로 감싸 GitOps화.
