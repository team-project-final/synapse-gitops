# SSM Bastion Host 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** EKS public endpoint를 비활성화하고 SSM Session Manager 전용 Bastion EC2를 배치하여 보안 강화된 EKS 접근 경로를 구성한다.

**Architecture:** Public subnet에 t3.micro Bastion을 배치하고, SSM Session Manager로 접근한다. EKS public endpoint를 끄고 private endpoint만 남긴다. Bastion에서 VPC 내부 통신으로 EKS API에 접근하며, User Data로 kubectl/helm을 자동 설치한다.

**Tech Stack:** Terraform (AWS provider ~> 5.40), Amazon Linux 2023, AWS Systems Manager, EKS 1.30

**Spec:** `docs/superpowers/specs/2026-05-20-ssm-bastion-design.md`

---

## 파일 구조

| 액션 | 파일 | 책임 |
|---|---|---|
| Create | `infra/aws/dev/bastion.tf` | Bastion EC2 + IAM Role + Instance Profile + Security Group |
| Modify | `infra/aws/dev/eks.tf` | public endpoint 비활성화 |
| Modify | `infra/aws/dev/outputs.tf` | bastion instance ID 출력 추가 |
| Create | `docs/runbooks/bastion-ssm-access.md` | SSM 접근 가이드 |

---

### Task 1: Bastion Terraform 리소스 작성 (`bastion.tf`)

**Files:**
- Create: `infra/aws/dev/bastion.tf`

- [ ] **Step 1: AMI data source + IAM Role 작성**

`infra/aws/dev/bastion.tf` 파일을 생성하고 AMI data source와 IAM Role을 작성한다:

```hcl
# ─── Bastion Host (SSM Session Manager) ─────────────────────────────────────

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── IAM Role ────────────────────────────────────────────────────────────────

resource "aws_iam_role" "bastion" {
  name = "${local.project}-${local.environment}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "${local.project}-${local.environment}-bastion-role" }
}

resource "aws_iam_role_policy" "bastion_eks" {
  name = "${local.project}-${local.environment}-bastion-eks"
  role = aws_iam_role.bastion.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = aws_eks_cluster.main.arn
      },
      {
        Effect   = "Allow"
        Action   = "sts:GetCallerIdentity"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.bastion.name
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${local.project}-${local.environment}-bastion-profile"
  role = aws_iam_role.bastion.name
}
```

- [ ] **Step 2: Security Group 작성**

같은 파일에 Security Group을 추가한다:

```hcl
# ─── Security Group ─────────────────────────────────────────────────────────

resource "aws_security_group" "bastion" {
  name_prefix = "${local.project}-${local.environment}-bastion-"
  vpc_id      = aws_vpc.main.id
  description = "Bastion host - SSM only, no SSH"

  egress {
    description = "HTTPS outbound (SSM + EKS API + package downloads)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.project}-${local.environment}-bastion-sg" }

  lifecycle { create_before_destroy = true }
}
```

Ingress 규칙은 없다. SSM은 EC2에서 아웃바운드 HTTPS로 SSM 서비스에 연결하므로 Ingress 불필요.

- [ ] **Step 3: EC2 Instance 작성**

같은 파일에 EC2 Instance를 추가한다:

```hcl
# ─── EC2 Instance ────────────────────────────────────────────────────────────

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl

    # helm
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # kubeconfig for ssm-user
    runuser -l ssm-user -c "aws eks update-kubeconfig --name ${local.cluster_name} --region ${var.aws_region}"
  EOF

  tags = { Name = "${local.project}-${local.environment}-bastion" }
}
```

`metadata_options`에서 `http_tokens = "required"`로 IMDSv2를 강제하여 보안을 강화한다.

- [ ] **Step 4: Commit**

```bash
git add infra/aws/dev/bastion.tf
git commit -m "feat(bastion): add SSM bastion EC2 with IAM role and security group"
```

---

### Task 2: EKS public endpoint 비활성화

**Files:**
- Modify: `infra/aws/dev/eks.tf:30-35`

- [ ] **Step 1: eks.tf에서 public endpoint 비활성화**

`infra/aws/dev/eks.tf`의 `vpc_config` 블록을 수정한다:

변경 전:
```hcl
  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
    security_group_ids      = [aws_security_group.eks_nodes.id]
  }
```

변경 후:
```hcl
  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [aws_security_group.eks_nodes.id]
  }
```

`endpoint_public_access`를 `false`로 변경하고, 불필요해진 `public_access_cidrs`를 제거한다.

- [ ] **Step 2: Commit**

```bash
git add infra/aws/dev/eks.tf
git commit -m "feat(eks): disable public endpoint — private-only access via bastion"
```

---

### Task 3: outputs.tf에 bastion instance ID 추가

**Files:**
- Modify: `infra/aws/dev/outputs.tf`

- [ ] **Step 1: outputs.tf 끝에 bastion 출력 추가**

파일 맨 끝에 추가:

