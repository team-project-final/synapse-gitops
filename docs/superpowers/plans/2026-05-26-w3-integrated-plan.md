# W3 통합 작업 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 3주차에 staging 환경을 auto-sync로 완성하고, Loki+Prometheus+Grafana 관측 스택과 Slack 알람을 구축하며, W2 이월 검증과 docs-portal 마무리(정리/CI/대시보드)를 완료한다.

**Architecture:** 인프라 크리티컬 패스 우선. Day1 클러스터 기동 → Day2 staging(ApplicationSet auto-sync + 공유 Ingress) → Day3-4 관측 스택(helm 설치 + GitOps로 관리되는 ServiceMonitor/Rule/Dashboard) → docs-portal은 저위험 슬롯에 끼워넣기. 모든 관측 매니페스트는 `infra/monitoring/`에 커밋해 재현 가능하게 둔다.

**Tech Stack:** ArgoCD ApplicationSet, Kustomize, kube-prometheus-stack(Helm), Loki+Promtail(Helm), Grafana, Alertmanager, External Secrets Operator(AWS Secrets Manager), AWS Load Balancer Controller(Ingress), Flutter Web + Node(build_docs.mjs), GitHub Actions(Pages).

**설계 스펙:** [2026-05-26-w3-integrated-plan-design.md](../specs/2026-05-26-w3-integrated-plan-design.md)

---

## 작업 그룹 (독립 테스트 가능 단위)

- **Group A — Day1: 클러스터 기동 + W2 이월 검증** (A1–A3)
- **Group B — Day2: staging 마무리** (B1–B5)
- **Group C — Day3-4: 관측 스택** (C1–C8)
- **Group D — docs-portal 마무리** (D1–D4)
- **Group E — 주 마감** (E1–E2)

## 파일 구조 (생성/수정 대상)

| 경로 | 동작 | 책임 |
|---|---|---|
| `argocd/applicationset-staging.yaml` | 수정 | staging auto-sync 활성화 |
| `infra/ingress/staging-ingress.yaml` | 생성 | staging 5개 앱 공유 Ingress(ALB)+TLS |
| `docs/runbooks/dev-to-staging-promotion.md` | 생성 | 승격 절차 문서 |
| `infra/monitoring/kube-prometheus-stack-values.yaml` | 생성 | Prometheus/Grafana/Alertmanager helm 값 |
| `infra/monitoring/loki-values.yaml` | 생성 | Loki+Promtail helm 값 |
| `infra/monitoring/servicemonitor-synapse.yaml` | 생성 | Spring 4앱 + learning-ai ServiceMonitor |
| `infra/monitoring/prometheus-rules.yaml` | 생성 | 알람 3개 |
| `infra/monitoring/grafana-dashboard-synapse.yaml` | 생성 | Synapse 개요 대시보드 ConfigMap |
| `infra/monitoring/grafana-admin-externalsecret.yaml` | 생성 | Grafana admin 비밀번호 ESO |
| `infra/monitoring/alertmanager-slack-externalsecret.yaml` | 생성 | Slack webhook ESO |
| `infra/monitoring/README.md` | 생성 | 관측 스택 설치/운영 메모 |
| `.gitignore` | 수정 | node_modules/.summary-cache 무시 |
| `site/README.md` | 수정 | 기본 템플릿 → 포털 설명 |
| `.github/workflows/deploy-pages.yml` | 수정 | build_docs.mjs 실행 추가 |
| `site/lib/pages/dashboard_page.dart` | 수정 | Grafana 링크 카드 추가 |
| `docs/superpowers/HANDOFF_W3.md` | 수정 | 완료 항목/발견사항 갱신 |
| `docs/project-management/task/TASK_gitops.md` | 수정 | Step 7/8 Done 체크 |

> **GitOps 트레이드오프:** kube-prometheus-stack / Loki 본체는 시간 제약상 `helm install`(런북 절차)로 설치하고, CRD 리소스(ServiceMonitor/PrometheusRule/대시보드 ConfigMap)는 `infra/monitoring/`에 커밋 후 `kubectl apply`한다. helm 릴리스를 ArgoCD Application으로 감싸는 GitOps화는 W4/W5 백로그.

---

## Group A — Day1: 클러스터 기동 + W2 이월 검증

### Task A1: 클러스터 기동 + 5/5 Healthy 확인

**Files:** (변경 없음 — 운영 작업)

- [ ] **Step 1: 세션 부트스트랩 런북 12단계 실행**

