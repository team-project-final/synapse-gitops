# Runbook: Dev Overlay 5개 앱 완성 (Step 4 상세)

> **소요 시간**: 약 2일
> **결과**: 5개 앱이 dev 환경에서 ArgoCD Synced + Healthy 상태
> **상위 문서**: [w2-dev-deploy-runbook.md](./w2-dev-deploy-runbook.md) Step 4
> **사전 조건**: W1 완료 (ArgoCD 부트스트랩 + ApplicationSet 구성), EKS 클러스터 Running, ECR에 5개 앱 이미지 존재

---

## 4-A. 사전 분석 (30분)

**왜 필요한가**: 5개 앱의 리소스 요구사항, 환경변수, 포트, 헬스체크 endpoint를 미리 정리해야 base/overlay 매니페스트를 정확하게 작성할 수 있다. 이 단계를 건너뛰면 CrashLoopBackOff와 디버깅 시간이 늘어난다.

### 5개 앱 리소스 정리표

| 앱 | 컨테이너 포트 | 헬스체크 경로 | 주요 환경변수 | 언어/프레임워크 |
|---|---|---|---|---|
| platform-svc | 8080 | `/health` | `DATABASE_URL`, `REDIS_URL`, `JWT_SECRET` | Java/Spring |
| engagement-svc | 8080 | `/health` | `DATABASE_URL`, `KAFKA_BROKERS`, `REDIS_URL` | Java/Spring |
| knowledge-svc | 8080 | `/health` | `DATABASE_URL`, `OPENSEARCH_URL`, `S3_BUCKET` | Java/Spring |
| learning-card | 3000 | `/api/health` | `API_URL`, `NEXT_PUBLIC_API_URL` | Node.js/Next.js |
| learning-ai | 8000 | `/health` | `DATABASE_URL`, `OPENAI_API_KEY`, `MODEL_NAME` | Python/FastAPI |

### dev 환경 공통 설정

| 항목 | 값 | 이유 |
|---|---|---|
| replicas | 1 | dev는 단일 인스턴스로 충분 |
| CPU request | 100m | 최소 자원으로 비용 절감 |
| Memory request | 128Mi | 최소 자원으로 비용 절감 |
| CPU limit | 500m | burst 허용 |
| Memory limit | 512Mi | OOMKill 방지 |
| LOG_LEVEL | DEBUG | dev 환경 디버깅용 |

---

## 4-B. Base 매니페스트 작성 (3시간)

**왜 필요한가**: base는 환경에 무관한 공통 정의를 담는다. overlay에서 환경별(dev/staging/prod) 차이만 덮어쓰는 Kustomize 패턴의 핵심이다.

### 디렉토리 구조

```
apps/
├── platform-svc/
│   ├── base/
│   │   ├── kustomization.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── configmap.yaml
│   └── overlays/
│       └── dev/
│           └── kustomization.yaml
├── engagement-svc/
│   ├── base/
│   │   └── ...
│   └── overlays/
│       └── dev/
│           └── ...
├── knowledge-svc/
│   └── ...
├── learning-card/
│   └── ...
└── learning-ai/
    └── ...
```

### platform-svc 예시 (나머지 4개도 동일 패턴)

#### `apps/platform-svc/base/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: platform-svc
  labels:
    app: platform-svc
    part-of: synapse
spec:
  selector:
    matchLabels:
      app: platform-svc
  template:
    metadata:
      labels:
        app: platform-svc
    spec:
      containers:
        - name: platform-svc
          image: <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/platform-svc:latest
          ports:
            - containerPort: 8080
              protocol: TCP
          envFrom:
            - configMapRef:
                name: platform-svc-config
            - secretRef:
                name: platform-svc-secret
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 30
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 5
          resources: {}  # overlay에서 설정
```

#### `apps/platform-svc/base/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: platform-svc
  labels:
    app: platform-svc
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 8080
      protocol: TCP
  selector:
    app: platform-svc
```

#### `apps/platform-svc/base/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: platform-svc-config
data:
  LOG_LEVEL: "INFO"
  SERVER_PORT: "8080"
  SPRING_PROFILES_ACTIVE: "default"
```

#### `apps/platform-svc/base/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml

commonLabels:
  app.kubernetes.io/managed-by: kustomize