```hcl

# ─── Bastion ────────────────────────────────────────────────────────────────

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID (for SSM session)"
  value       = aws_instance.bastion.id
}
```

- [ ] **Step 2: Commit**

```bash
git add infra/aws/dev/outputs.tf
git commit -m "feat(outputs): add bastion instance ID for SSM access"
```

---

### Task 4: terraform validate 검증

**Files:**
- 변경 없음 (검증만)

- [ ] **Step 1: terraform validate 실행**

```bash
cd infra/aws/dev
terraform init -backend=false
terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 2: terraform fmt 실행**

```bash
cd infra/aws/dev
terraform fmt -check -recursive
```

포맷 오류가 있으면 `terraform fmt`로 수정 후 커밋:

```bash
terraform fmt -recursive
git add infra/aws/dev/
git commit -m "style: terraform fmt"
```

---

### Task 5: SSM 접근 런북 작성

**Files:**
- Create: `docs/runbooks/bastion-ssm-access.md`

- [ ] **Step 1: 런북 작성**

`docs/runbooks/bastion-ssm-access.md`:

```markdown
# Bastion SSM 접근 가이드

## 사전 요구사항

1. **AWS CLI v2** 설치
2. **Session Manager Plugin** 설치:
   - Windows: `choco install session-manager-plugin`
   - macOS: `brew install --cask session-manager-plugin`
   - 확인: `session-manager-plugin --version`
3. **AWS 자격증명** 설정: `aws sts get-caller-identity` 정상 응답 확인

## 접속

### 1. Bastion Instance ID 확인

```bash
# terraform output으로 확인
cd infra/aws/dev
terraform output bastion_instance_id

# 또는 AWS CLI로 확인
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=synapse-dev-bastion" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" \
  --output text --region ap-northeast-2
```

### 2. SSM 세션 시작

```bash
aws ssm start-session --target <instance-id> --region ap-northeast-2
```

### 3. kubectl 사용

```bash
# kubeconfig는 User Data에서 자동 설정됨
kubectl get nodes
kubectl get pods -n synapse-dev
kubectl get configmap -n synapse-dev -o yaml | grep DATABASE_HOST
```

### 4. helm 확인

```bash
helm list -n argocd
helm list -n synapse-dev
```

## 트러블슈팅

### SSM 연결 실패

1. **Instance 상태 확인**: `aws ec2 describe-instance-status --instance-ids <id>`
   - running 상태인지 확인
2. **SSM Agent 상태 확인**: EC2 콘솔 → Fleet Manager → Managed Instances에서 bastion 확인
3. **IAM 권한 확인**: Instance Profile에 `AmazonSSMManagedInstanceCore` 정책 연결 확인
4. **네트워크 확인**: Public subnet에 Internet Gateway 연결 + Egress 443 허용 확인

### kubectl 인증 실패

1. **aws-auth ConfigMap 확인**:
   ```bash
   kubectl get configmap aws-auth -n kube-system -o yaml
   ```
2. Bastion IAM Role ARN이 `mapRoles`에 등록되어 있는지 확인
3. 없으면 등록:
   ```bash
   kubectl edit configmap aws-auth -n kube-system
   ```
   `mapRoles` 하위에 추가:
   ```yaml
   - rolearn: arn:aws:iam::963773969059:role/synapse-dev-bastion-role
     username: bastion
     groups:
       - system:masters
   ```

### User Data 실행 실패 (kubectl/helm 미설치)

SSM 접속 후 수동 설치:
```bash
# kubectl
curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# helm
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# kubeconfig
aws eks update-kubeconfig --name synapse-dev --region ap-northeast-2
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/runbooks/bastion-ssm-access.md
git commit -m "docs: add bastion SSM access runbook"
```

---

### Task 6: 핸드오프 문서 갱신

**Files:**
- Modify: `docs/superpowers/HANDOFF_W2.md`

- [ ] **Step 1: 핸드오프 문서에 bastion 정보 추가**

`HANDOFF_W2.md`의 **섹션 6 (발견 사항)** D-017 항목을 업데이트한다:

변경 전:
```
| D-017 | EKS private endpoint — 로컬 helm/kubectl 접근 불가 | VPN 또는 bastion 경유 필요 |
```

변경 후:
```
| D-017 | EKS private endpoint — 로컬 helm/kubectl 접근 불가 | ✅ SSM Bastion 구성 완료. `docs/runbooks/bastion-ssm-access.md` 참조 |
```

**섹션 4 (사전 조건 체크리스트)** 에 추가:

```
[ ] SSM Session Manager Plugin 설치 (로컬)
[ ] aws-auth ConfigMap에 bastion role 등록
```

**섹션 5 (핵심 파일 위치)** 가이드 문서에 추가:

```
| 4 | `docs/runbooks/bastion-ssm-access.md` | Bastion SSM 접근 절차 |
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/HANDOFF_W2.md
git commit -m "docs: update handoff — bastion SSM setup complete"
```
