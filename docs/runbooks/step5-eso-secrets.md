# Runbook: ESO Secret 관리 (Step 5 상세)

> **소요 시간**: 약 1.5일
> **결과**: 5개 ExternalSecret 모두 SecretSynced=True, git에 평문 시크릿 0건
> **상위 문서**: [w2-dev-deploy-runbook.md](./w2-dev-deploy-runbook.md) Step 5
> **사전 조건**: [step4-dev-overlay.md](./step4-dev-overlay.md) 완료 (5개 앱 dev Synced + Healthy)

---

## 5-A. 사전 분석 (30분)

**왜 필요한가**: Kubernetes에서 시크릿을 관리하는 방법은 여러 가지다. 프로젝트에 맞는 도구를 선택해야 운영 복잡도와 보안 리스크를 최소화할 수 있다.

### 시크릿 관리 도구 비교

| 항목 | ESO (External Secrets Operator) | SOPS + age/KMS | Sealed Secrets |
|---|---|---|---|
| **동작 방식** | 외부 시크릿 저장소에서 자동 sync | git에 암호화된 시크릿 저장 | 클러스터 내 컨트롤러가 복호화 |
| **AWS 통합** | 네이티브 (Secrets Manager, SSM) | KMS 키로 암호화 | 없음 |
| **운영 복잡도** | 낮음 (설치 후 CRD만 관리) | 중간 (암호화/복호화 파이프라인) | 중간 (인증서 관리) |
| **시크릿 로테이션** | 자동 (sync 주기) | 수동 (재암호화 필요) | 수동 (재암호화 필요) |
| **git에 평문 노출** | 없음 (외부 저장소 참조만) | 없음 (암호문만) | 없음 (sealed만) |
| **멀티 클러스터** | 쉬움 (저장소 공유) | 가능 | 클러스터별 인증서 |

**추천: ESO** — AWS Secrets Manager와 네이티브 통합, IRSA로 IAM 권한 관리, CRD 기반으로 GitOps 패턴에 자연스러움.

### IRSA 권한 설계

```
EKS Pod (ServiceAccount: external-secrets)
  → IRSA (IAM Role: synapse-dev-eso-role)
    → IAM Policy: SecretsManagerReadWrite
      → Resource: arn:aws:secretsmanager:ap-northeast-2:<ACCOUNT>:secret:synapse/dev/*
```

### 시크릿 명명 규칙

AWS Secrets Manager 경로:

```
synapse/{env}/{app}/{key}
```

예시:

| Secrets Manager 경로 | K8s Secret 이름 | 용도 |
|---|---|---|
| `synapse/dev/platform-svc/db-password` | `platform-svc-secret` → `DATABASE_PASSWORD` | DB 접속 비밀번호 |
| `synapse/dev/platform-svc/jwt-secret` | `platform-svc-secret` → `JWT_SECRET` | JWT 서명 키 |
| `synapse/dev/engagement-svc/db-password` | `engagement-svc-secret` → `DATABASE_PASSWORD` | DB 접속 비밀번호 |
| `synapse/dev/knowledge-svc/db-password` | `knowledge-svc-secret` → `DATABASE_PASSWORD` | DB 접속 비밀번호 |
| `synapse/dev/knowledge-svc/s3-access-key` | `knowledge-svc-secret` → `S3_ACCESS_KEY` | S3 접근 키 |
| `synapse/dev/learning-card/api-key` | `learning-card-secret` → `API_KEY` | 백엔드 API 키 |
| `synapse/dev/learning-ai/openai-api-key` | `learning-ai-secret` → `OPENAI_API_KEY` | OpenAI API 키 |
| `synapse/dev/learning-ai/db-password` | `learning-ai-secret` → `DATABASE_PASSWORD` | DB 접속 비밀번호 |

---

## 5-B. AWS Secrets Manager에 시크릿 등록 (30분)

**왜 필요한가**: ESO가 sync할 원본 시크릿이 AWS에 존재해야 한다. dev 환경용이므로 테스트 값을 넣는다.

### bash