```

### 나머지 4개 앱 반복

위 platform-svc 패턴을 다음 4개 앱에 반복 적용한다. 변경 포인트:

| 앱 | `containerPort` | `image` 경로 | 헬스체크 경로 | ConfigMap 주요 값 |
|---|---|---|---|---|
| engagement-svc | 8080 | `.../synapse/engagement-svc:latest` | `/health` | `SPRING_PROFILES_ACTIVE` |
| knowledge-svc | 8080 | `.../synapse/knowledge-svc:latest` | `/health` | `SPRING_PROFILES_ACTIVE` |
| learning-card | 3000 | `.../synapse/learning-card:latest` | `/api/health` | `NEXT_PUBLIC_API_URL` |
| learning-ai | 8000 | `.../synapse/learning-ai:latest` | `/health` | `MODEL_NAME`, `PYTHONUNBUFFERED=1` |

### 작성 명령 (bash)

```bash
# 디렉토리 일괄 생성
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  mkdir -p apps/$app/base
  mkdir -p apps/$app/overlays/dev
done
```

### kustomize build 로컬 검증

각 앱의 base가 올바르게 빌드되는지 확인:

```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $app ==="
  kustomize build apps/$app/base
  echo ""
done
```

**Expected**: 각 앱에서 Deployment, Service, ConfigMap YAML이 병합되어 출력. 에러 없음.

---

## 4-C. Dev Overlay 작성 (2시간)

**왜 필요한가**: dev overlay는 개발 환경 전용 설정을 덮어쓴다. replica 수, 리소스 제한, 로그 레벨, Ingress 등 환경별 차이를 여기서 관리한다.

### `apps/platform-svc/overlays/dev/kustomization.yaml`

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: dev

resources:
  - ../../base
  - ingress.yaml

patches:
  - target:
      kind: Deployment
      name: platform-svc
    patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: platform-svc
      spec:
        replicas: 1
        template:
          spec:
            containers:
              - name: platform-svc
                resources:
                  requests:
                    cpu: 100m
                    memory: 128Mi
                  limits:
                    cpu: 500m
                    memory: 512Mi

  - target:
      kind: ConfigMap
      name: platform-svc-config
    patch: |-
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: platform-svc-config
      data:
        LOG_LEVEL: "DEBUG"
        SPRING_PROFILES_ACTIVE: "dev"
```

### `apps/platform-svc/overlays/dev/ingress.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-svc
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
    - host: dev-platform-svc.<도메인>
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: platform-svc
                port:
                  number: 80
```

### 나머지 4개 앱 반복

동일한 패턴으로 작성. Ingress의 `host`만 변경:

| 앱 | Ingress host |
|---|---|
| engagement-svc | `dev-engagement-svc.<도메인>` |
| knowledge-svc | `dev-knowledge-svc.<도메인>` |
| learning-card | `dev-learning-card.<도메인>` |
| learning-ai | `dev-learning-ai.<도메인>` |

### kustomize build 로컬 검증 (overlay)

```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $app dev overlay ==="
  kustomize build apps/$app/overlays/dev
  echo ""
done
```

**Expected**: 각 앱에서 namespace=dev, replicas=1, resources 설정, Ingress가 포함된 YAML 출력. 에러 없음.

---

## 4-D. ArgoCD Sync + 검증 (1시간)

**왜 필요한가**: git push 후 ArgoCD가 자동으로 변경을 감지하고 sync해야 한다. polling 주기(기본 3분)를 감안해 대기한 뒤 5앱 모두 정상 배포를 확인한다.

### 1. dev 네임스페이스 생성

ArgoCD가 자동 생성하지 않는 경우를 대비:

```bash
kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
```

### 2. Git push

```bash
git checkout -b feat/w2-dev-overlay
git add apps/
git commit -m "feat(apps): add base manifests and dev overlays for 5 apps"
git push -u origin feat/w2-dev-overlay
gh pr create --title "feat(apps): W2 Step 4 - dev overlay 5개 앱" \
  --body "FR-GO-201: 5개 앱 dev overlay 작성 + ArgoCD 자동 sync"
gh pr merge --merge --delete-branch
```

### 3. ArgoCD 자동 sync 대기

```bash
# polling 주기 3분 → 최대 5분 대기
echo "ArgoCD sync 대기 중... (최대 5분)"
sleep 300

# 상태 확인
argocd app list
```

### 4. 검증 명령

```bash
# 4-1. ArgoCD Application 상태
argocd app list
# Expected: 5개 모두 STATUS=Synced, HEALTH=Healthy

# 4-2. Pod 상태
kubectl get pods -n dev
# Expected: 5개 pod 모두 STATUS=Running, READY=1/1

# 4-3. 각 앱 상세 상태
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $app ==="
  argocd app get synapse-$app-dev --show-operation
done

# 4-4. Pod 로그 검사 (에러 없는지)
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== $app 로그 (최근 10줄) ==="
  kubectl logs -n dev -l app=$app --tail=10
done

