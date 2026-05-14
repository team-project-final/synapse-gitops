# AWS 인프라 Terraform 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** synapse-gitops/infra/aws/dev/ 에 Terraform IaC 9개 파일을 작성하여 dev 환경 AWS 인프라를 코드화한다.

**Architecture:** VPC(2AZ, public+private) → EKS(3 node) → 데이터 서비스(RDS, MSK, Redis, OpenSearch) → ArgoCD(Helm) 순서로 의존성 체인을 구성. 모든 데이터 서비스는 private subnet에 배치하고 EKS 노드 SG에서만 접근 허용.

**Tech Stack:** Terraform 1.7+, AWS Provider 5.x, Helm Provider, Kubernetes Provider

---

## File Structure

| 파일 | 책임 |
|------|------|
| `infra/aws/dev/main.tf` | Terraform 설정, provider, backend, locals |
| `infra/aws/dev/variables.tf` | 모든 입력 변수 정의 |
| `infra/aws/dev/vpc.tf` | VPC, subnets, IGW, NAT, route tables, security groups |
| `infra/aws/dev/eks.tf` | EKS cluster, managed node group, OIDC, IAM roles |
| `infra/aws/dev/rds.tf` | PostgreSQL 16 instance, subnet group, parameter group |
| `infra/aws/dev/msk.tf` | MSK cluster, configuration, security group rule |
| `infra/aws/dev/redis.tf` | ElastiCache Redis, subnet group, auth |
| `infra/aws/dev/opensearch.tf` | OpenSearch domain, access policy |
| `infra/aws/dev/argocd.tf` | Helm release for ArgoCD |
| `infra/aws/dev/outputs.tf` | 모든 엔드포인트 출력 |

---

### Task 1: main.tf + variables.tf

**Files:**
- Create: `infra/aws/dev/main.tf`
- Create: `infra/aws/dev/variables.tf`

- [ ] **Step 1: main.tf 작성**

```hcl
# infra/aws/dev/main.tf

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }

  backend "s3" {
    bucket         = "synapse-terraform-state"
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "synapse-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "synapse"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_cert)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_cert)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
    }
  }
}

locals {
  project      = "synapse"
  environment  = var.environment
  cluster_name = "${local.project}-${local.environment}"
  azs          = ["${var.aws_region}a", "${var.aws_region}c"]
}
```

- [ ] **Step 2: variables.tf 작성**

```hcl
# infra/aws/dev/variables.tf

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "eks_node_instance_type" {
  description = "EKS node instance type"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_count" {
  description = "Number of EKS worker nodes"
  type        = number
  default     = 3
}

variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "rds_db_name" {
  description = "RDS database name"
  type        = string
  default     = "synapse"
}

variable "rds_username" {
  description = "RDS master username"
  type        = string
  default     = "synapse_admin"
  sensitive   = true
}

variable "rds_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "msk_instance_type" {
  description = "MSK broker instance type"
  type        = string
  default     = "kafka.t3.small"
}

variable "msk_broker_count" {
  description = "Number of MSK brokers"
  type        = number
  default     = 3
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_auth_token" {
  description = "Redis AUTH token"
  type        = string
  sensitive   = true
}

variable "opensearch_instance_type" {
  description = "OpenSearch instance type"
  type        = string
  default     = "t3.small.search"
}
```

- [ ] **Step 3: terraform.tfvars.example 작성**

```hcl
# infra/aws/dev/terraform.tfvars.example
# Copy to terraform.tfvars and fill in actual values
# DO NOT commit terraform.tfvars to git

aws_region   = "ap-northeast-2"
environment  = "dev"
rds_password = "<CHANGE_ME>"
redis_auth_token = "<CHANGE_ME>"
```

- [ ] **Step 4: .gitignore 추가**

```
# infra/aws/dev/.gitignore
*.tfvars
!terraform.tfvars.example
*.tfstate
*.tfstate.backup
.terraform/
.terraform.lock.hcl
```

- [ ] **Step 5: 검증**

```bash
cd infra/aws/dev
terraform fmt -check
terraform validate  # provider 없이도 구문 검증 가능
```

- [ ] **Step 6: 커밋**

```bash
git add infra/aws/dev/main.tf infra/aws/dev/variables.tf infra/aws/dev/terraform.tfvars.example infra/aws/dev/.gitignore
git commit -m "feat(infra): add Terraform base configuration and variables"
```

---

### Task 2: vpc.tf

**Files:**
- Create: `infra/aws/dev/vpc.tf`

- [ ] **Step 1: vpc.tf 작성**