```bash
AWS_REGION=ap-northeast-2

# platform-svc
aws secretsmanager create-secret --name synapse/dev/platform-svc/db-password \
  --secret-string "dev-platform-db-password-$(openssl rand -hex 8)" \
  --region $AWS_REGION

aws secretsmanager create-secret --name synapse/dev/platform-svc/jwt-secret \
  --secret-string "dev-jwt-secret-$(openssl rand -hex 16)" \
  --region $AWS_REGION

# engagement-svc
aws secretsmanager create-secret --name synapse/dev/engagement-svc/db-password \
  --secret-string "dev-engagement-db-password-$(openssl rand -hex 8)" \
  --region $AWS_REGION

# knowledge-svc
aws secretsmanager create-secret --name synapse/dev/knowledge-svc/db-password \
  --secret-string "dev-knowledge-db-password-$(openssl rand -hex 8)" \
  --region $AWS_REGION

aws secretsmanager create-secret --name synapse/dev/knowledge-svc/s3-access-key \
  --secret-string "dev-s3-access-key-$(openssl rand -hex 8)" \
  --region $AWS_REGION

# learning-card
aws secretsmanager create-secret --name synapse/dev/learning-card/api-key \
  --secret-string "dev-learning-card-api-key-$(openssl rand -hex 8)" \
  --region $AWS_REGION

# learning-ai
aws secretsmanager create-secret --name synapse/dev/learning-ai/openai-api-key \
  --secret-string "sk-dev-test-$(openssl rand -hex 16)" \
  --region $AWS_REGION

aws secretsmanager create-secret --name synapse/dev/learning-ai/db-password \
  --secret-string "dev-learning-ai-db-password-$(openssl rand -hex 8)" \
  --region $AWS_REGION
```

### PowerShell

```powershell
$region = "ap-northeast-2"

# platform-svc
$pw = "dev-platform-db-password-" + (-join ((48..57) + (97..122) | Get-Random -Count 16 | ForEach-Object {[char]$_}))
aws secretsmanager create-secret --name synapse/dev/platform-svc/db-password --secret-string $pw --region $region

# 나머지 앱도 동일 패턴 반복...
```

### 검증

```bash
aws secretsmanager list-secrets --region ap-northeast-2 \
  --filter Key=name,Values=synapse/dev \
  --query 'SecretList[].Name' --output table
```

**Expected**: 8개 시크릿 모두 표시.

---

## 5-C. ESO 설치 (30분)

**왜 필요한가**: ESO는 Helm으로 설치하며, AWS Secrets Manager와 통신하기 위해 IRSA(IAM Roles for Service Accounts) 설정이 필요하다.

### 1. IAM Policy 생성

```bash
cat <<'EOF' > /tmp/eso-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
        "secretsmanager:ListSecrets"
      ],
      "Resource": "arn:aws:secretsmanager:ap-northeast-2:*:secret:synapse/*"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name SynapseESOSecretsReadPolicy \
  --policy-document file:///tmp/eso-policy.json
```

### 2. IRSA 설정

```bash
# OIDC provider 확인 (EKS 생성 시 이미 설정됨)
OIDC_URL=$(aws eks describe-cluster --name synapse-dev --region ap-northeast-2 \
  --query 'cluster.identity.oidc.issuer' --output text)
echo "OIDC: $OIDC_URL"

# IAM Role 생성 (Trust Policy에 OIDC 포함)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OIDC_ID=$(echo $OIDC_URL | cut -d'/' -f5)

cat <<EOF > /tmp/eso-trust-policy.json
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
          "oidc.eks.ap-northeast-2.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name synapse-dev-eso-role \
  --assume-role-policy-document file:///tmp/eso-trust-policy.json

aws iam attach-role-policy \
  --role-name synapse-dev-eso-role \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/SynapseESOSecretsReadPolicy"
```

### 3. Helm으로 ESO 설치

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::${ACCOUNT_ID}:role/synapse-dev-eso-role" \
  --set installCRDs=true \
  --wait
```

### 4. 설치 검증

```bash
kubectl get pods -n external-secrets
# Expected: external-secrets-* pod 3개 Running (controller, webhook, cert-controller)

kubectl get crd | grep externalsecrets
# Expected: externalsecrets.external-secrets.io, secretstores.external-secrets.io 등
```

### 5. ClusterSecretStore 생성

```bash
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-northeast-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
EOF
```

### ClusterSecretStore 검증

```bash
kubectl get clustersecretstore aws-secrets-manager
# Expected: STATUS=Valid, AGE=...
```

---

## 5-D. 테스트 ExternalSecret (20분)

**왜 필요한가**: 5개 앱에 한꺼번에 적용하기 전에, 단일 ExternalSecret으로 동작을 확인한다. 문제가 생기면 디버깅 범위가 좁다.

### 테스트 ExternalSecret 생성

```bash
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: test-external-secret
  namespace: dev
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: test-secret
    creationPolicy: Owner
  data:
    - secretKey: DB_PASSWORD
      remoteRef:
        key: synapse/dev/platform-svc/db-password