`docs/runbooks/w2-session-bootstrap-runbook.md`를 순서대로 따른다. 핵심:
```bash
cd infra/aws/dev && terraform apply -auto-approve
```

- [ ] **Step 2: SG 수동작업(D-026) 적용**

EKS cluster SG ID를 RDS/Redis/MSK/OpenSearch SG 인바운드에 추가 (런북 D-026 절차). 누락 시 앱이 DB/Kafka 연결 실패하므로 필수.

- [ ] **Step 3: kubeconfig + ArgoCD 로그인 확인**

Run:
```bash
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl get nodes
argocd app list
```
Expected: 노드 Ready, `argocd app list`에 dev 5개 앱 표시

- [ ] **Step 4: dev 5/5 Healthy 검증**

Run:
```bash
argocd app list -o wide | grep -E "platform-svc-dev|engagement-svc-dev|knowledge-svc-dev|learning-card-dev|learning-ai-dev"
```
Expected: 5개 앱 모두 `Synced  Healthy`. 미달 시 `docs/runbooks/troubleshooting-infra.md` 참조 후 해결하고 진행.

### Task A2: W2 이월 — gitleaks 평문 시크릿 0건

**Files:** (변경 없음 — 검증 작업)

- [ ] **Step 1: gitleaks 실행**

Run:
```bash
gitleaks detect --source . --no-banner --redact
```
Expected: `no leaks found` (exit 0). 누출 발견 시 해당 커밋/파일을 ExternalSecret로 이전 후 git history 정리.

- [ ] **Step 2: TASK_gitops Step 5 체크박스 갱신**

`docs/project-management/task/TASK_gitops.md`에서 `[ ] git에 평문 시크릿 0건 확인 (gitleaks)` → `[x]`로 변경.

- [ ] **Step 3: 커밋**

```bash
git add docs/project-management/task/TASK_gitops.md
git commit -m "docs: W2 이월 — gitleaks 평문 시크릿 0건 검증 완료"
```

### Task A3: W2 이월 — 이미지 자동 sync E2E 1건 확인

**Files:** (변경 없음 — 검증 작업)

- [ ] **Step 1: Image Updater 동작 확인**

Run:
```bash
kubectl logs -n argocd deploy/argocd-image-updater --tail=50 | grep -i "update\|processing"
```
Expected: 5개 앱 처리 로그. 에러 없을 것.

- [ ] **Step 2: 최근 자동 write-back 커밋 확인**

Run:
```bash
git log --oneline --all --grep="build:" --grep="image" -i | head -5
```
Expected: image-updater write-back 커밋 존재. 없으면 svc 레포에서 semver 태그 이미지 1건 푸시 후 5분 대기하여 dev overlay `newTag` 변경 확인.

- [ ] **Step 3: TASK_gitops Step 6 체크박스 갱신 + 커밋**

`docs/project-management/task/TASK_gitops.md` Step 6의 `[ ] 새 이미지 푸시 → 5분 이내 dev에 반영 확인` → `[x]`.
```bash
git add docs/project-management/task/TASK_gitops.md
git commit -m "docs: W2 이월 — 이미지 자동 sync E2E 확인"
```

---

## Group B — Day2: staging 마무리

### Task B1: 앱 트랙에 platform-svc staging 프로필 요청 (cross-repo)

**Files:** (변경 없음 — 의존성 발행)

- [ ] **Step 1: cross-repo work-order 발행**

platform-svc 레포에 staging Spring profile(`application-staging.yml`) 부재가 staging 5/5를 막는다(HANDOFF_W3, D-가정). `docs/superpowers/specs/2026-05-21-cross-repo-work-order-design.md` 형식으로 work-order 작성하여 앱 트랙에 전달. 미해결 시 platform-svc staging은 "조건부 done"으로 기록(Task E1에서 반영).

### Task B2: staging ApplicationSet auto-sync 전환

**Files:**
- Modify: `argocd/applicationset-staging.yaml`

- [ ] **Step 1: syncPolicy에 automated 블록 추가**

`argocd/applicationset-staging.yaml`의 `spec.template.spec.syncPolicy`를 dev ApplicationSet(`argocd/applicationset.yaml:44-49`)과 동일하게 맞춘다:
```yaml
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

- [ ] **Step 2: kustomize/스키마 로컬 검증**

Run:
```bash
kubectl apply --dry-run=client -f argocd/applicationset-staging.yaml
```
Expected: `applicationset.argoproj.io/synapse-apps-staging configured (dry run)` — 에러 없음

- [ ] **Step 3: 커밋**

```bash
git add argocd/applicationset-staging.yaml
git commit -m "feat(argocd): staging ApplicationSet auto-sync 전환 (PRD FR-GO-301)"
```

### Task B3: staging 공유 Ingress + TLS

**Files:**
- Create: `infra/ingress/staging-ingress.yaml`

- [ ] **Step 1: ALB Ingress Controller 설치 여부 확인**

Run:
```bash
kubectl get deploy -n kube-system aws-load-balancer-controller
```
Expected: Running. **부재 시** 먼저 설치:
```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=synapse-dev \
  --set serviceAccount.create=true
