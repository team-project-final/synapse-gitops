# Runbook: 이미지 태그 자동 Sync (Step 6 상세)

> **소요 시간**: 약 1.5일
> **결과**: 새 이미지 push 시 5분 이내 dev Pod 반영, git log에 태그 변경 이력 기록
> **상위 문서**: [w2-dev-deploy-runbook.md](./w2-dev-deploy-runbook.md) Step 6
> **사전 조건**: [step5-eso-secrets.md](./step5-eso-secrets.md) 완료 (ESO 정상 동작), 5개 앱 dev Synced + Healthy

---

## 6-A. 사전 분석 (30분)

**왜 필요한가**: 새 이미지가 ECR에 push될 때 dev 환경에 자동 반영하는 방법은 여러 가지다. 프로젝트 요구사항(5분 이내 반영 + git 이력)에 맞는 도구를 선택한다.

### 이미지 자동 업데이트 방식 비교

| 항목 | ArgoCD Image Updater | GitHub Actions PR 방식 |
|---|---|---|
| **동작 방식** | ArgoCD 내장, ECR polling → annotation/kustomize 업데이트 | CI가 새 이미지 감지 → PR 생성 → 머지 → ArgoCD sync |
| **반영 속도** | 2~5분 (polling interval) | 5~15분 (CI + PR 머지 시간) |
| **git 이력** | write-back: git 방식으로 자동 커밋 | PR 머지 커밋 |
| **운영 복잡도** | 낮음 (Helm 설치 + annotation) | 중간 (CI 파이프라인 작성) |
| **ArgoCD 통합** | 네이티브 | 간접 (git 변경 → ArgoCD sync) |
| **ECR 인증** | IRSA 또는 Secret | GitHub OIDC 또는 Access Key |
| **멀티 환경** | Application별 설정 | 환경별 workflow |

**추천: ArgoCD Image Updater** — ArgoCD 네이티브 통합, 설정이 간단하고 반영 속도가 빠르다. write-back: git 방식으로 태그 변경이 git commit으로 기록되어 FR-GO-206 충족.

### 태그 정책

| 정책 | 설명 | 예시 | 적합한 경우 |
|---|---|---|---|
| **semver** | 시맨틱 버전 기준 최신 | `1.2.3` → `1.2.4` | 릴리즈 관리가 체계적일 때 |
| **latest** | latest 태그 추적 | `latest` → 최신 digest | 빠른 개발, 태그 관리 불필요 |
| **digest** | SHA digest 기반 | `sha-abc1234` | CI에서 commit SHA 태그 사용 시 |
| **name** | 정규식 매칭 최신 | `dev-*` → 가장 최근 | 환경별 태그 prefix 사용 시 |

**dev 환경 추천**: `semver` (릴리즈 관리 시) 또는 `name` with `~dev-.*` (dev 전용 태그).

### write-back 방식

| 방식 | 설명 | git 이력 | 설정 |
|---|---|---|---|
| **git** | 태그 변경을 git commit으로 push | 남음 (FR-GO-206 충족) | SSH key 또는 GitHub App 필요 |
| **argocd** | ArgoCD Application의 parameter override | 안 남음 | 추가 설정 불필요 |

**추천: git** — FR-GO-206 요구사항(git log에 태그 변경 이력)을 충족하려면 git write-back 필수.

---

## 6-B. Image Updater 설치 (30분)

**왜 필요한가**: ArgoCD Image Updater는 별도 컴포넌트로, ArgoCD와 같은 네임스페이스에 설치한다.

### 1. ECR 인증용 IRSA 설정

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_URL=$(aws eks describe-cluster --name synapse-dev --region ap-northeast-2 \
  --query 'cluster.identity.oidc.issuer' --output text)
OIDC_ID=$(echo $OIDC_URL | cut -d'/' -f5)