EOF
```

### 검증

```bash
# ExternalSecret 상태
kubectl get externalsecret -n dev test-external-secret
# Expected: STATUS=SecretSynced

# 생성된 K8s Secret 확인
kubectl get secret -n dev test-secret
kubectl get secret -n dev test-secret -o jsonpath='{.data.DB_PASSWORD}' | base64 -d
# Expected: synapse/dev/platform-svc/db-password의 값과 일치
```

### 테스트 리소스 정리

```bash
kubectl delete externalsecret -n dev test-external-secret
kubectl delete secret -n dev test-secret
```

---

## 5-E. 5개 앱 ExternalSecret 작성 (2시간)

**왜 필요한가**: 각 앱에 필요한 시크릿을 ExternalSecret CRD로 정의한다. 기존에 git에 존재하던 평문 Secret 매니페스트는 모두 제거한다.

### `apps/platform-svc/base/externalsecret.yaml`

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: platform-svc-external-secret
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  target:
    name: platform-svc-secret
    creationPolicy: Owner
  data:
    - secretKey: DATABASE_PASSWORD
      remoteRef:
        key: synapse/dev/platform-svc/db-password
    - secretKey: JWT_SECRET
      remoteRef:
        key: synapse/dev/platform-svc/jwt-secret
```

### 나머지 4개 앱 패턴

동일 구조. 각 앱의 `apps/{app}/base/externalsecret.yaml`:

**engagement-svc**:
```yaml
  data:
    - secretKey: DATABASE_PASSWORD
      remoteRef:
        key: synapse/dev/engagement-svc/db-password
```

**knowledge-svc**:
```yaml
  data:
    - secretKey: DATABASE_PASSWORD
      remoteRef:
        key: synapse/dev/knowledge-svc/db-password
    - secretKey: S3_ACCESS_KEY
      remoteRef:
        key: synapse/dev/knowledge-svc/s3-access-key
```

**learning-card**:
```yaml
  data:
    - secretKey: API_KEY
      remoteRef:
        key: synapse/dev/learning-card/api-key
```

**learning-ai**:
```yaml
  data:
    - secretKey: OPENAI_API_KEY
      remoteRef:
        key: synapse/dev/learning-ai/openai-api-key
    - secretKey: DATABASE_PASSWORD
      remoteRef:
        key: synapse/dev/learning-ai/db-password
```

### kustomization.yaml 업데이트

각 앱의 `base/kustomization.yaml`에 externalsecret.yaml 추가:

```yaml
resources:
  - deployment.yaml
  - service.yaml
  - configmap.yaml
  - externalsecret.yaml    # 추가
```

### 기존 평문 Secret 제거

```bash
# git에 평문 Secret 파일이 있다면 삭제
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  if [ -f "apps/$app/base/secret.yaml" ]; then
    rm "apps/$app/base/secret.yaml"
    echo "Removed: apps/$app/base/secret.yaml"
  fi
done
```

### Git push

```bash
git checkout -b feat/w2-eso-secrets
git add apps/
git commit -m "feat(apps): add ExternalSecret CRDs, remove plaintext secrets"
git push -u origin feat/w2-eso-secrets
gh pr create --title "feat(apps): W2 Step 5 - ESO secret management" \
  --body "FR-GO-203, FR-GO-204: ESO 도입 + 평문 시크릿 제거"
gh pr merge --merge --delete-branch
```

---

## 5-F. 보안 검증 (30분)

**왜 필요한가**: ESO 도입의 핵심 목표는 git에서 평문 시크릿을 완전히 제거하는 것이다. git history까지 포함해 검증해야 한다.

### 1. ExternalSecret sync 상태 확인

```bash
kubectl get externalsecret -n dev
# Expected:
# NAME                              STORE                 REFRESH   STATUS
# platform-svc-external-secret      aws-secrets-manager   5m        SecretSynced
# engagement-svc-external-secret    aws-secrets-manager   5m        SecretSynced
# knowledge-svc-external-secret     aws-secrets-manager   5m        SecretSynced
# learning-card-external-secret     aws-secrets-manager   5m        SecretSynced
# learning-ai-external-secret       aws-secrets-manager   5m        SecretSynced
```

### 2. K8s Secret 생성 확인

```bash
kubectl get secret -n dev
# Expected: 5개 앱별 secret (platform-svc-secret, engagement-svc-secret, ...)

# 값이 실제로 채워졌는지 확인
kubectl get secret -n dev platform-svc-secret -o jsonpath='{.data}' | jq
```