```

- [ ] **Step 2: ACM 인증서 ARN 확인**

Run:
```bash
aws acm list-certificates --region ap-northeast-2 --query "CertificateSummaryList[].{Domain:DomainName,Arn:CertificateArn}" --output table
```
Expected: `*.<domain>` 와일드카드 인증서 ARN. 다음 스텝에서 `<ACM_ARN>`에 사용.

- [ ] **Step 3: 공유 Ingress 매니페스트 작성**

`infra/ingress/staging-ingress.yaml` (5개 앱 host 라우팅, ClusterIP Service 포트 80 → http):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: synapse-staging
  namespace: synapse-staging
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: <ACM_ARN>
    alb.ingress.kubernetes.io/healthcheck-path: /actuator/health/readiness
spec:
  rules:
    - host: staging-platform-svc.<domain>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: platform-svc, port: { number: 80 } } }
    - host: staging-engagement-svc.<domain>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: engagement-svc, port: { number: 80 } } }
    - host: staging-knowledge-svc.<domain>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: knowledge-svc, port: { number: 80 } } }
    - host: staging-learning-card.<domain>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: learning-card, port: { number: 80 } } }
    - host: staging-learning-ai.<domain>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: learning-ai, port: { number: 80 } } }
```
> `<ACM_ARN>`, `<domain>`은 Step 2 / 프로젝트 도메인 값으로 치환. learning-ai의 healthcheck-path는 Python 앱이므로 per-host 주석으로 분리 필요 시 `/health`로 조정.

- [ ] **Step 4: 적용 + ALB 프로비저닝 확인**

Run:
```bash
kubectl apply -f infra/ingress/staging-ingress.yaml
kubectl get ingress -n synapse-staging synapse-staging -w
```
Expected: ADDRESS 컬럼에 ALB DNS 표시(1-2분 소요). Route53에 `staging-*.<domain>` → ALB CNAME/Alias 레코드 추가.

- [ ] **Step 5: 커밋**

```bash
git add infra/ingress/staging-ingress.yaml
git commit -m "feat(ingress): staging 5개 앱 공유 ALB Ingress + TLS"
```

### Task B4: staging 10개 Application Synced+Healthy 검증

**Files:** (변경 없음 — 검증 작업)

- [ ] **Step 1: ApplicationSet 변경 푸시 반영 대기**

Run:
```bash
git push origin <branch> && argocd appset get synapse-apps-staging
```
Expected: 5개 generated Application, auto-sync 활성. (main 머지 후 반영되므로 staging 검증은 main 기준 — 필요 시 임시로 targetRevision 확인)

- [ ] **Step 2: 10개 Application 상태 확인**

Run:
```bash
argocd app list | grep synapse | wc -l   # 10 기대
argocd app list | grep -v "Synced.*Healthy" | grep synapse  # 비정상만 출력
```
Expected: synapse 앱 10개(5×dev+5×staging), 두번째 명령 출력은 platform-svc-staging 외 비어 있어야 함(platform-svc는 Task B1 의존으로 조건부).

- [ ] **Step 3: staging pod 2개씩 Running 확인**

Run:
```bash
kubectl get pods -n synapse-staging -l app.kubernetes.io/part-of=synapse
```
Expected: 각 앱 2 replica Running (platform-svc 제외 가능).

### Task B5: dev→staging 승격 절차 문서 + 1회 실행

**Files:**
- Create: `docs/runbooks/dev-to-staging-promotion.md`

- [ ] **Step 1: 승격 절차 문서 작성**

`docs/runbooks/dev-to-staging-promotion.md`:
```markdown
# dev → staging 승격 절차

> staging은 main 브랜치를 auto-sync한다. 승격 = main에 머지하면 자동 반영.

## 절차
1. 변경을 feature 브랜치에서 작업 → PR 생성
2. CI(validate-manifests) 통과 + 리뷰 승인
3. main 머지 → ArgoCD가 staging ApplicationSet을 통해 5분 이내 자동 sync
4. 검증: `argocd app get synapse-<svc>-staging` → Synced/Healthy
5. staging 도메인 헬스체크: `curl -s https://staging-<svc>.<domain>/actuator/health`