# IAM Policy (ECR 읽기 전용)
cat <<'EOF' > /tmp/image-updater-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:DescribeImages",
        "ecr:ListImages",
        "ecr:BatchCheckLayerAvailability"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name SynapseImageUpdaterECRPolicy \
  --policy-document file:///tmp/image-updater-policy.json

# IAM Role + Trust Policy
cat <<EOF > /tmp/image-updater-trust.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.ap-northeast-2.amazonaws.com/id/${OIDC_ID}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "oidc.eks.ap-northeast-2.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:argocd:argocd-image-updater"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name synapse-dev-image-updater-role \
  --assume-role-policy-document file:///tmp/image-updater-trust.json

aws iam attach-role-policy \
  --role-name synapse-dev-image-updater-role \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/SynapseImageUpdaterECRPolicy"
```

### 2. Git write-back용 SSH key 또는 GitHub App 설정

```bash
# 옵션 A: Deploy Key (SSH)
ssh-keygen -t ed25519 -C "argocd-image-updater" -f /tmp/image-updater-key -N ""

# GitHub 레포 Settings → Deploy keys → Add deploy key
# Title: argocd-image-updater
# Key: /tmp/image-updater-key.pub 내용 붙여넣기
# Allow write access: 체크

# K8s Secret으로 등록
kubectl create secret generic git-creds \
  -n argocd \
  --from-file=sshPrivateKey=/tmp/image-updater-key

# 옵션 B: GitHub App (더 안전, 조직 레포에 적합)
# GitHub App 생성 → Installation ID, App ID, Private Key 발급
# kubectl create secret generic github-app-creds -n argocd \
#   --from-literal=github-app-id=<APP_ID> \
#   --from-literal=github-app-installation-id=<INSTALLATION_ID> \
#   --from-file=github-app-private-key=/tmp/github-app.pem
```

### 3. Helm 설치

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::${ACCOUNT_ID}:role/synapse-dev-image-updater-role" \
  --set config.registries[0].name=ecr \
  --set config.registries[0].api_url="https://${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com" \
  --set config.registries[0].prefix="${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com" \
  --set config.registries[0].default=true \
  --set config.registries[0].credentials=ext:/scripts/ecr-login.sh \
  --set config.argocd.plaintext=true \
  --wait
```

### 4. ECR 인증 스크립트 ConfigMap

```bash
cat <<'SCRIPT' > /tmp/ecr-login.sh
#!/bin/sh
aws ecr get-login-password --region ap-northeast-2
SCRIPT

kubectl create configmap ecr-login-script \
  -n argocd \
  --from-file=ecr-login.sh=/tmp/ecr-login.sh

# Pod에 마운트 (helm values로 하는 것이 이상적이지만, 수동 패치도 가능)
kubectl patch deployment argocd-image-updater -n argocd --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/volumes/-", "value": {"name": "ecr-login", "configMap": {"name": "ecr-login-script", "defaultMode": 493}}},
  {"op": "add", "path": "/spec/template/spec/containers/0/volumeMounts/-", "value": {"name": "ecr-login", "mountPath": "/scripts"}}
]'
```

### 5. 설치 검증

```bash
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-image-updater
# Expected: 1개 pod Running

kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=20
# Expected: "Starting image update cycle" 로그, 에러 없음
```

---

## 6-C. Application Annotation 추가 (1시간)

**왜 필요한가**: ArgoCD Image Updater는 Application의 annotation을 읽어 어떤 이미지를 어떤 전략으로 업데이트할지 결정한다. 5개 Application에 각각 annotation을 추가한다.

### annotation 설명

| Annotation | 설명 | 예시 |
|---|---|---|
| `argocd-image-updater.argoproj.io/image-list` | 추적할 이미지 별칭=레지스트리/이미지 | `app=<ACCOUNT>.dkr.ecr.../synapse/platform-svc` |
| `argocd-image-updater.argoproj.io/<별칭>.update-strategy` | 업데이트 전략 | `semver`, `latest`, `name`, `digest` |
| `argocd-image-updater.argoproj.io/<별칭>.allow-tags` | 허용 태그 패턴 (정규식) | `regexp:^[0-9]+\.[0-9]+\.[0-9]+$` |
| `argocd-image-updater.argoproj.io/write-back-method` | 태그 변경 반영 방식 | `git:secret:argocd/git-creds` |
| `argocd-image-updater.argoproj.io/write-back-target` | write-back 대상 | `kustomization` |
| `argocd-image-updater.argoproj.io/git-branch` | write-back 대상 브랜치 | `main` |

