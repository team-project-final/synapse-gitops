# Runbook: Observability 스택 구축 (Step 8 상세)

> **소요 시간**: 약 5.5시간 (2일 배분)
> **결과**: Grafana UI 접속 가능, 5앱 메트릭 수집, 알람 3개+ 동작, Loki 로그 조회 가능
> **상위 문서**: [w3-staging-observability-runbook.md](./w3-staging-observability-runbook.md) Step 8
> **사전 조건**: Step 7 완료 — 10 Application 모두 Synced+Healthy

---

## 8-A. 사전 분석 (30분)

### 설치 방식 결정

| 방식 | 장점 | 단점 |
|------|------|------|
| **kube-prometheus-stack (통합, 추천)** | Prometheus + Grafana + Alertmanager 한방 설치, CRD 포함, 커뮤니티 표준 | values.yaml이 방대 |
| 개별 설치 (prometheus + grafana 별도) | 세밀한 제어 | 버전 호환 관리 부담, CRD 수동 |

**결정**: kube-prometheus-stack 사용.

### 로그 백엔드 결정

| 방식 | 장점 | 단점 |
|------|------|------|
| **Loki + Promtail (추천)** | Grafana 네이티브 연동, 리소스 경량, label 기반 | full-text 검색 약함 |
| CloudWatch Logs | AWS 네이티브, 관리 불필요 | 비용 높음, Grafana 연동 별도 |
| Elasticsearch + Fluentd | full-text 검색 강력 | 리소스 무거움, 운영 부담 |

**결정**: Loki + Promtail 사용.

### 보존 기간

| 데이터 | 기간 | 비고 |
|--------|------|------|
| 메트릭 (Prometheus) | 15일 | dev/staging 학습용, prod 확장 시 30일+ |
| 로그 (Loki) | 7일 | 스토리지 절약 |

### 알람 채널

- **Slack**: `#synapse-alerts` 채널 (Incoming Webhook URL 사전 생성 필요)
- Webhook URL을 AWS Secrets Manager에 저장: `synapse/monitoring/slack-webhook`

### monitoring 네임스페이스

```bash
kubectl create namespace monitoring
kubectl label namespace monitoring purpose=observability project=synapse
```

```powershell
kubectl create namespace monitoring
kubectl label namespace monitoring purpose=observability project=synapse
```

---

## 8-B. kube-prometheus-stack 설치 (1시간)

### Helm repo 추가

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
```

### custom values 파일 작성

```yaml
# monitoring/kube-prometheus-stack-values.yaml
prometheus:
  prometheusSpec:
    retention: 15d
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
    resources:
      requests:
        cpu: 500m
        memory: 1Gi
      limits:
        cpu: "1"
        memory: 2Gi
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false

grafana:
  enabled: true
  adminPassword: ""  # ESO로 주입하거나 설치 시 --set으로 전달
  persistence:
    enabled: true
    size: 10Gi
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi
  ingress:
    enabled: true
    annotations:
      kubernetes.io/ingress.class: alb
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/certificate-arn: <ACM_CERT_ARN>
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    hosts:
      - grafana.<domain>
    tls:
      - hosts:
          - grafana.<domain>
  sidecar:
    dashboards:
      enabled: true
      searchNamespace: ALL
    datasources:
      enabled: true

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 200m
        memory: 256Mi
  config:
    global:
      resolve_timeout: 5m
    route:
      group_by: ['alertname', 'namespace']
      group_wait: 30s
      group_interval: 5m
      repeat_interval: 4h
      receiver: 'slack-notifications'
      routes:
        - match:
            severity: critical
          receiver: 'slack-critical'
          repeat_interval: 1h
    receivers:
      - name: 'slack-notifications'
        slack_configs:
          - api_url_file: /etc/alertmanager/secrets/slack-webhook-url
            channel: '#synapse-alerts'
            send_resolved: true
            title: '[{{ .Status | toUpper }}] {{ .CommonLabels.alertname }}'
            text: >-
              {{ range .Alerts }}
              *Alert:* {{ .Annotations.summary }}
              *Namespace:* {{ .Labels.namespace }}
              *Severity:* {{ .Labels.severity }}
              {{ end }}
      - name: 'slack-critical'
        slack_configs:
          - api_url_file: /etc/alertmanager/secrets/slack-webhook-url
            channel: '#synapse-alerts'
            send_resolved: true
            title: ':rotating_light: [CRITICAL] {{ .CommonLabels.alertname }}'
            text: >-
              {{ range .Alerts }}
              *Alert:* {{ .Annotations.summary }}
              *Description:* {{ .Annotations.description }}
              *Namespace:* {{ .Labels.namespace }}
              {{ end }}

