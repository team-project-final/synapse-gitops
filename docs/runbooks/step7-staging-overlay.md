# Runbook: Staging Overlay + ApplicationSet 확장 (Step 7 상세)

> **소요 시간**: 약 7시간 (2일 배분)
> **결과**: 10 Application (5앱 x 2환경) 모두 Synced+Healthy, staging 도메인 헬스체크 통과
> **상위 문서**: [w3-staging-observability-runbook.md](./w3-staging-observability-runbook.md) Step 7
> **사전 조건**: W2 완료 — dev 5개 앱 Synced+Healthy, ESO 동작, 이미지 태그 자동 싱크 정상

---

## 7-A. 사전 분석 (30분)

staging 환경 확장 전에 아키텍처 결정 사항을 확인한다.

### 네임스페이스 분리 전략

```bash
# 현재 dev 네임스페이스 확인
kubectl get ns synapse-dev -o yaml
kubectl get all -n synapse-dev
```

```powershell
# PowerShell
kubectl get ns synapse-dev -o yaml
kubectl get all -n synapse-dev
```

- dev: `synapse-dev` 네임스페이스
- staging: `synapse-staging` 네임스페이스 (신규 생성)
- 네임스페이스 간 네트워크 격리: NetworkPolicy로 cross-ns 트래픽 차단 (향후)

### 승격 트리거 결정

- **자동 승격**: main 브랜치 merge -> ArgoCD auto-sync -> dev + staging 동시 반영
- dev와 staging이 같은 Git 브랜치(main)를 바라보되, overlay에서 환경별 설정을 분리
- 향후 prod는 수동 승격(manual sync)으로 전환 예정

### staging 도메인 패턴

| 앱 | staging 도메인 |
|-----|---------------|
| platform-svc | `staging-platform-svc.<domain>` |
| engagement-svc | `staging-engagement-svc.<domain>` |
| knowledge-svc | `staging-knowledge-svc.<domain>` |
| learning-card | `staging-learning-card.<domain>` |
| learning-ai | `staging-learning-ai.<domain>` |

### 리소스 산정

| 항목 | dev | staging |
|------|-----|---------|
| replicas | 1 | 2 |
| CPU request | 100m | 200m |
| CPU limit | 500m | 500m |
| Memory request | 128Mi | 256Mi |
| Memory limit | 512Mi | 512Mi |

**Expected**: 위 결정 사항이 팀 내 합의되었거나, 단독 진행 시 본 가이드 기준 그대로 사용.

---

## 7-B. Staging Overlay 작성 (3시간)

5개 앱 각각에 staging overlay를 생성한다. dev overlay를 기반으로 staging 고유 설정을 덮어쓴다.

### 네임스페이스 생성

```bash
# staging 네임스페이스 생성 (ArgoCD가 자동 생성하도록 설정할 수도 있음)
kubectl create namespace synapse-staging
kubectl label namespace synapse-staging environment=staging project=synapse
```

```powershell
kubectl create namespace synapse-staging
kubectl label namespace synapse-staging environment=staging project=synapse
```

### overlay 디렉토리 구조 (5개 앱 반복)

대상 앱 목록: `platform-svc`, `engagement-svc`, `knowledge-svc`, `learning-card`, `learning-ai`

각 앱의 staging overlay 디렉토리:
```
apps/{app}/overlays/staging/
├── kustomization.yaml
├── namespace.yaml        # (옵션: namespace transformer)
├── replicas-patch.yaml
├── resources-patch.yaml
├── ingress.yaml
└── external-secret.yaml
```

### kustomization.yaml 템플릿 (platform-svc 예시)

```bash
mkdir -p apps/platform-svc/overlays/staging
```

```yaml
# apps/platform-svc/overlays/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: synapse-staging

resources:
  - ../../base
  - external-secret.yaml
  - ingress.yaml

patches:
  - path: replicas-patch.yaml
  - path: resources-patch.yaml

commonLabels:
  environment: staging

images:
  - name: platform-svc
    newName: <ECR_REGISTRY>/platform-svc
    newTag: latest  # 이미지 태그 자동 싱크로 업데이트됨
```

### replicas-patch.yaml 템플릿

```yaml
# apps/platform-svc/overlays/staging/replicas-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: platform-svc
spec:
  replicas: 2
```