## 롤백
- `git revert <merge-commit>` → main 푸시 → staging 자동 복구 (W4 상세 롤백 런북 참조)
```

- [ ] **Step 2: 승격 1회 실행 (시뮬레이션)**

dev overlay에 사소한 변경(예: ConfigMap LOG_LEVEL 코멘트) PR → main 머지 → staging 자동 반영 확인.
Run:
```bash
argocd app get synapse-engagement-svc-staging | grep -E "Sync Status|Health Status|Revision"
```
Expected: 머지 커밋 SHA로 Synced, Healthy. git log에 머지 이력 존재(FR-GO-302 검증).

- [ ] **Step 3: 커밋**

```bash
git add docs/runbooks/dev-to-staging-promotion.md
git commit -m "docs: dev→staging 승격 절차 + 1회 실행 (FR-GO-302)"
```

---

## Group C — Day3-4: 관측 스택

### Task C1: Grafana admin + Slack webhook 시크릿 (AWS SM + ESO)

**Files:**
- Create: `infra/monitoring/grafana-admin-externalsecret.yaml`
- Create: `infra/monitoring/alertmanager-slack-externalsecret.yaml`

- [ ] **Step 1: AWS Secrets Manager에 시크릿 등록**

Run:
```bash
aws secretsmanager create-secret --name synapse/monitoring/grafana \
  --secret-string '{"admin-user":"admin","admin-password":"<강한비밀번호>"}' --region ap-northeast-2
aws secretsmanager create-secret --name synapse/monitoring/alertmanager \
  --secret-string '{"slack-webhook-url":"https://hooks.slack.com/services/XXX"}' --region ap-northeast-2
```
Expected: 두 시크릿 ARN 반환.

- [ ] **Step 2: monitoring 네임스페이스 + ESO ExternalSecret 작성**

`infra/monitoring/grafana-admin-externalsecret.yaml`:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: grafana-admin
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: grafana-admin
    creationPolicy: Owner
  data:
    - secretKey: admin-user
      remoteRef: { key: synapse/monitoring/grafana, property: admin-user }
    - secretKey: admin-password
      remoteRef: { key: synapse/monitoring/grafana, property: admin-password }
```
`infra/monitoring/alertmanager-slack-externalsecret.yaml`:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: alertmanager-slack
  namespace: monitoring
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: alertmanager-slack
    creationPolicy: Owner
  data:
    - secretKey: slack-webhook-url
      remoteRef: { key: synapse/monitoring/alertmanager, property: slack-webhook-url }
```

- [ ] **Step 3: 네임스페이스 생성 + 적용 + 동기화 확인**

Run:
```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f infra/monitoring/grafana-admin-externalsecret.yaml -f infra/monitoring/alertmanager-slack-externalsecret.yaml
kubectl get externalsecret -n monitoring
```
Expected: 두 ExternalSecret `SecretSynced=True`. (ESO ClusterSecretStore `aws-secrets-manager`는 W2에서 Valid 확인됨)

- [ ] **Step 4: 커밋**

```bash
git add infra/monitoring/grafana-admin-externalsecret.yaml infra/monitoring/alertmanager-slack-externalsecret.yaml
git commit -m "feat(monitoring): Grafana admin + Slack webhook ExternalSecret"
```

### Task C2: kube-prometheus-stack 설치

**Files:**
- Create: `infra/monitoring/kube-prometheus-stack-values.yaml`

- [ ] **Step 1: helm values 작성**

`infra/monitoring/kube-prometheus-stack-values.yaml`:
```yaml
prometheus:
  prometheusSpec:
    retention: 15d
    serviceMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    resources:
      requests: { cpu: 250m, memory: 1Gi }
      limits: { cpu: 1, memory: 2Gi }
grafana:
  admin:
    existingSecret: grafana-admin
    userKey: admin-user
    passwordKey: admin-password
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
alertmanager:
  alertmanagerSpec:
    resources:
      requests: { cpu: 50m, memory: 128Mi }
```

- [ ] **Step 2: helm 설치**

Run:
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f infra/monitoring/kube-prometheus-stack-values.yaml
```
Expected: `STATUS: deployed`

- [ ] **Step 3: Running 확인**

Run:
```bash
kubectl get pods -n monitoring
```
Expected: `prometheus-kube-prometheus-stack-prometheus-0`, `kube-prometheus-stack-grafana-*`, `alertmanager-kube-prometheus-stack-alertmanager-0` 모두 Running.

