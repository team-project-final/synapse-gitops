# Runbook: 비용 최적화 + 안정화 + 핸드오프 (Step 12 상세)

> **소요 시간**: 2일 (약 7시간 실작업)
> **결과**: 비용 가시성 확보, HPA 동작 검증, P0/P1 이슈 0건, 핸드오프 완료
> **상위 문서**: [w5-stabilize-runbook.md](./w5-stabilize-runbook.md) Step 12
> **사전 조건**: Step 11 완료 (장애 Runbook 5개 + 시뮬레이션 + On-call 체계)

---

## 12-A. 비용 가시성 확보 (1시간)

### 태그 정책

| 태그 키 | 값 | 설명 |
|---|---|---|
| `Project` | `synapse` | 프로젝트 식별 |
| `Environment` | `dev` / `staging` / `prod` | 환경 구분 |
| `Service` | `platform-svc` / `engagement-svc` / `knowledge-svc` / `learning-card` / `learning-ai` | 서비스 구분 |
| `ManagedBy` | `terraform` / `argocd` / `manual` | 관리 주체 |

### 태그 미적용 자원 식별 + 추가

```bash
# 미태깅 자원 검색
aws resourcegroupstaggingapi get-resources --region ap-northeast-2 \
  --no-tag-filters --resource-type-filters ec2:instance ec2:volume rds:db \
  --query 'ResourceTagMappingList[?!Tags[?Key==`Project`]].ResourceARN' --output table

# 태그 추가 예시
aws ec2 create-tags --resources <instance-id> --tags \
  Key=Project,Value=synapse Key=Environment,Value=prod Key=Service,Value=platform-svc
```

### 비용 분포 측정

```bash
# 서비스별 비용
aws ce get-cost-and-usage \
  --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{"Tags":{"Key":"Project","Values":["synapse"]}}' --output table

# 환경별 비용
aws ce get-cost-and-usage \
  --time-period Start=$(date -u +%Y-%m-01),End=$(date -u +%Y-%m-%d) \
  --granularity MONTHLY --metrics "UnblendedCost" \
  --group-by Type=TAG,Key=Environment \
  --filter '{"Tags":{"Key":"Project","Values":["synapse"]}}' --output table
```

Cost Explorer 콘솔에서 월별 추이 그래프 스크린샷 캡처 (HISTORY 첨부용).

**Expected**: 미태깅 자원 0건, 비용 분포 서비스/환경별 가시화.

---

## 12-B. 리소스 적정화 (2시간)

### P95 사용량 측정

```promql
# Prometheus — P95 메모리 (최근 7일, MB)
quantile_over_time(0.95, container_memory_working_set_bytes{namespace="prod", container!="POD"}[7d]) / 1024 / 1024

# P95 CPU (최근 7일, millicores)
quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{namespace="prod", container!="POD"}[5m])[7d:]) * 1000
```

```bash
kubectl top pods -n prod --sort-by=memory
kubectl top pods -n prod --sort-by=cpu
```

### requests/limits 조정 기준

| 항목 | 산출 | 예시 |
|---|---|---|
| requests.cpu | P95 CPU | 100m |
| requests.memory | P95 메모리 | 128Mi |
| limits.cpu | P95 CPU × 2 | 200m |
| limits.memory | P95 메모리 × 1.3 | 256Mi |

각 앱 prod overlay에 리소스 패치:
```yaml
# apps/<app>/overlays/prod/resource-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: <app>
spec:
  template:
    spec:
      containers:
        - name: <app>
          resources:
            requests: { cpu: "100m", memory: "128Mi" }
            limits: { cpu: "200m", memory: "256Mi" }
```

### HPA 정의 (platform-svc, engagement-svc)

```yaml
# apps/platform-svc/overlays/prod/hpa.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: platform-svc
  namespace: prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: platform-svc
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 70 }
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies: [{ type: Percent, value: 25, periodSeconds: 60 }]
    scaleUp:
      stabilizationWindowSeconds: 60
      policies: [{ type: Percent, value: 50, periodSeconds: 60 }]
```

engagement-svc도 동일 구조 (maxReplicas: 6).

### PDB 정의 (5개 앱 공통)

```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  cat > "apps/${app}/overlays/prod/pdb.yaml" << EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${app}
  namespace: prod
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: ${app}
EOF
done
```

kustomization.yaml에 리소스 추가:
```yaml
resources:
  - ../../base
  - hpa.yaml   # platform-svc, engagement-svc만
  - pdb.yaml
patches:
  - path: resource-patch.yaml
```

### 검증
```bash
kubectl get hpa -n prod   # TARGETS에 실제 수치 표시 (not <unknown>)
kubectl get pdb -n prod   # 5개 앱 ALLOWED DISRUPTIONS >= 0
```