### resources-patch.yaml 템플릿

```yaml
# apps/platform-svc/overlays/staging/resources-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: platform-svc
spec:
  template:
    spec:
      containers:
        - name: platform-svc
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

### ExternalSecret 템플릿

```yaml
# apps/platform-svc/overlays/staging/external-secret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: platform-svc-secrets
  namespace: synapse-staging
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: platform-svc-secrets
    creationPolicy: Owner
  data:
    - secretKey: DATABASE_URL
      remoteRef:
        key: synapse/staging/platform-svc/database
        property: url
    - secretKey: REDIS_URL
      remoteRef:
        key: synapse/staging/platform-svc/redis
        property: url
```

### Ingress 템플릿

```yaml
# apps/platform-svc/overlays/staging/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-svc
  namespace: synapse-staging
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/certificate-arn: <ACM_CERT_ARN>
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
spec:
  rules:
    - host: staging-platform-svc.<domain>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: platform-svc
                port:
                  number: 8080
  tls:
    - hosts:
        - staging-platform-svc.<domain>
```

### 5개 앱 일괄 생성 스크립트

```bash
APPS="platform-svc engagement-svc knowledge-svc learning-card learning-ai"
for app in $APPS; do
  mkdir -p "apps/${app}/overlays/staging"
  # dev overlay를 복사 후 staging 값으로 수정
  cp "apps/${app}/overlays/dev/kustomization.yaml" "apps/${app}/overlays/staging/kustomization.yaml"
  echo "Created staging overlay for ${app}"
done
```

```powershell
$apps = @("platform-svc", "engagement-svc", "knowledge-svc", "learning-card", "learning-ai")
foreach ($app in $apps) {
    New-Item -ItemType Directory -Path "apps\$app\overlays\staging" -Force
    Copy-Item "apps\$app\overlays\dev\kustomization.yaml" "apps\$app\overlays\staging\kustomization.yaml"
    Write-Host "Created staging overlay for $app"
}
```

각 앱의 kustomization.yaml에서 다음을 수정:
1. `namespace: synapse-dev` -> `synapse-staging`
2. replicas: 1 -> 2
3. ExternalSecret의 remoteRef key: `synapse/dev/` -> `synapse/staging/`
4. Ingress host: `dev-` -> `staging-`

### kustomize 빌드 검증

```bash
for app in $APPS; do
  echo "=== ${app} ==="
  kustomize build "apps/${app}/overlays/staging" | head -20
  echo ""
done
```

**Expected**: 각 앱의 빌드 결과에서 `namespace: synapse-staging`, `replicas: 2` 확인.

### Secrets Manager에 staging 시크릿 등록

```bash
APPS="platform-svc engagement-svc knowledge-svc learning-card learning-ai"
for app in $APPS; do
  aws secretsmanager create-secret \
    --name "synapse/staging/${app}/database" \
    --secret-string '{"url":"postgresql://...staging-rds-endpoint..."}' \
    --region ap-northeast-2
  aws secretsmanager create-secret \
    --name "synapse/staging/${app}/redis" \
    --secret-string '{"url":"redis://...staging-redis-endpoint..."}' \
    --region ap-northeast-2
  echo "Created staging secrets for ${app}"
done
```

```powershell
$apps = @("platform-svc", "engagement-svc", "knowledge-svc", "learning-card", "learning-ai")
foreach ($app in $apps) {
    aws secretsmanager create-secret `
        --name "synapse/staging/$app/database" `
        --secret-string '{"url":"postgresql://...staging-rds-endpoint..."}' `
        --region ap-northeast-2
    aws secretsmanager create-secret `
        --name "synapse/staging/$app/redis" `
        --secret-string '{"url":"redis://...staging-redis-endpoint..."}' `
        --region ap-northeast-2
    Write-Host "Created staging secrets for $app"
}
```

---

## 7-C. ApplicationSet 확장 (1시간)

기존 ApplicationSet의 generator matrix에 staging 환경을 추가한다.

### 현재 ApplicationSet 확인

```bash
kubectl get applicationset synapse-apps -n argocd -o yaml
```

### ApplicationSet 수정

generator의 `elements` 배열에 staging을 추가:

```yaml
# applicationset.yaml (수정 부분)
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: synapse-apps
  namespace: argocd