defaultRules:
  create: true
  rules:
    kubeScheduler: false  # EKS managed, 접근 불가
    kubeControllerManager: false
    kubeProxy: false
```

### Grafana admin 비밀번호 생성

```bash
# 비밀번호 생성
GRAFANA_PASS=$(openssl rand -base64 16)
echo "Grafana admin password: ${GRAFANA_PASS}"

# Secrets Manager에 저장
aws secretsmanager create-secret \
  --name synapse/monitoring/grafana-admin \
  --secret-string "{\"password\":\"${GRAFANA_PASS}\"}" \
  --region ap-northeast-2
```

```powershell
$grafanaPass = [Convert]::ToBase64String((1..16 | ForEach-Object { Get-Random -Maximum 256 }) -as [byte[]])
Write-Host "Grafana admin password: $grafanaPass"

aws secretsmanager create-secret `
    --name "synapse/monitoring/grafana-admin" `
    --secret-string "{`"password`":`"$grafanaPass`"}" `
    --region ap-northeast-2
```

### Slack Webhook URL 등록

```bash
# Slack App에서 Incoming Webhook URL을 발급받은 후:
aws secretsmanager create-secret \
  --name synapse/monitoring/slack-webhook \
  --secret-string '{"url":"https://hooks.slack.com/services/T.../B.../xxx"}' \
  --region ap-northeast-2
```

### Helm install 실행

```bash
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values monitoring/kube-prometheus-stack-values.yaml \
  --set grafana.adminPassword="${GRAFANA_PASS}" \
  --version 58.x.x \
  --wait --timeout 10m
```

```powershell
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
    --namespace monitoring `
    --values monitoring/kube-prometheus-stack-values.yaml `
    --set "grafana.adminPassword=$grafanaPass" `
    --version 58.x.x `
    --wait --timeout 10m
```

### 설치 검증

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

**Expected**:
- `prometheus-kube-prometheus-stack-prometheus-0` — Running
- `kube-prometheus-stack-grafana-*` — Running
- `alertmanager-kube-prometheus-stack-alertmanager-0` — Running
- `kube-prometheus-stack-operator-*` — Running
- `kube-state-metrics-*` — Running
- `node-exporter-*` — 노드 수만큼 Running

### Grafana 접속 검증

```bash
# Ingress 미설정 시 port-forward
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
# 브라우저: http://localhost:3000
# ID: admin / PW: 위에서 생성한 비밀번호
```

---

## 8-C. ServiceMonitor 정의 (1시간)

5개 앱 각각에 대해 ServiceMonitor를 생성하여 Prometheus가 메트릭을 수집하도록 한다.

### ServiceMonitor 템플릿 (platform-svc 예시)

```yaml
# monitoring/servicemonitors/platform-svc-servicemonitor.yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: platform-svc
  namespace: monitoring
  labels:
    app: platform-svc
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - synapse-dev
      - synapse-staging
  selector:
    matchLabels:
      app: platform-svc
  endpoints:
    - port: http
      path: /actuator/prometheus    # Spring Boot 기본. 앱에 따라 /metrics 사용
      interval: 30s
      scrapeTimeout: 10s
