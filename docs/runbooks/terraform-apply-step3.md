# Runbook: Terraform Apply 실행 + 트러블슈팅 (Step 3 상세)

> **소요 시간**: 25~45분 (실패 + 재시도 발생 시 더 김)
> **결과**: dev 환경의 AWS 인프라(VPC, EKS, RDS, Redis, MSK, OpenSearch, ArgoCD Helm) 생성 완료
> **상위 문서**: [w1-argocd-bootstrap-runbook.md](./w1-argocd-bootstrap-runbook.md) Step 3
> **사전 조건**: [aws-account-setup.md](./aws-account-setup.md) + [terraform-tfvars-setup.md](./terraform-tfvars-setup.md) 완료

⚠️ **이 단계부터 AWS 비용 발생**. 자원이 만들어진 시각을 기록하고, 학습 완료 후 즉시 destroy로 출혈 종료.

---

## 3-Pre. State Backend 자원 수동 생성 (5분)

`infra/aws/dev/main.tf`의 backend 설정이 S3 bucket + DynamoDB lock table을 요구한다. chicken-and-egg 문제이므로 수동으로 먼저 만든다.

### 1. S3 bucket 생성
```powershell
aws s3api create-bucket --bucket synapse-terraform-state --region ap-northeast-2 --create-bucket-configuration LocationConstraint=ap-northeast-2
```
- 정상: JSON에 `"Location": "http://synapse-terraform-state.s3..."`
- `BucketAlreadyOwnedByYou`: 이미 만들었음. OK
- `BucketAlreadyExists`: 글로벌 unique 이름 충돌. main.tf의 bucket 이름을 변경하는 PR 필요

### 2. Versioning + 암호화 + Public access 차단
```powershell
aws s3api put-bucket-versioning --bucket synapse-terraform-state --versioning-configuration Status=Enabled

$encryption = '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-bucket-encryption --bucket synapse-terraform-state --server-side-encryption-configuration $encryption

aws s3api put-public-access-block --bucket synapse-terraform-state --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 3. DynamoDB lock table
```powershell
aws dynamodb create-table --table-name synapse-terraform-locks --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region ap-northeast-2

aws dynamodb wait table-exists --table-name synapse-terraform-locks --region ap-northeast-2
```

---

## 3-A. terraform init (1~2분)

```powershell
cd infra\aws\dev
terraform init
```

**Expected** 마지막 라인: `Terraform has been successfully initialized!`

내부 동작: AWS / Kubernetes / Helm / TLS provider 다운로드 (`.terraform/` 약 300MB).

`Deprecated Parameter: dynamodb_table` 경고는 무시 가능 (동작에 영향 없음).

---

## 3-B. terraform plan (5~30초)

```powershell
terraform plan -out=tfplan
```

**Expected** 마지막 라인 (자원 약 40~60개):
```
Plan: 40 to add, 0 to change, 0 to destroy.
Saved the plan to: tfplan
```

핵심 체크: `to destroy: 0`. 0이 아니면 어떤 자원이 destroy되는지 출력 확인 후 진행 결정.

---

## 3-C. terraform apply (20~25분, ⚠️ 비용 발생 시작)

```powershell
$startTime = Get-Date
terraform apply tfplan
"Started at: $startTime"
```

### 진행 순서 (대략)
- 1~2분: VPC / Subnet / IGW / Route Table
- 2~5분: NAT Gateway × 2 (EIP 포함)
- 3~10분: IAM Role, Security Group
- **5~15분: EKS Cluster** (가장 오래)
- 5~10분: RDS, ElastiCache Redis (병렬)
- 5~10분: MSK Cluster
- 10~15분: OpenSearch Domain
- 마지막 2~3분: EKS Node Group → Helm release (ArgoCD)

### 완료 신호
```
Apply complete! Resources: 40 added, 0 changed, 0 destroyed.