- [ ] **Step 4: 커밋**

```bash
git add infra/monitoring/kube-prometheus-stack-values.yaml
git commit -m "feat(monitoring): kube-prometheus-stack helm values (FR-GO-303)"
```

### Task C3: 5개 앱 ServiceMonitor

**Files:**
- Create: `infra/monitoring/servicemonitor-synapse.yaml`

- [ ] **Step 1: ServiceMonitor 작성 (Spring 4앱 + learning-ai)**

서비스 공통 라벨 `app.kubernetes.io/part-of: synapse`, 포트명 `http` 사용. Spring은 `/actuator/prometheus`, learning-ai(Python, 8090)는 `/metrics`.
`infra/monitoring/servicemonitor-synapse.yaml`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: synapse-spring
  namespace: monitoring
  labels: { release: kube-prometheus-stack }
spec:
  namespaceSelector:
    matchNames: [synapse-dev, synapse-staging]
  selector:
    matchExpressions:
      - { key: app.kubernetes.io/part-of, operator: In, values: [synapse] }
      - { key: app.kubernetes.io/name, operator: NotIn, values: [learning-ai] }
  endpoints:
    - port: http
      path: /actuator/prometheus
      interval: 30s
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: synapse-learning-ai
  namespace: monitoring
  labels: { release: kube-prometheus-stack }
spec:
  namespaceSelector:
    matchNames: [synapse-dev, synapse-staging]
  selector:
    matchLabels: { app.kubernetes.io/name: learning-ai }
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
```

- [ ] **Step 2: 적용 + Prometheus targets UP 확인**

Run:
```bash
kubectl apply -f infra/monitoring/servicemonitor-synapse.yaml
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | grep -o '"health":"[a-z]*"' | sort | uniq -c
```
Expected: 5개 앱 타깃 `"health":"up"`. **DOWN이면** 앱이 메트릭 엔드포인트를 노출하지 않는 것 → 앱 레포 의존(Spring: micrometer-registry-prometheus + `management.endpoints.web.exposure.include=prometheus`). Task B1과 함께 cross-repo work-order로 기록.

- [ ] **Step 3: 커밋**

```bash
git add infra/monitoring/servicemonitor-synapse.yaml
git commit -m "feat(monitoring): 5개 앱 ServiceMonitor (FR-GO-304)"
```

### Task C4: Loki + Promtail 설치

**Files:**
- Create: `infra/monitoring/loki-values.yaml`

- [ ] **Step 1: helm values 작성 (단일 바이너리 모드)**

`infra/monitoring/loki-values.yaml`:
```yaml
loki:
  auth_enabled: false
  commonConfig: { replication_factor: 1 }
  storage: { type: filesystem }
  limits_config: { retention_period: 720h }
singleBinary: { replicas: 1 }
read: { replicas: 0 }
write: { replicas: 0 }
backend: { replicas: 0 }
```

- [ ] **Step 2: Loki + Promtail 설치**

Run:
```bash
helm repo add grafana https://grafana.github.io/helm-charts && helm repo update
helm install loki grafana/loki -n monitoring -f infra/monitoring/loki-values.yaml
helm install promtail grafana/promtail -n monitoring \
  --set "config.clients[0].url=http://loki-gateway/loki/api/v1/push"
```
Expected: 두 릴리스 `deployed`.

- [ ] **Step 3: Promtail DaemonSet 노드 수만큼 Running + Loki datasource 추가**

Run:
```bash
kubectl get pods -n monitoring -l app.kubernetes.io/name=promtail
```
Expected: 노드 수만큼 Running. Grafana에 Loki datasource 추가(URL `http://loki-gateway`) — kube-prometheus-stack grafana sidecar용 datasource ConfigMap 또는 UI에서 추가.

- [ ] **Step 4: 5앱 로그 조회 확인**

Grafana → Explore → Loki → `{namespace="synapse-dev"}` 쿼리.
Expected: 5개 앱 로그 스트림 표시.

- [ ] **Step 5: 커밋**

```bash
git add infra/monitoring/loki-values.yaml
git commit -m "feat(monitoring): Loki+Promtail 로그 스택 (FR-GO-305)"
```

### Task C5: Synapse 개요 Grafana 대시보드

**Files:**
- Create: `infra/monitoring/grafana-dashboard-synapse.yaml`

- [ ] **Step 1: 대시보드 ConfigMap 작성 (sidecar 자동 임포트)**