### ApplicationSet 수정

`argocd/applicationset.yaml`(또는 해당 파일)의 Application template에 annotation 추가:

```yaml
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
                - app: platform-svc
                  port: "8080"
                - app: engagement-svc
                  port: "8080"
                - app: knowledge-svc
                  port: "8080"
                - app: learning-card
                  port: "3000"
                - app: learning-ai
                  port: "8000"
          - list:
              elements:
                - env: dev
  template:
    metadata:
      name: "synapse-{{app}}-{{env}}"
      annotations:
        # Image Updater 설정
        argocd-image-updater.argoproj.io/image-list: "app=<ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/{{app}}"
        argocd-image-updater.argoproj.io/app.update-strategy: semver
        argocd-image-updater.argoproj.io/app.allow-tags: "regexp:^[0-9]+\\.[0-9]+\\.[0-9]+$"
        argocd-image-updater.argoproj.io/write-back-method: "git:secret:argocd/git-creds"
        argocd-image-updater.argoproj.io/write-back-target: kustomization
        argocd-image-updater.argoproj.io/git-branch: main
    spec:
      project: synapse
      source:
        repoURL: https://github.com/team-project-final/synapse-gitops.git
        targetRevision: main
        path: "apps/{{app}}/overlays/{{env}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{env}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

### 개별 Application에 수동 annotation (ApplicationSet 미사용 시)

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  kubectl annotate application synapse-$app-dev -n argocd \
    "argocd-image-updater.argoproj.io/image-list=app=${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/$app" \
    "argocd-image-updater.argoproj.io/app.update-strategy=semver" \
    "argocd-image-updater.argoproj.io/app.allow-tags=regexp:^[0-9]+\.[0-9]+\.[0-9]+$" \
    "argocd-image-updater.argoproj.io/write-back-method=git:secret:argocd/git-creds" \
    "argocd-image-updater.argoproj.io/write-back-target=kustomization" \
    "argocd-image-updater.argoproj.io/git-branch=main" \
    --overwrite
  echo "Annotated: synapse-$app-dev"
done
```

### Annotation 검증

```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  echo "=== synapse-$app-dev ==="
  kubectl get application synapse-$app-dev -n argocd \
    -o jsonpath='{.metadata.annotations}' | jq 'with_entries(select(.key | startswith("argocd-image-updater")))'
  echo ""
done
```

---

## 6-D. 자동 머지 정책 (30분)

**왜 필요한가**: write-back: git 방식에서 Image Updater가 `.argocd-source` 파일을 직접 커밋하므로, 별도의 PR 머지 과정이 필요 없다. 하지만 branch protection이 걸려 있으면 push가 실패할 수 있다.

### Git commit 직접 방식 (추천)

Image Updater가 `.argocd-source-<app-name>.yaml` 파일을 overlay 디렉토리에 직접 커밋한다:

```
apps/platform-svc/overlays/dev/.argocd-source-synapse-platform-svc-dev.yaml
```

이 파일에는 업데이트된 이미지 태그가 기록된다:

```yaml
kustomize:
  images:
    - name: <ACCOUNT>.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/platform-svc
      newTag: 1.2.4
```

### Branch protection 예외 설정

main 브랜치에 protection rule이 있다면, Image Updater의 push를 허용해야 한다:

**옵션 A: Deploy Key에 bypass 허용**
- GitHub 레포 Settings → Rules → Rulesets
- main 브랜치 ruleset에서 "Bypass actors" → Deploy key 추가