```

### 5개 앱 ServiceMonitor 일괄 생성

```bash
APPS="platform-svc engagement-svc knowledge-svc learning-card learning-ai"
for app in $APPS; do
  cat > "monitoring/servicemonitors/${app}-servicemonitor.yaml" << EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ${app}
  namespace: monitoring
  labels:
    app: ${app}
    release: kube-prometheus-stack
spec:
  namespaceSelector:
    matchNames:
      - synapse-dev
      - synapse-staging
  selector:
    matchLabels:
      app: ${app}
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 30s
      scrapeTimeout: 10s
EOF
  echo "Created ServiceMonitor for ${app}"
done
```

### 적용 + 검증

```bash
kubectl apply -f monitoring/servicemonitors/ -n monitoring
kubectl get servicemonitor -n monitoring
```

**Expected**: 5개 ServiceMonitor 표시.

### Prometheus targets 확인

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# 브라우저: http://localhost:9090/targets
# 5개 앱의 target이 "UP" 상태인지 확인
```

**주의**: 앱 Service에 `app: <app-name>` label이 있어야 selector가 매칭됨. 없으면:
```bash
kubectl get svc -n synapse-dev --show-labels
# label 누락 시 Service 또는 ServiceMonitor selector 수정
```

---

## 8-D. Loki + Promtail 설치 (1시간)

### Helm repo 추가

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### Loki values 작성

```yaml
# monitoring/loki-stack-values.yaml
loki:
  enabled: true
  persistence:
    enabled: true
    size: 20Gi
  config:
    limits_config:
      retention_period: 168h    # 7일
    table_manager:
      retention_deletes_enabled: true
      retention_period: 168h
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 512Mi

promtail:
  enabled: true
  config:
    clients:
      - url: http://loki:3100/loki/api/v1/push
    snippets:
      pipelineStages:
        - docker: {}
        - match:
            selector: '{namespace=~"synapse-.*"}'
            stages:
              - regex:
                  expression: '.*level=(?P<level>\w+).*'
              - labels:
                  level:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
```

### Helm install

```bash
helm install loki-stack grafana/loki-stack \
  --namespace monitoring \
  --values monitoring/loki-stack-values.yaml \
  --wait --timeout 5m
```

```powershell
helm install loki-stack grafana/loki-stack `
    --namespace monitoring `
    --values monitoring/loki-stack-values.yaml `
    --wait --timeout 5m
```

### 설치 검증

```bash
kubectl get pods -n monitoring -l app=loki
kubectl get pods -n monitoring -l app=promtail
kubectl get ds -n monitoring    # Promtail은 DaemonSet
```

**Expected**:
- `loki-0` — Running
- `loki-stack-promtail-*` — 노드 수만큼 Running (DaemonSet)

### Grafana에 Loki data source 추가

kube-prometheus-stack의 Grafana sidecar가 자동 검색하지 못할 경우 수동 추가:

```bash
# Grafana UI: Configuration → Data sources → Add data source → Loki
# URL: http://loki:3100
# Save & Test
```

또는 ConfigMap으로 선언적 관리:

```yaml
# monitoring/grafana-loki-datasource.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-loki-datasource
  namespace: monitoring
  labels:
    grafana_datasource: "true"
data:
  loki-datasource.yaml: |
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        access: proxy
        url: http://loki:3100
        isDefault: false
        editable: true
```

```bash
kubectl apply -f monitoring/grafana-loki-datasource.yaml
# Grafana sidecar가 자동 reload (약 30초)
```

### 로그 조회 테스트

```bash
# Grafana UI: Explore → Data source: Loki
# Query: {namespace="synapse-dev"}
# 또는 CLI:
kubectl port-forward svc/loki 3100:3100 -n monitoring
curl -s "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={namespace="synapse-dev"}' \
  --data-urlencode 'limit=5' | jq '.data.result | length'