### 3. gitleaks로 git history 스캔

```bash
# 전체 history 스캔
gitleaks detect --source . --verbose --report-path /tmp/gitleaks-report.json

# Expected: 0 findings
echo "Findings: $(cat /tmp/gitleaks-report.json | jq length)"
```

### 4. trufflehog 대안 (gitleaks 미설치 시)

```bash
docker run --rm -v "$(pwd):/repo" trufflesecurity/trufflehog git file:///repo --only-verified
```

### 5. ESO sync 실패 알람 설정 (선택)

```bash
# Prometheus 기반 알람 (monitoring 스택이 있는 경우)
cat <<EOF | kubectl apply -f -
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: eso-sync-alerts
  namespace: external-secrets
spec:
  groups:
    - name: eso
      rules:
        - alert: ExternalSecretSyncFailed
          expr: externalsecret_status_condition{condition="Ready",status="False"} == 1
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "ExternalSecret sync 실패: {{ \$labels.name }}"
EOF
```

---

## 검증 요약

| 검증 항목 | 명령 | 기대 결과 |
|---|---|---|
| ExternalSecret 상태 | `kubectl get externalsecret -n dev` | 5개 SecretSynced |
| K8s Secret 생성 | `kubectl get secret -n dev` | 5개 앱별 secret 존재 |
| Pod 정상 동작 | `kubectl get pods -n dev` | 5개 Running (시크릿 주입 후) |
| 평문 시크릿 스캔 | `gitleaks detect --source .` | 0 findings |
| ClusterSecretStore | `kubectl get clustersecretstore` | Valid |

---

## 자주 막히는 지점

### IRSA 권한 부족 (AccessDeniedException)

**에러**: ExternalSecret STATUS가 `SecretSyncedError`, 이벤트에 `AccessDeniedException`.

**원인**: ESO ServiceAccount의 IRSA Role에 Secrets Manager 접근 권한이 없거나, Trust Policy의 OIDC 조건이 틀림.

**해결**:
```bash
# 1. ServiceAccount annotation 확인
kubectl get sa -n external-secrets external-secrets -o yaml | grep eks.amazonaws.com

# 2. IAM Role Trust Policy 확인
aws iam get-role --role-name synapse-dev-eso-role --query 'Role.AssumeRolePolicyDocument'

# 3. IAM Policy 확인
aws iam list-attached-role-policies --role-name synapse-dev-eso-role

# 4. OIDC provider ID가 일치하는지 확인
aws eks describe-cluster --name synapse-dev --region ap-northeast-2 \
  --query 'cluster.identity.oidc.issuer' --output text
```

### SecretStore 연결 실패

**에러**: ClusterSecretStore STATUS가 `Invalid`.

**원인**: AWS 리전 설정 오류, 또는 ServiceAccount 참조가 잘못됨.

**해결**:
```bash
# 1. ClusterSecretStore 상세 확인
kubectl describe clustersecretstore aws-secrets-manager

# 2. ESO controller 로그
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets --tail=50

# 3. 리전 확인
kubectl get clustersecretstore aws-secrets-manager -o jsonpath='{.spec.provider.aws.region}'
```

### Sync 주기 지연

**증상**: 시크릿 값을 변경했는데 K8s Secret에 반영이 안 됨.

**원인**: refreshInterval 설정값만큼 대기. 기본 5분.

**해결**:
```bash
# 즉시 sync 강제
kubectl annotate externalsecret -n dev platform-svc-external-secret \
  force-sync=$(date +%s) --overwrite

# 또는 refreshInterval을 1m으로 줄이기 (dev 환경)
```

### Secrets Manager 리전 불일치

**에러**: `ResourceNotFoundException: Secrets Manager can't find the specified secret.`

**원인**: 시크릿은 `us-east-1`에 생성했는데 ClusterSecretStore는 `ap-northeast-2`를 바라봄.

**해결**:
```bash
# 시크릿이 어느 리전에 있는지 확인
aws secretsmanager list-secrets --region ap-northeast-2 --query 'SecretList[].Name'
aws secretsmanager list-secrets --region us-east-1 --query 'SecretList[].Name'

# 리전 통일: ClusterSecretStore의 region 수정 또는 시크릿 재생성
```

---

## 다음 단계

5개 ExternalSecret 모두 SecretSynced + gitleaks 0 findings 확인 후, [step6-image-sync.md](./step6-image-sync.md)로 진행하여 이미지 태그 자동 sync를 설정한다.