```hcl
# infra/aws/dev/vpc.tf

# ─── VPC ────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "${local.project}-${local.environment}-vpc" }
}

# ─── Internet Gateway ───────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.project}-${local.environment}-igw" }
}

# ─── Public Subnets ─────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1) # 10.0.1.0/24, 10.0.2.0/24
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${local.project}-${local.environment}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# ─── Private Subnets ────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10) # 10.0.10.0/24, 10.0.20.0/24
  availability_zone = local.azs[count.index]

  tags = {
    Name                                          = "${local.project}-${local.environment}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# ─── NAT Gateway (single, cost saving for dev) ──────────────────────────────

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.project}-${local.environment}-nat-eip" }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags       = { Name = "${local.project}-${local.environment}-nat" }
  depends_on = [aws_internet_gateway.main]
}

# ─── Route Tables ───────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.project}-${local.environment}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.project}-${local.environment}-private-rt" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ─── Security Groups ────────────────────────────────────────────────────────

resource "aws_security_group" "eks_nodes" {
  name_prefix = "${local.project}-${local.environment}-eks-nodes-"
  vpc_id      = aws_vpc.main.id
  description = "EKS worker nodes"

  ingress {
    description = "Allow all internal VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.project}-${local.environment}-eks-nodes-sg" }

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.project}-${local.environment}-rds-"
  vpc_id      = aws_vpc.main.id
  description = "RDS PostgreSQL access from EKS nodes only"

  ingress {
    description     = "PostgreSQL from EKS nodes"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = { Name = "${local.project}-${local.environment}-rds-sg" }

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "redis" {
  name_prefix = "${local.project}-${local.environment}-redis-"
  vpc_id      = aws_vpc.main.id
  description = "Redis access from EKS nodes only"

  ingress {
    description     = "Redis from EKS nodes"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = { Name = "${local.project}-${local.environment}-redis-sg" }

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "msk" {
  name_prefix = "${local.project}-${local.environment}-msk-"
  vpc_id      = aws_vpc.main.id
  description = "MSK Kafka access from EKS nodes only"

  ingress {
    description     = "Kafka TLS from EKS nodes"
    from_port       = 9094
    to_port         = 9094
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  ingress {
    description     = "Kafka plaintext from EKS nodes (dev)"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = { Name = "${local.project}-${local.environment}-msk-sg" }

  lifecycle { create_before_destroy = true }
}

resource "aws_security_group" "opensearch" {
  name_prefix = "${local.project}-${local.environment}-opensearch-"
  vpc_id      = aws_vpc.main.id
  description = "OpenSearch access from EKS nodes only"

  ingress {
    description     = "HTTPS from EKS nodes"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_nodes.id]
  }

  tags = { Name = "${local.project}-${local.environment}-opensearch-sg" }

  lifecycle { create_before_destroy = true }
}
```

- [ ] **Step 2: 검증 및 커밋**

```bash
cd infra/aws/dev && terraform fmt vpc.tf
git add infra/aws/dev/vpc.tf
git commit -m "feat(infra): add VPC with public/private subnets and security groups"
```

---

### Task 3: eks.tf

**Files:**
- Create: `infra/aws/dev/eks.tf`

- [ ] **Step 1: eks.tf 작성**

```hcl
# infra/aws/dev/eks.tf

# ─── IAM Role for EKS Cluster ───────────────────────────────────────────────

resource "aws_iam_role" "eks_cluster" {
  name = "${local.project}-${local.environment}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_vpc_resource_controller" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

# ─── EKS Cluster ────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = "1.29"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"] # dev 환경: kubectl 접근용. prod에서는 제한.
    security_group_ids      = [aws_security_group.eks_nodes.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
  ]

  tags = { Name = local.cluster_name }
}

# ─── IAM Role for Node Group ────────────────────────────────────────────────

resource "aws_iam_role" "eks_nodes" {
  name = "${local.project}-${local.environment}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_nodes.name
}

# ─── Managed Node Group ─────────────────────────────────────────────────────

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.project}-${local.environment}-nodes"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = aws_subnet.private[*].id

  instance_types = [var.eks_node_instance_type]

  scaling_config {
    desired_size = var.eks_node_count
    max_size     = var.eks_node_count + 1
    min_size     = var.eks_node_count
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ecr_read_only,
  ]

  tags = { Name = "${local.project}-${local.environment}-nodes" }
}

# ─── OIDC Provider (for IRSA) ───────────────────────────────────────────────

data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = { Name = "${local.cluster_name}-oidc" }
}
```

- [ ] **Step 2: 커밋**

```bash
cd infra/aws/dev && terraform fmt eks.tf
git add infra/aws/dev/eks.tf
git commit -m "feat(infra): add EKS cluster with managed node group and OIDC"
```