`infra/monitoring/grafana-dashboard-synapse.yaml` — `grafana_dashboard: "1"` 라벨로 sidecar가 자동 로드. 패널: ① 앱 up 카운트 ② request rate ③ 5xx rate.
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: synapse-overview-dashboard
  namespace: monitoring
  labels: { grafana_dashboard: "1" }
data:
  synapse-overview.json: |
    {
      "title": "Synapse 개요",
      "uid": "synapse-overview",
      "schemaVersion": 39,
      "panels": [
        {"id":1,"title":"앱 Up","type":"stat","gridPos":{"h":6,"w":8,"x":0,"y":0},
         "targets":[{"expr":"count(up{namespace=~\"synapse-.*\"} == 1)"}]},
        {"id":2,"title":"Request Rate (5m)","type":"timeseries","gridPos":{"h":6,"w":8,"x":8,"y":0},
         "targets":[{"expr":"sum by (app_kubernetes_io_name) (rate(http_server_requests_seconds_count{namespace=~\"synapse-.*\"}[5m]))"}]},
        {"id":3,"title":"5xx Rate","type":"timeseries","gridPos":{"h":6,"w":8,"x":16,"y":0},
         "targets":[{"expr":"sum by (app_kubernetes_io_name) (rate(http_server_requests_seconds_count{namespace=~\"synapse-.*\",status=~\"5..\"}[5m]))"}]}
      ]
    }
```
> 메트릭 이름(`http_server_requests_seconds_count`)은 Spring micrometer 기준. 실제 노출 메트릭에 맞춰 Task C3 검증 후 조정.

- [ ] **Step 2: 적용 + 대시보드 표시 확인**

Run:
```bash
kubectl apply -f infra/monitoring/grafana-dashboard-synapse.yaml
```
Grafana → Dashboards → "Synapse 개요" 표시 확인, 패널에 데이터 렌더.

- [ ] **Step 3: 커밋**

```bash
git add infra/monitoring/grafana-dashboard-synapse.yaml
git commit -m "feat(monitoring): Synapse 개요 대시보드 (FR-GO-307)"
```

### Task C6: PrometheusRule 알람 3개

**Files:**
- Create: `infra/monitoring/prometheus-rules.yaml`

- [ ] **Step 1: 알람 룰 작성**

`infra/monitoring/prometheus-rules.yaml`:
```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: synapse-alerts
  namespace: monitoring
  labels: { release: kube-prometheus-stack }
spec:
  groups:
    - name: synapse.rules
      rules:
        - alert: SynapsePodDown
          expr: up{namespace=~"synapse-.*"} == 0
          for: 5m
          labels: { severity: critical }
          annotations: { summary: "{{ $labels.namespace }}/{{ $labels.pod }} 5분 이상 다운" }
        - alert: SynapseHighMemory
          expr: |
            sum by (pod,namespace) (container_memory_working_set_bytes{namespace=~"synapse-.*"})
            / sum by (pod,namespace) (kube_pod_container_resource_limits{namespace=~"synapse-.*",resource="memory"}) > 0.9
          for: 10m
          labels: { severity: warning }
          annotations: { summary: "{{ $labels.namespace }}/{{ $labels.pod }} 메모리 90% 초과" }
        - alert: SynapseHigh5xx
          expr: |
            sum by (namespace,app_kubernetes_io_name) (rate(http_server_requests_seconds_count{namespace=~"synapse-.*",status=~"5.."}[5m]))
            / sum by (namespace,app_kubernetes_io_name) (rate(http_server_requests_seconds_count{namespace=~"synapse-.*"}[5m])) > 0.05
          for: 5m
          labels: { severity: critical }
          annotations: { summary: "{{ $labels.app_kubernetes_io_name }} 5xx 비율 5% 초과" }
```

- [ ] **Step 2: 적용 + 룰 로드 확인**

Run:
```bash
kubectl apply -f infra/monitoring/prometheus-rules.yaml
kubectl get prometheusrule -n monitoring synapse-alerts
```
Expected: 생성됨. Prometheus UI(http://localhost:9090/alerts)에 3개 룰 표시.

- [ ] **Step 3: 커밋**

```bash
git add infra/monitoring/prometheus-rules.yaml
git commit -m "feat(monitoring): 알람 룰 3개 — Pod다운/메모리/5xx (FR-GO-306)"
```

### Task C7: Alertmanager → Slack 라우팅

**Files:**
- Modify: `infra/monitoring/kube-prometheus-stack-values.yaml`

- [ ] **Step 1: values에 alertmanager config 추가**

`infra/monitoring/kube-prometheus-stack-values.yaml`의 `alertmanager:` 아래에 추가. webhook은 Task C1의 `alertmanager-slack` 시크릿 사용 (alertmanagerSpec.secrets로 마운트):
```yaml
alertmanager:
  alertmanagerSpec:
    secrets: [alertmanager-slack]
    resources:
      requests: { cpu: 50m, memory: 128Mi }
  config:
    route:
      receiver: slack
      group_by: [alertname, namespace]
      routes: [{ receiver: slack, matchers: [severity=~"critical|warning"] }]
    receivers:
      - name: slack
        slack_configs:
          - api_url_file: /etc/alertmanager/secrets/alertmanager-slack/slack-webhook-url
            channel: "#synapse-gitops"
            send_resolved: true
            title: '{{ .CommonAnnotations.summary }}'