**옵션 B: GitHub App 사용**
- GitHub App에 "Contents: Write" 권한 부여
- Bypass actors에 GitHub App 추가

### 검증

```bash
# Image Updater 로그에서 write-back 성공 확인
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=30 | grep -i "write-back\|commit\|push"
```

---

## 6-E. 검증 (1시간)

**왜 필요한가**: 실제로 새 이미지를 ECR에 push하고, dev 환경에 5분 이내 반영되는지 확인한다. 또한 git log에 태그 변경 커밋이 남는지 검증한다.

### 1. 테스트 이미지 빌드 + Push

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=ap-northeast-2

# ECR 로그인
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

# 테스트 이미지 태그 (현재 버전 + 1)
# 현재 배포된 버전 확인
CURRENT_TAG=$(kubectl get deployment -n dev platform-svc -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
echo "현재 태그: $CURRENT_TAG"

# 새 태그로 빌드 + push (예: 1.0.0 → 1.0.1)
NEW_TAG="1.0.1"
docker tag synapse/platform-svc:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/synapse/platform-svc:${NEW_TAG}
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/synapse/platform-svc:${NEW_TAG}

echo "Push 완료: $(date)"
```

### 2. 반영 시간 측정

```bash
echo "Image push 시간: $(date)"
START=$(date +%s)

# 최대 10분 대기, 30초 간격 polling
for i in $(seq 1 20); do
  CURRENT=$(kubectl get deployment -n dev platform-svc \
    -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
  echo "[$(date +%H:%M:%S)] 현재 이미지 태그: $CURRENT"
  
  if [ "$CURRENT" = "$NEW_TAG" ]; then
    END=$(date +%s)
    ELAPSED=$((END - START))
    echo "반영 완료! 소요 시간: ${ELAPSED}초"
    break
  fi
  sleep 30
done

# 목표: 300초(5분) 이내
if [ $ELAPSED -gt 300 ]; then
  echo "WARNING: 5분 초과 (${ELAPSED}초). polling interval 조정 필요."
fi
```

### 3. Git log에 태그 변경 커밋 확인 (FR-GO-206)

```bash
git pull origin main

# Image Updater가 생성한 커밋 확인
git log --oneline -10
# Expected: "[argocd-image-updater] update image synapse/platform-svc" 형태의 커밋

# .argocd-source 파일 확인
cat apps/platform-svc/overlays/dev/.argocd-source-synapse-platform-svc-dev.yaml
# Expected: newTag: 1.0.1
```

### 4. 롤백 테스트

```bash
# 이전 태그로 롤백
argocd app set synapse-platform-svc-dev \
  --kustomize-image "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/synapse/platform-svc:${CURRENT_TAG}"

argocd app sync synapse-platform-svc-dev

# 롤백 확인
kubectl get deployment -n dev platform-svc \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: ...:이전태그
```

### 5. 5개 앱 전체 검증

```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  IMAGE=$(kubectl get deployment -n dev $app \
    -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
  echo "$app: $IMAGE"
done
```

---

## 검증 요약

| 검증 항목 | 명령 | 기대 결과 |
|---|---|---|
| Image Updater 동작 | `kubectl get pods -n argocd -l app...=argocd-image-updater` | Running |
| ECR polling | Image Updater 로그 | "update cycle" 정상 |
| 자동 반영 | 새 이미지 push → Pod 이미지 태그 변경 | 5분 이내 |
| git 이력 | `git log --oneline` | Image Updater 커밋 존재 |
| 롤백 | `argocd app set` + `sync` | 이전 태그로 복귀 |

---

## 자주 막히는 지점

### ECR 인증 실패

**에러**: Image Updater 로그에 `401 Unauthorized` 또는 `no basic auth credentials`.

**원인**: IRSA 설정 오류, ECR 인증 토큰 만료, 또는 ecr-login.sh 스크립트 미마운트.

**해결**:
```bash
# 1. IRSA annotation 확인
kubectl get sa -n argocd argocd-image-updater -o yaml | grep eks.amazonaws.com

# 2. ecr-login.sh 마운트 확인
kubectl exec -n argocd deploy/argocd-image-updater -- ls -la /scripts/

# 3. ECR 토큰 직접 테스트
kubectl exec -n argocd deploy/argocd-image-updater -- \
  aws ecr get-login-password --region ap-northeast-2

# 4. 대안: ECR credentials를 Secret으로 직접 주입
aws ecr get-login-password --region ap-northeast-2 | \
  kubectl create secret docker-registry ecr-cred -n argocd \
    --docker-server=${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com \
    --docker-username=AWS \
    --docker-password=$(aws ecr get-login-password --region ap-northeast-2) \
    --dry-run=client -o yaml | kubectl apply -f -
```

### Write-back 권한 부족

**에러**: Image Updater 로그에 `failed to push commit` 또는 `Permission denied (publickey)`.

**원인**: Deploy Key에 write 권한이 없거나, SSH key Secret이 잘못 설정됨.

**해결**:
```bash
# 1. git-creds Secret 확인
kubectl get secret -n argocd git-creds -o yaml

# 2. Deploy Key write 권한 확인
# GitHub 레포 Settings → Deploy keys → 해당 키의 "Allow write access" 체크

# 3. SSH key 테스트
kubectl exec -n argocd deploy/argocd-image-updater -- \
  ssh -T git@github.com -i /tmp/sshPrivateKey 2>&1 | head -5

# 4. branch protection bypass 확인
# GitHub Settings → Rules → Rulesets → bypass actors에 deploy key 추가
```

### 반영 지연 (Polling Interval)

**증상**: 이미지 push 후 5분이 넘어도 반영 안 됨.

**원인**: Image Updater의 기본 polling interval이 2분이지만, 네트워크 지연이나 큐 대기로 더 걸릴 수 있음.

**해결**:
```bash
# 1. polling interval 확인 및 조정
helm upgrade argocd-image-updater argo/argocd-image-updater \
  -n argocd \
  --set config.argocd.plaintext=true \
  --set config.registries[0].default=true \
  --set extraArgs[0]="--interval=1m" \
  --reuse-values

# 2. 수동 trigger
kubectl rollout restart deployment argocd-image-updater -n argocd

# 3. Image Updater 로그에서 polling 시점 확인
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=50 | grep -i "processing\|update"
```

### 잘못된 이미지 태그 패턴

**증상**: 새 태그를 push했는데 Image Updater가 감지하지 않음.

**원인**: `allow-tags` 정규식과 실제 태그 형식이 불일치.

**해결**:
```bash
# 1. ECR에 존재하는 태그 목록 확인
aws ecr describe-images --repository-name synapse/platform-svc --region ap-northeast-2 \
  --query 'imageDetails[].imageTags' --output table

# 2. allow-tags 정규식 확인
kubectl get application synapse-platform-svc-dev -n argocd \
  -o jsonpath='{.metadata.annotations.argocd-image-updater\.argoproj\.io/app\.allow-tags}'

# 3. 정규식 수정 (예: SHA 태그도 허용)
kubectl annotate application synapse-platform-svc-dev -n argocd \
  "argocd-image-updater.argoproj.io/app.allow-tags=regexp:^(v?[0-9]+\.[0-9]+\.[0-9]+|dev-.+)$" \
  --overwrite
```

---

## 다음 단계

5개 앱 모두 이미지 자동 업데이트 + git 이력 확인이 완료되면, W2 전체 검증 체크리스트를 [w2-dev-deploy-runbook.md](./w2-dev-deploy-runbook.md#검증-체크리스트-done-표시용)에서 최종 확인한다.

W2 완료 후 다음 단계:
- **W3**: staging 환경 구성 + promotion 전략
- **도메인 설정**: Route 53 + ACM 인증서로 `dev-<app>.<도메인>` HTTPS 접근
- **모니터링**: Prometheus + Grafana 스택 도입
