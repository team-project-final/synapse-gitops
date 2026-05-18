# Runbook: Prod 환경 + 승인 게이트 구성 (Step 9 상세)

> **소요 시간**: 약 2일 (2026-06-01 ~ 06-02)
> **결과**: 15 Application (5앱 x 3환경), prod는 Manual Sync, 권한 분리 확인
> **상위 문서**: [w4-prod-rollback-runbook.md](./w4-prod-rollback-runbook.md) Step 9
> **사전 조건**: W3 완료 (staging overlay 10 Application + Observability 스택 동작)

---

## 9-A. 사전 분석 (30분)

### prod 클러스터/네임스페이스 분리 전략

| 옵션 | 장점 | 단점 | 판정 |
|---|---|---|---|
| **별도 namespace** (`prod`) | 비용 절감, 관리 단순 | 노드 자원 공유 | **추천 (학습 환경)** |
| 별도 클러스터 | 완전 격리 | 비용 2배, 운영 복잡 | 후순위 |

### 승인 방식 비교

| 옵션 | 동작 | 판정 |
|---|---|---|
| **ArgoCD Manual Sync** | syncPolicy 제거 → UI/CLI 수동 sync | **추천** |
| GitHub Environment Approval | GitHub Actions reviewer 지정 | 대안 (이중 관리) |

### prod RBAC 설계

- `gitops-admin`: prod sync/override/get 전체 권한
- `gitops-developer`: prod get 읽기 전용
- `gitops-viewer`: prod get 읽기 전용

---

## 9-B. prod overlay 작성 (3시간)

### 환경별 설정 비교

| 항목 | dev | staging | **prod** |
|---|---|---|---|
| replicas | 1 | 2 | **3** |
| CPU request | 100m | 200m | **500m** |
| Memory request | 128Mi | 256Mi | **512Mi** |
| LOG_LEVEL | DEBUG | INFO | **WARN** |
| Ingress TLS | 없음 | self-signed | **CA 인증서** |

### 9-B-1. prod 네임스페이스 생성

```bash
kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f -
```

### 9-B-2. prod overlay 작성 (5앱)

```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  mkdir -p apps/$app/overlays/prod
done
```

**예시: `apps/platform-svc/overlays/prod/kustomization.yaml`**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources:
  - ../../base
patches:
  - target:
      kind: Deployment
      name: platform-svc
    patch: |
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: platform-svc
      spec:
        replicas: 3
        template:
          spec:
            containers:
              - name: platform-svc
                resources:
                  requests: { cpu: 500m, memory: 512Mi }
                  limits: { cpu: "1", memory: 1Gi }
                env:
                  - name: LOG_LEVEL
                    value: "WARN"
                  - name: NODE_ENV
                    value: "production"
```

> 나머지 4개 앱도 동일 패턴. 포트/앱 이름만 변경.

### 9-B-3. prod ExternalSecret

각 앱의 `apps/{app}/overlays/prod/externalsecret.yaml`:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: platform-svc-secrets
  namespace: prod
spec:
  refreshInterval: 1h
  secretStoreRef: { name: aws-secrets-manager, kind: ClusterSecretStore }
  target: { name: platform-svc-secrets }
  data:
    - secretKey: DB_PASSWORD
      remoteRef: { key: synapse/prod/platform-svc/db-password }
```

### 9-B-4. Kustomize 빌드 검증

```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $app ===" && kubectl kustomize apps/$app/overlays/prod | head -20
done
```

**Expected**: `namespace: prod`, `replicas: 3`, `cpu: 500m` 반영.

---

## 9-C. AppProject + RBAC (1시간)

### 9-C-1. AppProject 정의

```yaml
# argocd/projects/synapse-prod.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: synapse-prod
  namespace: argocd
spec:
  description: "Synapse Production - Manual Sync Only"
  sourceRepos: ["https://github.com/team-project-final/synapse-gitops.git"]
  destinations:
    - namespace: prod
      server: https://kubernetes.default.svc
  roles:
    - name: admin
      policies:
        - p, proj:synapse-prod:admin, applications, sync, synapse-prod/*, allow
        - p, proj:synapse-prod:admin, applications, override, synapse-prod/*, allow
        - p, proj:synapse-prod:admin, applications, get, synapse-prod/*, allow
      groups: [gitops-admin]
    - name: viewer
      policies:
        - p, proj:synapse-prod:viewer, applications, get, synapse-prod/*, allow
      groups: [gitops-developer, gitops-viewer]
```