---

## 12-C. 안정화 + 회귀 검증 (2시간)

### 잔여 이슈 점검
```bash
gh issue list --label "priority:P0" --state open
gh issue list --label "priority:P1" --state open
# → open 이슈 처리 후 close
```

### 전체 환경 헬스체크
```bash
argocd app list   # 15개 Synced + Healthy
for env in dev staging prod; do
  echo "=== ${env} ===" && kubectl get pods -n ${env}
done   # 모든 pod Running+Ready
```

### CI/CD 회귀 점검
```bash
gh run list --limit 10 --json name,conclusion \
  --jq '.[] | "\(.name) | \(.conclusion)"'
# 실행 시간이 이전 대비 증가하지 않았는지 확인
```

### 알람 false-positive 점검
```bash
kubectl exec -n monitoring deploy/alertmanager -- amtool alert query
```
false-positive 다수 시 임계치 조정: CPU 80%→90%, 메모리 85%→90%, Pod 재시작 3회→5회/5분.

### 미사용 리소스 정리
```bash
# unattached EBS
aws ec2 describe-volumes --filters Name=status,Values=available \
  --query 'Volumes[].{ID:VolumeId,Size:Size}' --output table

# Completed/Failed pod
kubectl get pods --all-namespaces --field-selector=status.phase=Succeeded
kubectl delete pods --all-namespaces --field-selector=status.phase=Succeeded
kubectl delete pods --all-namespaces --field-selector=status.phase=Failed
```

---

## 12-D. 핸드오프 + 종료 (2시간)

### 문서 최종 검토

| 문서 | 경로 | 점검 |
|---|---|---|
| KICKOFF | `docs/project-management/KICKOFF.md` | 배경+목표 정확 |
| TASK | `docs/project-management/TASK.md` | 전체 태스크 완료 반영 |
| SCOPE | `docs/project-management/SCOPE.md` | 최종 스코프 변경 반영 |
| HISTORY | `docs/project-management/history/HISTORY_gitops.md` | W5까지 기록 완료 |
| README | `README.md` | 개요+사용법 최신화 |

### HISTORY W5 회고 추가

HISTORY_gitops.md에 W5 섹션 추가: 실행 결과, 잘된 점, 아쉬운 점, 다음 사이클 권고 (실행 후 기록).

### 트랜지션 미팅 (30분)

어젠다: 아키텍처 개요(5분) → 배포 흐름(5분) → 운영 포인트(5분) → 장애 대응(5분) → 비용 관리(5분) → Q&A(5분)

미팅 후:
- [ ] 운영 인수자 ArgoCD 계정 + RBAC 역할 부여
- [ ] AWS IAM 권한 확인
- [ ] Slack #synapse-oncall 참여
- [ ] GitHub 레포 Collaborator 추가

### team-lead 사인오프
- [ ] 15개 Application 정상 동작
- [ ] 장애 Runbook 검토 완료
- [ ] On-call 체계 승인
- [ ] 비용 현황 예산 범위 내
- [ ] 핸드오프 문서 충분성
- [ ] 프로젝트 종료 승인

---

## 자주 막히는 지점

### HPA 미동작 (metrics-server 미설치)

`kubectl top pods` 시 `Metrics API not available` 또는 HPA TARGETS `<unknown>`:
```bash
kubectl get deploy metrics-server -n kube-system   # 미설치 확인
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch deploy metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

### Cost Explorer 태그 반영 24시간 지연

태그 추가 후 Cost Explorer 필터에 바로 반영되지 않음 → 최대 24시간 대기. Cost Allocation Tags에서 해당 태그 "Active" 상태 확인.

### PDB로 인한 노드 드레인 블로킹

`Cannot evict pod as it would violate the pod's disruption budget` → replica를 minAvailable+1 이상으로 설정 (prod replica >= 3). 긴급 시 PDB 임시 삭제 → 드레인 → PDB 재적용.

### 핸드오프 문서 누락

```bash
for doc in docs/project-management/KICKOFF.md docs/project-management/TASK.md \
  docs/project-management/SCOPE.md README.md; do
  [ -f "$doc" ] && echo "[OK] $doc" || echo "[MISSING] $doc"
done
```

---

## 다음 단계

Step 12 완료 = W5 완료 = **프로젝트 종료**.

운영 인수자 정기 작업:

| 주기 | 작업 |
|---|---|
| 매일 | ArgoCD 상태 확인, Alertmanager 알람 점검 |
| 매주 | Grafana 메트릭 리뷰 (CPU/메모리 추이) |
| 매월 | Cost Explorer 비용 리뷰, Velero 백업 복원 테스트 |
| 분기 | TLS 인증서 만료 점검, EKS/ArgoCD 버전 업그레이드 검토 |