```

**Expected**: 1 이상의 결과.

---

## 8-E. 대시보드 작성 (1시간)

### Synapse 개요 대시보드 구성

Grafana에서 다음 패널을 포함하는 "Synapse Overview" 대시보드를 생성한다:

| 패널 | PromQL / LogQL | 유형 |
|------|----------------|------|
| 앱별 Pod 상태 | `kube_pod_status_phase{namespace=~"synapse-.*"} == 1` | Stat |
| Request Rate (5m) | `sum(rate(http_server_requests_seconds_count{namespace=~"synapse-.*"}[5m])) by (app)` | Time series |
| Error Rate (5xx, 5m) | `sum(rate(http_server_requests_seconds_count{namespace=~"synapse-.*",status=~"5.."}[5m])) by (app) / sum(rate(http_server_requests_seconds_count{namespace=~"synapse-.*"}[5m])) by (app) * 100` | Time series |
| P99 Latency | `histogram_quantile(0.99, sum(rate(http_server_requests_seconds_bucket{namespace=~"synapse-.*"}[5m])) by (le, app))` | Time series |
| 최근 에러 로그 | `{namespace=~"synapse-.*"} \|= "ERROR"` | Logs |
| Pod 메모리 사용률 | `container_memory_working_set_bytes{namespace=~"synapse-.*",container!=""} / container_spec_memory_limit_bytes{namespace=~"synapse-.*",container!=""} * 100` | Gauge |
| Pod CPU 사용률 | `sum(rate(container_cpu_usage_seconds_total{namespace=~"synapse-.*",container!=""}[5m])) by (pod) * 100` | Time series |

### 대시보드 JSON export -> ConfigMap

1. Grafana UI에서 대시보드 완성 후 Share → Export → Save to file (JSON)
2. JSON을 ConfigMap으로 래핑:

```yaml
# monitoring/dashboards/synapse-overview-dashboard.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: synapse-overview-dashboard
  namespace: monitoring
  labels:
    grafana_dashboard: "true"
data:
  synapse-overview.json: |
    {
      "dashboard": {
        "title": "Synapse Overview",
        "uid": "synapse-overview",
        "panels": [
          ...  # Grafana에서 export한 JSON 내용
        ]
      }
    }
```

```bash
kubectl apply -f monitoring/dashboards/synapse-overview-dashboard.yaml
# Grafana sidecar가 자동 import (약 30초)
```

### 검증

- [ ] Grafana → Dashboards → "Synapse Overview" 표시
- [ ] 각 패널에 데이터 표시 (앱이 트래픽을 받고 있어야 request rate 등이 보임)
- [ ] Loki 로그 패널에 최근 로그 표시

---

## 8-F. 알람 설정 + 테스트 (1시간)

### PrometheusRule 정의 (알람 3개)

```yaml
# monitoring/prometheus-rules/synapse-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: synapse-alerts
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: synapse.rules
      rules:
        # 알람 1: Pod 다운 5분 (critical)
        - alert: SynapsePodDown
          expr: |
            kube_pod_status_phase{namespace=~"synapse-.*", phase="Running"} == 0
            and on(pod, namespace)
            kube_pod_status_phase{namespace=~"synapse-.*", phase=~"Failed|Unknown"} == 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Pod {{ $labels.pod }} in {{ $labels.namespace }} is down for 5+ minutes"
            description: "Pod {{ $labels.pod }} in namespace {{ $labels.namespace }} has been in a non-running state for more than 5 minutes."

        # 알람 2: 메모리 90% 10분 (warning)
        - alert: SynapseHighMemoryUsage
          expr: |
            (container_memory_working_set_bytes{namespace=~"synapse-.*", container!=""}
            / container_spec_memory_limit_bytes{namespace=~"synapse-.*", container!=""}) > 0.9
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "Container {{ $labels.container }} in {{ $labels.namespace }} memory > 90%"
            description: "Container {{ $labels.container }} in pod {{ $labels.pod }} has been using more than 90% of its memory limit for 10+ minutes. Current usage: {{ $value | humanizePercentage }}."

        # 알람 3: 5xx 비율 5% 5분 (critical)
        - alert: SynapseHighErrorRate
          expr: |
            (sum(rate(http_server_requests_seconds_count{namespace=~"synapse-.*", status=~"5.."}[5m])) by (app, namespace)
            / sum(rate(http_server_requests_seconds_count{namespace=~"synapse-.*"}[5m])) by (app, namespace)) > 0.05
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "App {{ $labels.app }} in {{ $labels.namespace }} 5xx error rate > 5%"
            description: "Application {{ $labels.app }} in namespace {{ $labels.namespace }} has a 5xx error rate above 5% for 5+ minutes. Current rate: {{ $value | humanizePercentage }}."