```bash
kubectl apply -f argocd/projects/synapse-prod.yaml
```

### 9-C-2. RBAC ConfigMap 업데이트

`argocd-rbac-cm`의 `data.policy.csv`에 추가:

```csv
p, role:prod-admin, applications, sync, synapse-prod/*, allow
p, role:prod-admin, applications, override, synapse-prod/*, allow
g, gitops-admin, role:prod-admin
g, gitops-developer, role:prod-viewer
```

```bash
kubectl apply -f argocd/rbac/argocd-rbac-cm.yaml
```

---

## 9-D. ApplicationSet 확장 (30분)

기존 ApplicationSet env list에 `prod` 추가. prod만 syncPolicy를 제거(manual).

```bash
kubectl apply -f argocd/applicationsets/synapse-apps.yaml
sleep 30
argocd app list --output name | wc -l   # Expected: 15
argocd app get synapse-platform-svc-prod -o json | jq '.spec.syncPolicy'  # Expected: null
```

---

## 9-E. 권한 검증 (1시간)

### 9-E-1. 비권한 계정 prod sync 시도

```bash
argocd login <argocd-server> --username developer --password <dev-password>
argocd app sync synapse-platform-svc-prod
```

**Expected**: `permission denied: applications, sync, synapse-prod/synapse-platform-svc-prod`

### 9-E-2. 권한 계정 prod sync

```bash
argocd login <argocd-server> --username admin --password <admin-password>
argocd app sync synapse-platform-svc-prod
```

**Expected**: `Phase: Succeeded`, `Synced` + `Healthy`.

### 9-E-3. 전체 파이프라인 시뮬레이션

```bash
# 코드 변경 → PR → 머지
git checkout -b test/prod-pipeline-sim
echo "  TEST_KEY: sim-$(date +%s)" >> apps/platform-svc/base/configmap.yaml
git add . && git commit -m "test: prod pipeline simulation"
git push -u origin test/prod-pipeline-sim
gh pr create --title "test: prod pipeline sim" --body "W4 Step 9-E 검증용"
gh pr merge --merge --delete-branch

# dev/staging 자동 sync 확인 (2~3분 대기)
argocd app get synapse-platform-svc-dev | grep "Sync Status"      # Synced
argocd app get synapse-platform-svc-staging | grep "Sync Status"  # Synced
argocd app get synapse-platform-svc-prod | grep "Sync Status"     # OutOfSync

# prod 수동 sync
argocd app sync synapse-platform-svc-prod                         # Synced
```

---

## 9-F. 문서화 (30분)

- prod 배포 절차: PR → CI → main 머지 → dev/staging auto sync → staging 검증 → prod 수동 sync
- 권한 신청 절차: Slack #synapse-gitops 신청 → gitops-admin 승인 → RBAC 업데이트

---

## 자주 막히는 지점

### RBAC policy 오타
`argocd admin settings rbac validate`로 정책 검증. 수정 후 `kubectl rollout restart deployment argocd-server -n argocd`.

### AppProject destination 불일치
**증상**: `application destination is not permitted in project`. AppProject `destinations`에 올바른 namespace 추가.

### Manual Sync 후 OutOfSync 지속
`argocd app diff`로 diff 확인. `managedFields` 등 server-side 필드면 `ignoreDifferences` 설정.

### prod Ingress TLS 인증서 에러
`aws acm describe-certificate --certificate-arn <arn>`로 검증 상태 확인. DNS 검증 CNAME 미생성이 흔한 원인.

---

## 다음 단계

📖 **[step10-rollback-backup.md](./step10-rollback-backup.md)** — Velero 설치, 백업 스케줄, 복구 시뮬레이션, 모니터링 알람.