spec:
  generators:
    - matrix:
        generators:
          - list:
              elements:
                - env: dev
                  namespace: synapse-dev
                - env: staging
                  namespace: synapse-staging
          - list:
              elements:
                - app: platform-svc
                - app: engagement-svc
                - app: knowledge-svc
                - app: learning-card
                - app: learning-ai
  template:
    metadata:
      name: "synapse-{{app}}-{{env}}"
    spec:
      project: synapse
      source:
        repoURL: https://github.com/team-project-final/synapse-gitops.git
        targetRevision: main
        path: "apps/{{app}}/overlays/{{env}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### 적용 + 검증

```bash
# ApplicationSet 적용
kubectl apply -f applicationset.yaml -n argocd

# 10개 Application 생성 확인 (최대 30초 대기)
sleep 10
argocd app list
```

```powershell
kubectl apply -f applicationset.yaml -n argocd
Start-Sleep -Seconds 10
argocd app list
```

**Expected**: 10개 Application 표시:
```
NAME                             SYNC STATUS   HEALTH STATUS
synapse-platform-svc-dev         Synced        Healthy
synapse-platform-svc-staging     Synced        Healthy
synapse-engagement-svc-dev       Synced        Healthy
synapse-engagement-svc-staging   Synced        Healthy
synapse-knowledge-svc-dev        Synced        Healthy
synapse-knowledge-svc-staging    Synced        Healthy
synapse-learning-card-dev        Synced        Healthy
synapse-learning-card-staging    Synced        Healthy
synapse-learning-ai-dev          Synced        Healthy
synapse-learning-ai-staging      Synced        Healthy
```

staging Application이 `OutOfSync` 또는 `Missing`이면:
1. `argocd app get synapse-platform-svc-staging` 으로 상세 확인
2. overlay path가 올바른지 점검 (`apps/platform-svc/overlays/staging` 존재 여부)
3. kustomization.yaml 문법 오류 → `kustomize build` 로컬 테스트

---

## 7-D. 승격 시뮬레이션 + 검증 (2시간)

dev에서 변경한 내용이 main merge 후 staging에도 자동 반영되는지 확인한다.

### 시뮬레이션 절차

```bash
# 1. 테스트 브랜치 생성
git checkout main && git pull
git checkout -b test/staging-promotion-check

# 2. dev overlay에 무해한 변경 (annotation 추가)
cat >> apps/platform-svc/overlays/dev/kustomization.yaml << 'EOF'

commonAnnotations:
  promotion-test: "w3-staging-check"
EOF

# 3. staging overlay에도 동일 변경 적용 확인
cat >> apps/platform-svc/overlays/staging/kustomization.yaml << 'EOF'

commonAnnotations:
  promotion-test: "w3-staging-check"
EOF

# 4. 커밋 + PR
git add apps/platform-svc/overlays/
git commit -m "test: staging promotion simulation"
git push -u origin test/staging-promotion-check
gh pr create --title "test: staging promotion simulation" \
  --body "W3 승격 절차 검증용. merge 후 dev+staging 모두 반영 확인."
```

### merge 후 검증

```bash
# PR merge
gh pr merge --merge --delete-branch

# ArgoCD sync 대기 (auto-sync 주기: 기본 3분)
sleep 180

# 검증
argocd app get synapse-platform-svc-dev -o json | jq '.status.sync.status'
argocd app get synapse-platform-svc-staging -o json | jq '.status.sync.status'
```

**Expected**: 두 환경 모두 `"Synced"`.

### staging 도메인 헬스체크

```bash
APPS="platform-svc engagement-svc knowledge-svc learning-card learning-ai"
for app in $APPS; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://staging-${app}.<domain>/health" || echo "FAIL")
  echo "${app}: ${STATUS}"
done
```