```

### 적용

```bash
kubectl apply -f monitoring/prometheus-rules/synapse-alerts.yaml
kubectl get prometheusrule -n monitoring
```

```powershell
kubectl apply -f monitoring/prometheus-rules/synapse-alerts.yaml
kubectl get prometheusrule -n monitoring
```

**Expected**: `synapse-alerts` PrometheusRule 표시.

### Prometheus UI에서 알람 규칙 확인

```bash
kubectl port-forward svc/kube-prometheus-stack-prometheus 9090:9090 -n monitoring
# 브라우저: http://localhost:9090/alerts
# 3개 알람 규칙 표시 확인 (Inactive 상태가 정상)
```

### Alertmanager -> Slack 라우팅 검증

Slack webhook URL이 올바르게 설정되었는지 확인:

```bash
# Alertmanager config 확인
kubectl port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 -n monitoring
# 브라우저: http://localhost:9093/#/status
# Configuration 섹션에서 slack_configs가 표시되는지 확인
```

### 의도적 알람 트리거 테스트

```bash
# 방법 1: 임시 pod을 만들어 메모리 90% 이상 사용
kubectl run memory-stress-test \
  --namespace synapse-dev \
  --image=polinux/stress \
  --limits="memory=128Mi" \
  --requests="memory=128Mi" \
  --restart=Never \
  -- stress --vm 1 --vm-bytes 120M --timeout 600s

# 10분 대기 후 SynapseHighMemoryUsage 알람 발동 확인

# 방법 2: 테스트용 낮은 임계치 알람 생성 (빠른 검증)
cat << 'EOF' | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: synapse-test-alert
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: synapse.test
      rules:
        - alert: SynapseTestAlert
          expr: vector(1)
          for: 1m
          labels:
            severity: warning
          annotations:
            summary: "Test alert - please ignore"
            description: "This is a test alert to verify Slack routing."
EOF

# 1분 후 Slack #synapse-alerts 채널에 알림 도달 확인
```

```powershell
# 테스트 알람 (vector(1)로 즉시 발동)
@"
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: synapse-test-alert
  namespace: monitoring
  labels:
    release: kube-prometheus-stack
spec:
  groups:
    - name: synapse.test
      rules:
        - alert: SynapseTestAlert
          expr: vector(1)
          for: 1m
          labels:
            severity: warning
          annotations:
            summary: "Test alert - please ignore"
            description: "This is a test alert to verify Slack routing."
"@ | kubectl apply -f -
```

**Expected**: 1~2분 내에 Slack `#synapse-alerts` 채널에 `SynapseTestAlert` 알림 도달.

### 테스트 자원 정리

```bash
# 테스트 알람 제거
kubectl delete prometheusrule synapse-test-alert -n monitoring

# 스트레스 테스트 pod 제거
kubectl delete pod memory-stress-test -n synapse-dev --ignore-not-found
```

---

## 검증