# 4-5. 헬스체크 endpoint 확인 (클러스터 내부)
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -n dev -- \
  sh -c 'for svc in platform-svc engagement-svc knowledge-svc; do echo "=== $svc ==="; curl -s http://$svc/health; echo; done'

# 4-6. Ingress 확인
kubectl get ingress -n dev
```

### 5. 외부 접근 확인 (FR-GO-202)

```bash
# ALB DNS 확인
kubectl get ingress -n dev -o jsonpath='{.items[*].status.loadBalancer.ingress[0].hostname}'

# 헬스체크 (도메인 DNS 설정 후)
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' https://dev-$app.<도메인>/health)
  echo "$app: $HTTP_CODE"
done
# Expected: 모두 200
```

---

## 검증 요약

| 검증 항목 | 명령 | 기대 결과 |
|---|---|---|
| ArgoCD 상태 | `argocd app list` | 5개 Synced + Healthy |
| Pod 상태 | `kubectl get pods -n dev` | 5개 Running |
| 헬스체크 | `curl` 각 앱 `/health` | HTTP 200 |
| Ingress | `kubectl get ingress -n dev` | 5개 Ingress 생성 |
| kustomize 빌드 | `kustomize build apps/*/overlays/dev` | 에러 없음 |

---

## 자주 막히는 지점

### ImagePullBackOff

**에러**: Pod이 `ImagePullBackOff` 상태로 멈춤.

**원인**: ECR 인증 실패. EKS 노드가 ECR에 접근할 권한이 없거나, 이미지 경로가 틀림.

**해결**:
```bash
# 1. 이미지 경로 확인
kubectl describe pod -n dev <pod-name> | grep "Image:"

# 2. ECR에 이미지 존재 여부
aws ecr describe-images --repository-name synapse/platform-svc --region ap-northeast-2

# 3. ECR pull-through cache 또는 imagePullSecrets 설정
# EKS 노드 IAM Role에 AmazonEC2ContainerRegistryReadOnly 정책 추가
aws iam attach-role-policy \
  --role-name <eks-node-role-name> \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
```

### CrashLoopBackOff

**에러**: Pod이 시작 후 반복적으로 crash.

**원인**: 환경변수 누락, DB 연결 실패, 잘못된 설정값.

**해결**:
```bash
# 1. 로그 확인
kubectl logs -n dev <pod-name> --previous

# 2. 환경변수 확인
kubectl exec -n dev <pod-name> -- env | sort

# 3. ConfigMap/Secret 확인
kubectl get configmap -n dev platform-svc-config -o yaml
kubectl get secret -n dev platform-svc-secret -o yaml
```

### kustomize build 실패

**에러**: `Error: accumulating resources: ...`

**원인**: kustomization.yaml의 경로 오타, 파일 누락.

**해결**:
```bash
# 1. 파일 존재 확인
ls -la apps/platform-svc/base/

# 2. kustomization.yaml의 resources 경로와 실제 파일명 일치 확인
cat apps/platform-svc/base/kustomization.yaml
```

### Pending pods (리소스 부족)

**에러**: Pod이 `Pending` 상태에서 멈춤.

**원인**: 노드 자원(CPU/Memory) 부족으로 스케줄링 불가.

**해결**:
```bash
# 1. 노드 자원 현황
kubectl describe nodes | grep -A 5 "Allocated resources"

# 2. Pod 이벤트 확인
kubectl describe pod -n dev <pod-name> | grep -A 10 "Events"

# 3. 해결: 리소스 request 낮추기 또는 노드 추가
# overlays/dev/kustomization.yaml에서 requests를 더 낮추기:
# cpu: 50m, memory: 64Mi
```

### OutOfSync 무한 루프

**에러**: ArgoCD가 계속 OutOfSync를 표시하면서 sync를 반복.

**원인**: ArgoCD가 실제 클러스터 상태와 git 매니페스트의 diff를 감지하지만, 컨트롤러가 자동으로 추가하는 필드(metadata.annotations 등) 때문에 diff가 영원히 사라지지 않음.

**해결**:
```bash
# 1. diff 내용 확인
argocd app diff synapse-platform-svc-dev

# 2. 무시할 diff 설정 (Application에 ignoreDifferences 추가)
# argocd-appset.yaml의 Application template에:
#   spec:
#     ignoreDifferences:
#       - group: apps
#         kind: Deployment
#         jsonPointers:
#           - /spec/template/metadata/annotations
```

---

## 다음 단계

5개 앱 모두 Synced + Healthy 확인 후, [step5-eso-secrets.md](./step5-eso-secrets.md)로 진행하여 External Secrets Operator를 도입한다.