---

### Task 4: rds.tf

**Files:**
- Create: `infra/aws/dev/rds.tf`

- [ ] **Step 1: rds.tf 작성**

```hcl
# infra/aws/dev/rds.tf

resource "aws_db_subnet_group" "main" {
  name       = "${local.project}-${local.environment}-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${local.project}-${local.environment}-db-subnet" }
}

resource "aws_db_parameter_group" "postgres16" {
  name   = "${local.project}-${local.environment}-pg16"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements,pgvector"
  }

  tags = { Name = "${local.project}-${local.environment}-pg16-params" }
}

resource "aws_db_instance" "main" {
  identifier = "${local.project}-${local.environment}-postgres"

  engine         = "postgres"
  engine_version = "16.3"
  instance_class = var.rds_instance_class

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.rds_db_name
  username = var.rds_username
  password = var.rds_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres16.name

  publicly_accessible = false
  multi_az            = false # dev 환경: 비용 절감
  skip_final_snapshot = true  # dev 환경

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  tags = { Name = "${local.project}-${local.environment}-postgres" }
}
```

- [ ] **Step 2: 커밋**

```bash
cd infra/aws/dev && terraform fmt rds.tf
git add infra/aws/dev/rds.tf
git commit -m "feat(infra): add RDS PostgreSQL 16 with encryption and SSL"
```

---

### Task 5: msk.tf

**Files:**
- Create: `infra/aws/dev/msk.tf`

- [ ] **Step 1: msk.tf 작성**

```hcl
# infra/aws/dev/msk.tf

resource "aws_msk_configuration" "main" {
  name              = "${local.project}-${local.environment}-kafka-config"
  kafka_versions    = ["3.6.0"]
  server_properties = <<-EOF
    auto.create.topics.enable=false
    default.replication.factor=3
    min.insync.replicas=2
    num.partitions=3
    log.retention.hours=168
    log.segment.bytes=1073741824
  EOF
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "${local.project}-${local.environment}-kafka"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = var.msk_broker_count

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 10 # GB per broker, dev minimum
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = false # dev 환경: 비용 절감
        log_group = ""
      }
    }
  }

  tags = { Name = "${local.project}-${local.environment}-kafka" }
}
```

- [ ] **Step 2: 커밋**

```bash
cd infra/aws/dev && terraform fmt msk.tf
git add infra/aws/dev/msk.tf
git commit -m "feat(infra): add MSK Kafka cluster with TLS encryption"
```

---

### Task 6: redis.tf

**Files:**
- Create: `infra/aws/dev/redis.tf`

- [ ] **Step 1: redis.tf 작성**

```hcl
# infra/aws/dev/redis.tf

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.project}-${local.environment}-redis-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${local.project}-${local.environment}-redis-subnet" }
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${local.project}-${local.environment}-redis"
  description          = "Synapse dev Redis cluster"

  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type
  num_cache_clusters   = 1 # dev 환경: 단일 노드
  port                 = 6379
  parameter_group_name = "default.redis7"

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.redis_auth_token

  automatic_failover_enabled = false # 단일 노드이므로 비활성화
  multi_az_enabled           = false

  snapshot_retention_limit = 1
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "Mon:04:00-Mon:05:00"

  tags = { Name = "${local.project}-${local.environment}-redis" }
}
```

- [ ] **Step 2: 커밋**

```bash
cd infra/aws/dev && terraform fmt redis.tf
git add infra/aws/dev/redis.tf
git commit -m "feat(infra): add ElastiCache Redis 7 with AUTH and TLS"
```

---

### Task 7: opensearch.tf

**Files:**
- Create: `infra/aws/dev/opensearch.tf`

- [ ] **Step 1: opensearch.tf 작성**

```hcl
# infra/aws/dev/opensearch.tf

data "aws_caller_identity" "current" {}

resource "aws_opensearch_domain" "main" {
  domain_name    = "${local.project}-${local.environment}"
  engine_version = "OpenSearch_2.13"

  cluster_config {
    instance_type  = var.opensearch_instance_type
    instance_count = 1

    zone_awareness_enabled = false # dev: 단일 노드
  }

  ebs_options {
    ebs_enabled = true
    volume_type = "gp3"
    volume_size = 10
  }

  vpc_options {
    subnet_ids         = [aws_subnet.private[0].id]
    security_group_ids = [aws_security_group.opensearch.id]
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-PFS-2023-10"
  }

  access_policies = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "*" }
      Action    = "es:*"
      Resource  = "arn:aws:es:${var.aws_region}:${data.aws_caller_identity.current.account_id}:domain/${local.project}-${local.environment}/*"
      Condition = {
        IpAddress = {
          "aws:SourceIp" = var.vpc_cidr
        }
      }
    }]
  })

  tags = { Name = "${local.project}-${local.environment}-opensearch" }
}
```