Outputs:
argocd_namespace = "argocd"
```

```powershell
"Apply took: $((Get-Date) - $startTime)"
```

---

## 트러블슈팅 (2026-05-16 실제 발생한 모든 케이스 + 일반 케이스)

### ❌ terraform init: `S3 bucket "synapse-terraform-state" does not exist`

**원인**: 3-Pre 단계의 S3 bucket 생성을 빼먹음. Terraform이 backend로 사용할 bucket이 없음.

**해결**: 위 [3-Pre. State Backend 자원 수동 생성](#3-pre-state-backend-자원-수동-생성-5분) 1번 명령을 실행 후 `terraform init` 재실행.

### ❌ aws CLI: `AccessDenied — User is not authorized to perform: s3:CreateBucket`

**원인**: 1-C에서 만든 IAM 사용자(`synapse-admin`)에 `AdministratorAccess` 정책이 attach 안 됨. 1-B 단계의 콘솔 click에서 정책 선택을 빠뜨린 케이스.

**해결**: AWS 콘솔로 직접 부착 (CLI로는 권한이 없어 안 됨):
1. Root 계정으로 콘솔 로그인
2. IAM → Users → `synapse-admin`
3. Permissions 탭 → Add permissions → Attach policies directly
4. `AdministratorAccess` 정확히 체크 → Next → Add permissions

검증: `aws iam list-attached-user-policies --user-name synapse-admin` 으로 `AdministratorAccess` 표시.

### ❌ PowerShell: `--policy-arn: expected one argument`

PowerShell이 콜론 `::`을 잘못 파싱. 따옴표로 감싸기:
```powershell
aws iam attach-user-policy --user-name synapse-admin --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
```
(단 이 명령은 본인이 attach 권한 없으면 거부됨 — 위 케이스 참고)

### ❌ terraform plan: `Error acquiring the state lock` + `ResourceNotFoundException: Requested resource not found` (DynamoDB)

**원인**: 3-Pre의 DynamoDB lock table 생성(5번)을 빼먹음. terraform이 lock 잡으려는데 table이 없음.

**해결**: [3-Pre 3번](#3-dynamodb-lock-table) DynamoDB 명령 실행 + wait → `terraform plan` 재시도.

### ❌ DynamoDB create-table: `ResourceInUseException`

**원인**: 이전에 이미 만든 table을 다시 만들려고 함.

**해결**: 무시. `aws dynamodb describe-table --table-name synapse-terraform-locks --region ap-northeast-2 --query 'Table.TableStatus' --output text` 결과가 `ACTIVE`면 OK.

### ❌ S3 create-bucket: `BucketAlreadyOwnedByYou`

**원인**: 이전 실행에서 이미 만든 bucket. 무시 가능, 다음 명령으로 진행.

### ❌ Free Tier 제약 — EKS Node Group launch 실패

```
Error: ...AsgInstanceLaunchFailures: ... InvalidParameterCombination -
The specified instance type is not eligible for Free Tier.
```

**원인**: AWS 신규 가입 계정이 결제수단 verification을 완료할 때까지 Free-Tier-Eligible 인스턴스만 launch 허용. EKS Cluster 자체는 만들어지지만 노드 launch 실패.

**해결**:
1. AWS 콘솔 → 우상단 Account → **"Account"** → "Contact Information" / "Payment methods" 모두 채워졌는지 확인
2. 카드 등록 후 AWS가 소액 결제($1) → 환불 verification 진행 (24~72h 소요)
3. verification 완료 후 재시도
4. **즉시 우회 불가** — destroy 후 verification 대기 또는 다른 path (kind 로컬) 선택

### ❌ MSK SubscriptionRequiredException

```
Error: ...SubscriptionRequiredException: The AWS Access Key Id needs a subscription for the service
```

**원인**: 신규 계정에서 MSK 서비스가 활성화 안 됨.

**해결**: AWS 콘솔 → 상단 검색 "MSK" → "Amazon MSK" 클릭 (페이지 진입만 해도 활성화). 활성화 후 `terraform apply tfplan` 재실행.

### ❌ OpenSearch service-linked role 없음

```
Error: ...you must enable a service-linked role to give Amazon OpenSearch Service permissions to access your VPC.
```

**해결**:
```powershell
aws iam create-service-linked-role --aws-service-name opensearchservice.amazonaws.com
```
이미 있으면 `InvalidInput: Service role name ... has been taken` — 무시 (정상).

### ❌ EKS AMI 1.29 미지원

```
Error: creating EKS Node Group (...): InvalidParameterException: Requested AMI for this version 1.29 is not supported
```

**해결**: 본 레포 main에서는 이미 1.30으로 수정됨 (PR #11). 로컬 fork면 `infra/aws/dev/eks.tf`의 `version = "1.29"`를 `"1.30"`으로 변경 후 재실행.

### ❌ RDS parameter group "cannot use immediate apply method for static parameter"

**해결**: 본 레포 main에 이미 수정됨 (PR #11). 로컬 fork면 `infra/aws/dev/rds.tf`의 parameter 블록 두 곳에:
```hcl
parameter {
  name         = "shared_preload_libraries"
  value        = "pg_stat_statements"
  apply_method = "pending-reboot"   # 추가
}
```

### ❌ RDS postgres 16.3 미지원

**해결**: 본 레포 main에 이미 16.6으로 수정됨 (PR #12).

### ❌ OpenSearch IP-based policy + VPC endpoint 충돌

**해결**: 본 레포 main에서 access_policies의 Condition 블록 제거됨 (PR #12).

### ❌ EIP 한도 초과

```
Error: creating EC2 EIP: AddressLimitExceeded
```

**해결**: AWS 콘솔 → Service Quotas → EC2 → "EC2-VPC Elastic IPs" → 한도 증설 요청 (보통 즉시 승인). 또는 `vpc.tf`에서 NAT Gateway 1개로 줄임 (single-AZ).

### ❌ State lock 에러

```
Error: Error acquiring the state lock
```

**원인**: 이전 apply가 비정상 종료되어 lock이 남음.

**해결**:
```powershell
terraform force-unlock <LOCK_ID>   # LOCK_ID는 에러 메시지에 표시됨
```

### ❌ 일시적 throttle (특히 Redis `InvalidCredentialsException`)

대부분 일시적. `terraform plan -out=tfplan && terraform apply tfplan` 다시 실행.

---

## 3-D. 비용 모니터링 시작

apply 완료 직후, 별도 브라우저 탭에서:
- AWS 콘솔 → Billing → Cost Explorer (24h lag)
- 또는 Budgets 콘솔에서 `synapse-gitops-learning` 진행률

```powershell
# CLI로 오늘 비용 확인 (lag로 0일 수 있음)
aws ce get-cost-and-usage --time-period Start=$(Get-Date -Format 'yyyy-MM-dd'),End=$(Get-Date (Get-Date).AddDays(1) -Format 'yyyy-MM-dd') --granularity DAILY --metrics UnblendedCost
```

---

## 3-Cleanup. 학습 완료 후 즉시 destroy (필수)

```powershell
cd infra\aws\dev
$destroyStart = Get-Date
terraform destroy -auto-approve
"Destroy took: $((Get-Date) - $destroyStart)"
```

예상 시간: 10~45분 (EKS Cluster destroy가 가장 오래, MSK도 느림).

### Backend 자원 정리 (옵션, state 재사용 안 할 때)
```powershell
aws s3 rm s3://synapse-terraform-state --recursive
aws s3 rb s3://synapse-terraform-state
aws dynamodb delete-table --table-name synapse-terraform-locks --region ap-northeast-2
```

### orphan 자원 확인
destroy 후에도 콘솔에서 확인:
- EC2 → Elastic IPs (orphan EIP 있으면 수동 release, 안 하면 시간당 $0.005 청구)
- VPC → Network Interfaces (orphan ENI)
- CloudWatch Logs (소액이지만 누적)

---

## 다음 단계

apply 완료 + `argocd_namespace = "argocd"` 출력까지 통과하면 상위 runbook의 [Step 4](./w1-argocd-bootstrap-runbook.md#4-kubeconfig-갱신--노드-확인-1분)로 진행.

apply가 Free Tier 제약 등으로 막히면 destroy + 재시도(verification 후) 또는 kind 로컬 대체 path 검토.
