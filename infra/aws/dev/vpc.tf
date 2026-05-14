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
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
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
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
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