```powershell
$apps = @("platform-svc", "engagement-svc", "knowledge-svc", "learning-card", "learning-ai")
foreach ($app in $apps) {
    try {
        $response = Invoke-WebRequest -Uri "https://staging-$app.<domain>/health" -UseBasicParsing
        Write-Host "$app`: $($response.StatusCode)"
    } catch {
        Write-Host "$app`: FAIL - $($_.Exception.Message)"
    }
}
```

**Expected**: 5개 앱 모두 200 OK.

### annotation 정리

```bash
git checkout main && git pull
git checkout -b fix/remove-promotion-test-annotation
# 두 overlay에서 promotion-test annotation 제거
sed -i '/promotion-test/d' apps/platform-svc/overlays/dev/kustomization.yaml
sed -i '/commonAnnotations/d' apps/platform-svc/overlays/dev/kustomization.yaml
sed -i '/promotion-test/d' apps/platform-svc/overlays/staging/kustomization.yaml
sed -i '/commonAnnotations/d' apps/platform-svc/overlays/staging/kustomization.yaml
git add apps/platform-svc/overlays/
git commit -m "chore: remove promotion test annotations"
git push -u origin fix/remove-promotion-test-annotation
gh pr create --title "chore: remove promotion test annotations" --body "승격 시뮬레이션 정리"
gh pr merge --merge --delete-branch
```

---

## 7-E. 문서화 (30분)

### 승격 절차 README 작성

`docs/promotion-procedure.md`에 다음 내용 기록:

1. 승격 흐름: feature branch -> PR -> main merge -> ArgoCD auto-sync -> dev + staging 동시 반영
2. staging 전용 설정 변경: `apps/{app}/overlays/staging/` 수정 후 동일 흐름
3. 롤백: ArgoCD UI에서 이전 revision으로 수동 sync 또는 Git revert PR
4. prod 승격 (향후): manual sync policy, approval gate 추가 예정

### HISTORY 갱신

`docs/project-management/history/HISTORY_gitops.md`에 W3 Step 7 실행 결과 기록:
- 날짜, 산출물 (PR 번호), 10개 Application 목록, 스크린샷

---

## 검증

- [ ] `argocd app list` — 10개 Application 모두 표시
- [ ] 10개 모두 `Synced / Healthy`
- [ ] `kubectl get pods -n synapse-staging` — 5개 앱 pod 각 2개 Running
- [ ] `kubectl get externalsecret -n synapse-staging` — 5개 ExternalSecret `SecretSynced`
- [ ] staging 도메인 5개 헬스체크 200 OK
- [ ] 승격 시뮬레이션 완료 — dev+staging 동시 반영 확인

---

## 자주 막히는 지점

### 네임스페이스 생성 누락

**증상**: staging Application이 `Missing` 상태, pod이 생성 안 됨.

**원인**: `synapse-staging` 네임스페이스가 없고, ApplicationSet에 `CreateNamespace=true` syncOption이 빠짐.

**해결**:
```bash
# 수동 생성
kubectl create namespace synapse-staging

# 또는 ApplicationSet syncOptions에 추가
# syncOptions:
#   - CreateNamespace=true
```

### ApplicationSet generator 오류

**증상**: `argocd app list`에 staging Application이 안 나옴.

**원인**: generator matrix 문법 오류 (YAML 들여쓰기, elements 누락 등).

**해결**:
```bash
kubectl describe applicationset synapse-apps -n argocd
# Events 섹션에서 에러 메시지 확인
# generator 부분의 YAML 문법 점검 (yamllint 사용 권장)
```

### Ingress 충돌

**증상**: staging Ingress가 생성되었으나 도메인 접근 불가.

**원인**: dev와 staging이 같은 ALB를 공유하면서 host rule 충돌, 또는 ACM 인증서에 staging 도메인이 없음.

**해결**:
```bash
kubectl get ingress -n synapse-staging
kubectl describe ingress -n synapse-staging <ingress-name>
# ACM 인증서에 *.staging.<domain> 추가 또는 SAN 확장
```

### ExternalSecret staging 경로 미등록

**증상**: ExternalSecret 상태가 `SecretSyncedError`, pod이 `CreateContainerConfigError`.

**원인**: AWS Secrets Manager에 `synapse/staging/{app}/*` 경로의 시크릿이 없음.

**해결**:
```bash
# 시크릿 존재 여부 확인
aws secretsmanager list-secrets --filter Key=name,Values=synapse/staging --region ap-northeast-2

# 없으면 7-B의 Secrets Manager 등록 절차 실행
```

---

## 다음 단계

10개 Application 모두 Synced+Healthy 확인 후 상위 runbook의 [Step 8](./w3-staging-observability-runbook.md#step-8-observability-스택-구축-2일)으로 진행.