```

- [ ] **Step 2: helm upgrade 적용**

Run:
```bash
helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring -f infra/monitoring/kube-prometheus-stack-values.yaml
```
Expected: `STATUS: deployed` (revision 2)

- [ ] **Step 3: 커밋**

```bash
git add infra/monitoring/kube-prometheus-stack-values.yaml
git commit -m "feat(monitoring): Alertmanager Slack 라우팅 (#synapse-gitops)"
```

### Task C8: 알람 1건 의도 발생 → Slack 도달 확인

**Files:** (변경 없음 — 검증 작업)

- [ ] **Step 1: 의도적 알람 트리거**

dev에서 앱 1개를 0으로 스케일 → SynapsePodDown 트리거(5분):
```bash
kubectl scale deploy/engagement-svc -n synapse-dev --replicas=0
```

- [ ] **Step 2: Slack 도달 확인 후 복구**

`#synapse-gitops` 채널에 알람 수신 확인(5-6분 내). 확인 후:
```bash
kubectl scale deploy/engagement-svc -n synapse-dev --replicas=1
```
Expected: Slack에 firing + resolved 메시지. (FR-GO-306 검증 완료)

---

## Group D — docs-portal 마무리

### Task D1: 리포 정리 (playwright 로그 + .gitignore)

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: playwright 로그 삭제 확정 + .gitignore 보강**

`.gitignore`에 추가:
```gitignore
# docs portal build artifacts
site/scripts/node_modules/
site/scripts/.summary-cache.json
.playwright-mcp/
```

- [ ] **Step 2: 삭제된 로그 스테이징 + 커밋**

Run:
```bash
git add -A .playwright-mcp .gitignore
git status --short
```
Expected: 3개 로그 삭제 + .gitignore 수정만 스테이징.
```bash
git commit -m "chore: playwright 로그 제거 + 포털 빌드 산출물 gitignore"
```

### Task D2: site/README 교체

**Files:**
- Modify: `site/README.md`

- [ ] **Step 1: 기본 Flutter 템플릿 → 포털 설명으로 교체**

`site/README.md` 전체 교체:
```markdown
# Synapse Docs Portal

synapse-gitops 문서(runbook/handoff/개발가이드)를 검색·브라우즈하는 Flutter Web 포털.

## 구조
- `lib/pages/` — home / search / dashboard / doc / runbook / onboarding
- `scripts/build_docs.mjs` — Markdown → JSON + 검색 인덱스 + AI 요약 빌드

## 로컬 실행
\`\`\`bash
node scripts/build_docs.mjs   # 문서 JSON 생성
flutter pub get && flutter run -d chrome
\`\`\`

## 배포
main 푸시 시 `.github/workflows/deploy-pages.yml`이 GitHub Pages로 자동 배포.
```

- [ ] **Step 2: 커밋**

```bash
git add site/README.md
git commit -m "docs: site/README — 기본 템플릿을 포털 설명으로 교체"
```

### Task D3: Pages CI에 build_docs.mjs 반영

**Files:**
- Modify: `.github/workflows/deploy-pages.yml`

- [ ] **Step 1: Node 셋업 + build_docs.mjs 스텝 추가**

`.github/workflows/deploy-pages.yml`의 "Parse runbooks" 스텝 앞/대체로 Node 빌드 추가. `Setup Dart SDK` 스텝 뒤에 삽입:
```yaml
      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Build docs JSON (build_docs.mjs)
        working-directory: site/scripts
        run: npm ci && node build_docs.mjs
```
`paths:` 트리거에 `site/scripts/build_docs.mjs` 추가. (기존 `dart run scripts/parse-runbooks.dart` 스텝은 build_docs.mjs가 대체하면 제거, 둘 다 필요하면 유지 — build_docs.mjs 산출물과 중복 확인 후 결정)