- [ ] `kubectl get pods -n monitoring` — 모든 pod Running
- [ ] Grafana UI 접속 가능 (admin 로그인 성공)
- [ ] Grafana → Data sources: Prometheus + Loki 두 개 연결됨
- [ ] Grafana → Explore → Prometheus: `up{namespace=~"synapse-.*"}` 조회 시 5앱 표시
- [ ] Grafana → Explore → Loki: `{namespace="synapse-dev"}` 로그 표시
- [ ] `kubectl get servicemonitor -n monitoring` — 5개 표시
- [ ] `kubectl get prometheusrule -n monitoring` — `synapse-alerts` 표시 (알람 3개 포함)
- [ ] Grafana → Dashboards → "Synapse Overview" 대시보드 표시
- [ ] Alertmanager → Slack 테스트 알람 1건 도달 확인

---

## 자주 막히는 지점

### helm values 충돌

**증상**: `helm install` 실패, `Error: rendered manifests contain a resource that already exists`.

**원인**: 이전에 개별 설치한 CRD(ServiceMonitor 등)가 남아있음.

**해결**:
```bash
# 기존 CRD 확인
kubectl get crd | grep monitoring.coreos.com
# 충돌 CRD 삭제 후 재설치 (주의: 기존 ServiceMonitor 등도 삭제됨)
kubectl delete crd prometheusrules.monitoring.coreos.com servicemonitors.monitoring.coreos.com
helm install kube-prometheus-stack ...
```

### ServiceMonitor selector 불일치

**증상**: Prometheus targets 페이지에 앱 target이 안 보임.

**원인**: ServiceMonitor의 `selector.matchLabels`와 앱 Service의 labels가 불일치.

**해결**:
```bash
# 앱 Service의 실제 label 확인
kubectl get svc -n synapse-dev -o jsonpath='{range .items[*]}{.metadata.name}: {.metadata.labels}{"\n"}{end}'

# ServiceMonitor selector를 실제 label에 맞게 수정
```

또한 `serviceMonitorSelectorNilUsesHelmValues: false`가 values에 설정되어야 Helm release 외부의 ServiceMonitor도 인식함.

### Promtail 권한 문제

**증상**: Promtail pod이 `CrashLoopBackOff`, 로그에 `permission denied`.

**원인**: 노드의 `/var/log` 또는 container runtime 로그 경로 접근 권한 없음.

**해결**:
```bash
kubectl logs -n monitoring -l app=promtail --tail=50
# SecurityContext 확인 — Promtail은 privileged 또는 적절한 volume mount 필요
# EKS + containerd: /var/log/pods 경로 사용
```

### Grafana 접속 불가

**증상**: Ingress로 접속 시 502/504, port-forward는 동작.

**원인**: ALB target group 헬스체크 실패 또는 Grafana pod readiness probe 실패.

**해결**:
```bash
# pod 상태 확인
kubectl describe pod -n monitoring -l app.kubernetes.io/name=grafana
# Ingress 상태
kubectl describe ingress -n monitoring
# ALB target group 헬스 (AWS 콘솔)
# port-forward로 우회:
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring
```

### 알람 미발송 (Slack webhook URL)

**증상**: Prometheus UI에서 알람이 Firing이지만 Slack에 안 옴.

**원인**: Alertmanager의 Slack webhook URL이 잘못되었거나, Alertmanager가 외부 네트워크에 접근 못함.

**해결**:
```bash
# Alertmanager 로그 확인
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager --tail=50 | grep -i slack

# webhook URL 직접 테스트
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Alertmanager test from CLI"}' \
  "https://hooks.slack.com/services/T.../B.../xxx"

# NAT Gateway / Security Group에서 outbound HTTPS 허용 여부 확인
```

---

## 다음 단계

Observability 스택 완성 후 상위 runbook의 [검증 체크리스트](./w3-staging-observability-runbook.md#검증-체크리스트-prd-w3-기준)를 통과하면 W3 완료.

W4에서는 prod 환경 확장 + CI/CD 파이프라인 고도화를 진행할 예정.
