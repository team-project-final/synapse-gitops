# Runbook: W2 EKS 전환 가이드 (Phase 2)

> **목적**: kind에서 검증 완료된 W2 매니페스트를 실제 EKS 환경에 적용
> **소요 시간**: 약 2일 (Day 4~5)
> **사전 조건**: Phase 1 (kind) 검증 완료 (PR #20), AWS 결제수단 verification 완료
> **결과**: 5개 앱이 EKS dev 환경에서 Synced + Healthy, ESO → AWS Secrets Manager, Image Updater → ECR

---

## 0. 사전 체크리스트

EKS 전환 전에 모두 확보:

- [ ] AWS 결제수단 verification 완료 (EKS 노드 launch 가능)
- [ ] aws CLI 설치 (`choco install awscli -y`)
- [ ] terraform 설치 (`choco install terraform -y`)
- [ ] AWS IAM 자격증명 설정 (`aws configure`)
- [ ] `aws sts get-caller-identity` → `synapse-admin` 확인
- [ ] PR #20 (`feat/w2-dev-deploy`) main 머지 완료
- [ ] kind 클러스터 정리 (비용 없지만 리소스 해제): `kind delete cluster --name synapse-w2`

도구 설치 검증:
```bash
aws --version        # aws-cli/2.x
terraform version    # Terraform v1.x
kubectl version --client
helm version --short
argocd version --client --short
```

---

## 1. AWS 인프라 프로비저닝 (Day 4 오전)

W1에서 작성한 Terraform 코드를 그대로 사용한다. PR #11/#12의 버그 수정이 이미 main에 반영되어 있다.

### 1-1. State Backend 생성 (신규 계정일 때만)

이전에 `terraform destroy`로 자원을 삭제했더라도 S3 state bucket과 DynamoDB lock table은 수동 생성이다.

```bash
# S3 bucket이 이미 있으면 skip
aws s3api head-bucket --bucket synapse-terraform-state 2>/dev/null \
  && echo "Bucket exists" \
  || aws s3api create-bucket --bucket synapse-terraform-state \
       --region ap-northeast-2 \
       --create-bucket-configuration LocationConstraint=ap-northeast-2

# DynamoDB table이 이미 있으면 skip
aws dynamodb describe-table --table-name synapse-terraform-locks --region ap-northeast-2 2>/dev/null \
  && echo "Table exists" \
  || aws dynamodb create-table --table-name synapse-terraform-locks \
       --attribute-definitions AttributeName=LockID,AttributeType=S \
       --key-schema AttributeName=LockID,KeyType=HASH \
       --billing-mode PAY_PER_REQUEST --region ap-northeast-2
```

### 1-2. terraform.tfvars 생성

```bash
cp infra/aws/dev/terraform.tfvars.example infra/aws/dev/terraform.tfvars
```

`terraform.tfvars`를 편집하여 실제 비밀번호를 입력한다. 상세 절차: [step2-terraform-tfvars.md](./step2-terraform-tfvars.md)

### 1-3. Terraform Apply

```bash
cd infra/aws/dev
terraform init
terraform plan    # 변경 내역 확인
terraform apply   # yes 입력
```

소요 시간: 약 25~45분. 상세 절차 + 트러블슈팅: [step3-terraform-apply.md](./step3-terraform-apply.md)

### 1-4. kubeconfig 설정

```bash
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl get nodes   # Ready 확인
```

---

## 2. ArgoCD 부트스트랩 (Day 4 오전)

```bash
# 레포 루트로 이동
cd /path/to/synapse-gitops

# ArgoCD 부트스트랩 (W1에서 작성한 스크립트)
bash scripts/bootstrap-argocd.sh
```

부트스트랩 검증:
```bash
kubectl get pods -n argocd         # 모든 pod Running
argocd app list                    # 5개 synapse-*-dev 표시
```

ArgoCD UI 접속: [argocd-ui-access.md](./argocd-ui-access.md) 참조

---

## 3. Provider 교체 — ESO (Day 4 오후)

### 3-1. AWS Secrets Manager에 시크릿 등록

```bash
AWS_REGION=ap-northeast-2

# platform-svc
aws secretsmanager create-secret --name synapse/dev/platform-svc/db-password \
  --secret-string "dev-platform-db-password-$(openssl rand -hex 8)" --region $AWS_REGION
aws secretsmanager create-secret --name synapse/dev/platform-svc/jwt-secret \
  --secret-string "dev-jwt-secret-$(openssl rand -hex 16)" --region $AWS_REGION

# engagement-svc
aws secretsmanager create-secret --name synapse/dev/engagement-svc/db-password \
  --secret-string "dev-engagement-db-password-$(openssl rand -hex 8)" --region $AWS_REGION

# knowledge-svc
aws secretsmanager create-secret --name synapse/dev/knowledge-svc/db-password \
  --secret-string "dev-knowledge-db-password-$(openssl rand -hex 8)" --region $AWS_REGION
aws secretsmanager create-secret --name synapse/dev/knowledge-svc/s3-access-key \
  --secret-string "dev-s3-access-key-$(openssl rand -hex 8)" --region $AWS_REGION

# learning-card
aws secretsmanager create-secret --name synapse/dev/learning-card/api-key \
  --secret-string "dev-learning-card-api-key-$(openssl rand -hex 8)" --region $AWS_REGION

# learning-ai
aws secretsmanager create-secret --name synapse/dev/learning-ai/openai-api-key \
  --secret-string "sk-dev-test-$(openssl rand -hex 16)" --region $AWS_REGION
aws secretsmanager create-secret --name synapse/dev/learning-ai/db-password \
  --secret-string "dev-learning-ai-db-password-$(openssl rand -hex 8)" --region $AWS_REGION
```

검증:
```bash
aws secretsmanager list-secrets --region ap-northeast-2 \
  --filter Key=name,Values=synapse/dev \
  --query 'SecretList[].Name' --output table
# Expected: 8개 시크릿
```

### 3-2. ESO 설치 + IRSA + ClusterSecretStore

상세 절차: [step5-eso-secrets.md](./step5-eso-secrets.md) 섹션 5-C

요약:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. IAM Policy 생성
# 2. IRSA Trust Policy + Role 생성
# 3. Helm으로 ESO 설치
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::${ACCOUNT_ID}:role/synapse-dev-eso-role" \
  --set installCRDs=true --wait

# 4. AWS ClusterSecretStore 생성
cat <<EOF | kubectl apply -f -
apiVersion: external-secrets.io/v1
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

### 3-3. dev overlay secretStoreRef 교체

5개 앱의 `apps/{app}/overlays/dev/kustomization.yaml`에서 ExternalSecret patch 값을 교체:

```yaml
# 변경 전 (kind)
        value: fake-secrets
# 변경 후 (EKS)
        value: aws-secrets-manager
```

```bash
for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  sed -i 's/value: fake-secrets/value: aws-secrets-manager/g' \
    "apps/$app/overlays/dev/kustomization.yaml"
done
```

### 3-4. ESO 검증

```bash
kubectl get clustersecretstore aws-secrets-manager
# STATUS: Valid

kubectl get externalsecret -n synapse-dev
# 5개 모두 SecretSynced
```

---

## 4. Provider 교체 — Image Updater (Day 4 오후)

### 4-1. dev overlay 이미지 경로 교체

kind에서 `localhost:5001` → EKS에서 ECR로 교체:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

for app in platform-svc engagement-svc knowledge-svc learning-card learning-ai; do
  sed -i "s|newName: localhost:5001/synapse/$app|newName: ${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/synapse/$app|g" \
    "apps/$app/overlays/dev/kustomization.yaml"
  # 태그도 dev-latest로 복원
  sed -i 's|newTag: "1.0.0"|newTag: dev-latest|g' \
    "apps/$app/overlays/dev/kustomization.yaml"
done
```

### 4-2. ApplicationSet annotation 교체

`argocd/applicationset.yaml`에서 image-list annotation 교체:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

sed -i "s|localhost:5001/synapse|${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com/synapse|g" \
  argocd/applicationset.yaml
```

### 4-3. Image Updater Helm 재설치 (ECR 설정)

상세 절차: [step6-image-sync.md](./step6-image-sync.md) 섹션 6-B

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

helm upgrade argocd-image-updater argo/argocd-image-updater \
  --namespace argocd \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::${ACCOUNT_ID}:role/synapse-dev-image-updater-role" \
  --set config.registries[0].name=ecr \
  --set config.registries[0].api_url="https://${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com" \
  --set config.registries[0].prefix="${ACCOUNT_ID}.dkr.ecr.ap-northeast-2.amazonaws.com" \
  --set config.registries[0].default=true \
  --set config.argocd.plaintext=true \
  --set "extraArgs[0]=--interval=1m" \
  --set installCRDs=true \
  --wait
```

### 4-4. ImageUpdater CR 적용

```bash
kubectl apply -f argocd/image-updater.yaml
```

### 4-5. Deploy Key 설정 (git write-back용)

```bash
# SSH key 생성
ssh-keygen -t ed25519 -C "argocd-image-updater" -f /tmp/image-updater-key -N ""

# GitHub 레포 Settings → Deploy keys → Add
# Title: argocd-image-updater
# Key: /tmp/image-updater-key.pub 내용
# Allow write access: 체크

# K8s Secret 등록
kubectl create secret generic git-creds \
  -n argocd \
  --from-file=sshPrivateKey=/tmp/image-updater-key

# GitHub Rulesets에서 Deploy key bypass 추가
```

---

## 5. PRD W2 검수 (Day 5)

### 5-1. 전체 검증

```bash
# FR-GO-201: 5개 앱 Synced + Healthy
argocd app list

# FR-GO-202: 헬스체크 (도메인 미확보 시 port-forward)
for app in platform-svc engagement-svc knowledge-svc; do
  kubectl port-forward svc/$app -n synapse-dev 8080:80 &
  sleep 2
  curl -s http://localhost:8080/actuator/health/liveness
  kill %1 2>/dev/null
done

# FR-GO-203: 평문 시크릿 0건
gitleaks detect --source . --no-git --verbose 2>&1 | tail -5

# FR-GO-204: ExternalSecret sync
kubectl get externalsecret -n synapse-dev

# FR-GO-205: 이미지 자동 반영 (ECR에 새 태그 push 후 5분 대기)
# FR-GO-206: git log에 Image Updater 커밋 확인
```

### 5-2. 문서 업데이트

```bash
# HISTORY에 EKS 전환 결과 기록
# WORKFLOW_W2.md 체크박스 완료
# TASK_gitops.md Step 4/5/6 Status → Done
```

### 5-3. 커밋 + PR 업데이트

```bash
git add apps/ argocd/ docs/
git commit -m "feat: swap kind providers to AWS (ESO + ECR) for EKS"
git push origin feat/w2-dev-deploy
```

---

## 6. 비용 관리

EKS 자원이 떠있는 동안 시간당 ~$0.40 발생. 작업 완료 후:

```bash
# 작업 종료 시 즉시 destroy
cd infra/aws/dev
terraform destroy -auto-approve
```

다음 작업 재개 시 `terraform apply`로 재생성 가능 (state가 S3에 있으므로).

---

## 7. 트러블슈팅

### terraform apply 실패

W1에서 발견된 4건의 버그는 PR #11/#12로 이미 수정됨. 새로운 에러 발생 시:
- [step3-terraform-apply.md](./step3-terraform-apply.md) 트러블슈팅 섹션 참조
- HISTORY에 에러 내용 + 해결 방법 기록

### EKS 노드 launch 불가

AWS 결제수단 verification이 완료되지 않으면 Free Tier eligible 인스턴스만 허용.
- 확인: AWS 콘솔 → Billing → Payment methods → Verification status
- 24~72시간 소요. 완료 전까지 kind에서 계속 검증.

### ESO IRSA 권한 오류

```bash
# ServiceAccount annotation 확인
kubectl get sa -n external-secrets external-secrets -o yaml | grep eks.amazonaws.com

# IAM Role Trust Policy 확인
aws iam get-role --role-name synapse-dev-eso-role --query 'Role.AssumeRolePolicyDocument'
```

상세: [step5-eso-secrets.md](./step5-eso-secrets.md) 트러블슈팅 섹션

### Image Updater ECR 인증 실패

```bash
# IRSA annotation 확인
kubectl get sa -n argocd argocd-image-updater -o yaml | grep eks.amazonaws.com

# 로그 확인
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=20
```

상세: [step6-image-sync.md](./step6-image-sync.md) 트러블슈팅 섹션