- [ ] **Step 2: 워크플로 YAML 유효성 확인**

Run:
```bash
python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/deploy-pages.yml')); print('valid')"
```
Expected: `valid`

- [ ] **Step 3: 커밋**

```bash
git add .github/workflows/deploy-pages.yml
git commit -m "ci: Pages 배포에 build_docs.mjs 빌드 스텝 추가"
```

### Task D4: dashboard 페이지에 Grafana 링크 카드

**Files:**
- Modify: `site/lib/pages/dashboard_page.dart`

- [ ] **Step 1: 기존 dashboard_page 구조 확인**

Read: `site/lib/pages/dashboard_page.dart` — 카드/위젯 패턴 파악(`summary_card.dart` 등 재사용 가능 위젯 확인).

- [ ] **Step 2: Grafana/ArgoCD 외부 링크 카드 추가**

기존 위젯 패턴을 따라 "운영 링크" 섹션 추가 — Grafana 개요 대시보드, ArgoCD UI 외부 URL 카드. `url_launcher`(이미 의존성에 있으면 사용, 없으면 `pubspec.yaml` 추가) 또는 `Uri`+`html` 앵커. 정확한 코드는 Step 1에서 파악한 위젯 시그니처에 맞춰 작성하되, 하드코딩 URL은 빌드타임 상수(`--dart-define=GRAFANA_URL=...`)로 주입.

- [ ] **Step 3: 빌드 통과 확인**

Run:
```bash
cd site && flutter analyze && flutter build web --release --base-href /synapse-gitops/
```
Expected: analyze 무경고(기존 수준), 빌드 성공.

- [ ] **Step 4: 커밋**

```bash
git add site/lib/pages/dashboard_page.dart site/pubspec.yaml
git commit -m "feat(portal): dashboard에 Grafana/ArgoCD 운영 링크 카드"
```

---

## Group E — 주 마감

### Task E1: 핸드오프 + TASK 문서 갱신

**Files:**
- Modify: `docs/superpowers/HANDOFF_W3.md`
- Modify: `docs/project-management/task/TASK_gitops.md`

- [ ] **Step 1: HANDOFF_W3 완료 항목 + 발견사항 갱신**

`docs/superpowers/HANDOFF_W3.md` 섹션 1(완료 사항)에 W3 결과 추가: staging auto-sync 10개 Application, 관측 스택(Prometheus/Grafana/Loki/Alertmanager), 알람 3개 Slack 도달. 섹션 4 발견사항 표에 platform-svc staging 프로필 부재(조건부 done), 앱 메트릭 엔드포인트 노출 의존성을 D-0XX로 기록.

- [ ] **Step 2: TASK_gitops Step 7/8 Done 체크**

`docs/project-management/task/TASK_gitops.md` Step 7/8의 Done When 체크박스 갱신, Status를 Done으로(platform-svc staging은 조건부 명시).

- [ ] **Step 3: 커밋**

```bash
git add docs/superpowers/HANDOFF_W3.md docs/project-management/task/TASK_gitops.md
git commit -m "docs: W3 핸드오프 갱신 — staging + 관측 스택 완료"
```

### Task E2: 클러스터 정리 (비용)

**Files:** (변경 없음 — 운영 작업)

- [ ] **Step 1: 작업 완료 후 destroy**

Run:
```bash
cd infra/aws/dev && terraform destroy -auto-approve
```
Expected: 46개 리소스 삭제. S3 state bucket(`synapse-terraform-state`) + DynamoDB lock table은 유지(destroy 대상 아님).

- [ ] **Step 2: 비용 확인**

Run:
```bash
aws ce get-cost-and-usage --time-period Start=2026-05-26,End=2026-05-30 \
  --granularity DAILY --metrics UnblendedCost --region us-east-1 --output table
```
Expected: W3 기간 비용 가시화.

---

## PRD W3 커버리지 체크

| 요구사항 | 태스크 |
|---|---|
| FR-GO-301 staging auto sync | B2, B4 |
| FR-GO-302 승격 절차+1회 | B5 |
| FR-GO-303 kube-prometheus-stack | C2 |
| FR-GO-304 5앱 ServiceMonitor | C3 |
| FR-GO-305 로그 스택(Loki) | C4 |
| FR-GO-306 알람 3개+Slack 도달 | C6, C7, C8 |
| FR-GO-307 개요 대시보드 | C5 |
| W2 이월(gitleaks/이미지sync) | A2, A3 |
| docs-portal(정리/CI/대시보드) | D1–D4 |
