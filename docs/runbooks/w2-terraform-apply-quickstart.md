# Runbook: W2 Terraform Apply 빠른 시작 가이드

> **목적**: AWS 인프라 프로비저닝 (EKS + RDS + MSK + Redis + OpenSearch) 한 번에 실행
> **소요 시간**: 약 1시간 (설치 + apply + 검증)
> **사전 조건**: AWS 계정 + 결제수단 verification 완료
> **상세 참조**: [step1-aws-account-setup.md](./step1-aws-account-setup.md) / [step2-terraform-tfvars.md](./step2-terraform-tfvars.md) / [step3-terraform-apply.md](./step3-terraform-apply.md)

⚠️ **비용 주의**: 시간당 ~$0.40, 월 ~$300. 작업 완료 후 반드시 `terraform destroy`.

---

## 1. 도구 설치 확인

```bash
aws --version        # aws-cli/2.x 필요
terraform version    # Terraform v1.x 필요
kubectl version --client
```

미설치 시:
```powershell
choco install awscli terraform -y
```

---

## 2. AWS 자격증명 설정

```bash
aws configure
# AWS Access Key ID: <IAM synapse-admin 키>
# AWS Secret Access Key: <IAM synapse-admin 시크릿>
# Default region name: ap-northeast-2
# Default output format: json

# 검증
aws sts get-caller-identity
# Expected: "Arn": "...synapse-admin"
```

IAM 키가 없으면: [step1-aws-account-setup.md](./step1-aws-account-setup.md) 1-C 참조.

---

## 3. State Backend 생성 (최초 1회)

이전에 만든 적 있으면 skip.

```bash
# S3 bucket
aws s3api head-bucket --bucket synapse-terraform-state 2>/dev/null \
  && echo "Bucket exists — skip" \
  || aws s3api create-bucket --bucket synapse-terraform-state \
       --region ap-northeast-2 \
       --create-bucket-configuration LocationConstraint=ap-northeast-2

# S3 보안 설정
aws s3api put-bucket-versioning --bucket synapse-terraform-state \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket synapse-terraform-state \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# DynamoDB lock table
aws dynamodb describe-table --table-name synapse-terraform-locks --region ap-northeast-2 2>/dev/null \
  && echo "Table exists — skip" \
  || aws dynamodb create-table --table-name synapse-terraform-locks \
       --attribute-definitions AttributeName=LockID,AttributeType=S \
       --key-schema AttributeName=LockID,KeyType=HASH \
       --billing-mode PAY_PER_REQUEST --region ap-northeast-2
```

---

## 4. terraform.tfvars 생성

```bash
cd infra/aws/dev
cp terraform.tfvars.example terraform.tfvars
```

`terraform.tfvars`를 편집하여 실제 비밀번호 입력. 상세: [step2-terraform-tfvars.md](./step2-terraform-tfvars.md)

핵심 항목:
```hcl
rds_password       = "<강력한 비밀번호>"
redis_auth_token   = "<강력한 토큰>"
```

> 이 값들을 1Password 등에 백업할 것. `.gitignore`에 포함되어 git에 올라가지 않음.

---

## 5. Terraform Apply

```bash
cd infra/aws/dev

# 초기화
terraform init
# Expected: "Terraform has been successfully initialized!"

# 계획 확인
terraform plan
# Expected: ~20개 자원 생성 예정

# 적용 (yes 입력)
terraform apply
# 소요: 25~45분
```

### apply 중 발생할 수 있는 에러

| 에러 | 원인 | 해결 |
|---|---|---|
| `Error creating EKS Node Group` | 결제수단 verification 미완 | AWS 콘솔 → Billing → 확인 |
| `Error creating OpenSearch Domain` | service-linked role 없음 | `aws iam create-service-linked-role --aws-service-name opensearchservice.amazonaws.com` |
| `Error creating MSK Cluster` | MSK 활성화 안 됨 | AWS 콘솔에서 MSK 페이지 방문 1회 |

상세 트러블슈팅: [step3-terraform-apply.md](./step3-terraform-apply.md)

---

## 6. 인프라 Endpoint 수집

apply 완료 후 각 자원의 endpoint를 수집한다. 이 값들은 gitops ConfigMap dev overlay에 들어간다.

```bash
echo "=== EKS ==="
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
kubectl get nodes

echo ""
echo "=== RDS Endpoint ==="
aws rds describe-db-instances \
  --query 'DBInstances[?DBInstanceIdentifier==`synapse-dev`].Endpoint.Address' \
  --output text --region ap-northeast-2

echo ""
echo "=== ElastiCache Redis Endpoint ==="
aws elasticache describe-replication-groups \
  --query 'ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address' \
  --output text --region ap-northeast-2

echo ""
echo "=== MSK Kafka Brokers ==="
CLUSTER_ARN=$(aws kafka list-clusters-v2 --region ap-northeast-2 \
  --query 'ClusterInfoList[0].ClusterArn' --output text)
aws kafka get-bootstrap-brokers --cluster-arn "$CLUSTER_ARN" \
  --query 'BootstrapBrokerStringSaslIam' --output text --region ap-northeast-2

echo ""
echo "=== OpenSearch Endpoint ==="
aws opensearch describe-domain --domain-name synapse-dev \
  --query 'DomainStatus.Endpoint' --output text --region ap-northeast-2
```

수집한 값을 기록해 두세요:

```
DATABASE_HOST=<RDS endpoint>
REDIS_HOST=<ElastiCache endpoint>
KAFKA_BROKERS=<MSK brokers>
OPENSEARCH_URL=https://<OpenSearch endpoint>
```

---

## 7. ArgoCD 부트스트랩

```bash
cd /path/to/synapse-gitops
bash scripts/bootstrap-argocd.sh
```

검증:
```bash
kubectl get pods -n argocd
# 모든 pod Running

argocd app list
# 5개 synapse-*-dev 표시
```

ArgoCD UI 접속: [argocd-ui-access.md](./argocd-ui-access.md) 참조

---

## 8. 다음 단계

인프라 + ArgoCD 준비 완료 후:

1. **gitops ConfigMap에 endpoint 값 반영** — `apps/*/overlays/dev/kustomization.yaml`에 `DATABASE_HOST`, `KAFKA_BROKERS` 등 추가
2. **ESO AWS provider 교체** — [w2-eks-transition.md](./w2-eks-transition.md) 섹션 3
3. **Image Updater ECR 교체** — [w2-eks-transition.md](./w2-eks-transition.md) 섹션 4
4. **PRD W2 검수** — [w2-eks-transition.md](./w2-eks-transition.md) 섹션 5

---

## 9. 작업 종료 시 비용 차단

```bash
cd infra/aws/dev
terraform destroy -auto-approve
# 소요: ~30~40분
```

S3 state bucket과 DynamoDB lock table은 삭제하지 않는다 (다음 apply에 필요).