- [ ] **Step 2: 커밋**

```bash
cd infra/aws/dev && terraform fmt opensearch.tf
git add infra/aws/dev/opensearch.tf
git commit -m "feat(infra): add OpenSearch domain with VPC access and encryption"
```

---

### Task 8: argocd.tf

**Files:**
- Create: `infra/aws/dev/argocd.tf`

- [ ] **Step 1: argocd.tf 작성**

```hcl
# infra/aws/dev/argocd.tf

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "6.7.3"
  namespace        = "argocd"
  create_namespace = true

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "server.ingress.enabled"
    value = "false"
  }

  set {
    name  = "configs.params.server\\.insecure"
    value = "true" # dev 환경: TLS termination은 ingress에서 처리
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "256Mi"
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "100m"
  }

  set {
    name  = "server.resources.requests.memory"
    value = "128Mi"
  }

  set {
    name  = "server.resources.requests.cpu"
    value = "50m"
  }

  depends_on = [aws_eks_node_group.main]
}
```

- [ ] **Step 2: 커밋**

```bash
cd infra/aws/dev && terraform fmt argocd.tf
git add infra/aws/dev/argocd.tf
git commit -m "feat(infra): add ArgoCD Helm release for EKS"
```

---

### Task 9: outputs.tf

**Files:**
- Create: `infra/aws/dev/outputs.tf`

- [ ] **Step 1: outputs.tf 작성**

```hcl
# infra/aws/dev/outputs.tf

# ─── VPC ────────────────────────────────────────────────────────────────────

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

# ─── EKS ────────────────────────────────────────────────────────────────────

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_ca_cert" {
  description = "EKS cluster CA certificate (base64)"
  value       = aws_eks_cluster.main.certificate_authority[0].data
  sensitive   = true
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN (for IRSA)"
  value       = aws_iam_openid_connect_provider.eks.arn
}

# ─── RDS ────────────────────────────────────────────────────────────────────

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.main.endpoint
}

output "rds_port" {
  description = "RDS PostgreSQL port"
  value       = aws_db_instance.main.port
}

# ─── MSK ────────────────────────────────────────────────────────────────────

output "msk_bootstrap_brokers_tls" {
  description = "MSK bootstrap brokers (TLS)"
  value       = aws_msk_cluster.main.bootstrap_brokers_tls
}

output "msk_zookeeper_connect" {
  description = "MSK Zookeeper connection string"
  value       = aws_msk_cluster.main.zookeeper_connect_string
}

# ─── Redis ──────────────────────────────────────────────────────────────────

output "redis_endpoint" {
  description = "Redis primary endpoint"
  value       = aws_elasticache_replication_group.main.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port"
  value       = aws_elasticache_replication_group.main.port
}

# ─── OpenSearch ─────────────────────────────────────────────────────────────

output "opensearch_endpoint" {
  description = "OpenSearch domain endpoint"
  value       = aws_opensearch_domain.main.endpoint
}

output "opensearch_dashboard_endpoint" {
  description = "OpenSearch Dashboard endpoint"
  value       = aws_opensearch_domain.main.dashboard_endpoint
}
```

- [ ] **Step 2: 커밋**

```bash
cd infra/aws/dev && terraform fmt outputs.tf
git add infra/aws/dev/outputs.tf
git commit -m "feat(infra): add Terraform outputs for all service endpoints"
```

---

### Task 10: ApplicationSet 확인 및 최종 push

**Files:**
- Verify: `argocd/applicationset.yaml` (이미 존재, 수정 불필요)

- [ ] **Step 1: ApplicationSet 이미 완성 확인**

기존 `argocd/applicationset.yaml`이 이미 5서비스 x 3환경 matrix + dev만 autoSync하는 `templatePatch`를 포함하고 있음을 확인:
- services: platform-svc, engagement-svc, knowledge-svc, learning-card, learning-ai
- envs: dev (auto), staging (manual), prod (manual)
- path: `apps/{{service}}/overlays/{{env}}`

수정 불필요.

- [ ] **Step 2: 전체 terraform fmt 검증**

```bash
cd infra/aws/dev
terraform fmt -recursive .
```

- [ ] **Step 3: 최종 push**

```bash
git push origin docs/INFRA-001-aws-provisioning-workflow-guide
```

Expected: 브랜치에 9개 .tf 파일 + docs 추가됨
