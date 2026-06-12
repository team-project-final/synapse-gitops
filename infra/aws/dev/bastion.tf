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
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
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
      },
      {
        Effect   = "Allow"
        Action   = ["kafka:ListClustersV2"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka:GetBootstrapBrokers",
          "kafka:DescribeClusterV2"
        ]
        Resource = aws_msk_cluster.main.arn
      },
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

# ─── Security Group ─────────────────────────────────────────────────────────

resource "aws_security_group" "bastion" {
  name_prefix = "${local.project}-${local.environment}-bastion-"
  vpc_id      = aws_vpc.main.id
  description = "Bastion host - SSM only, no SSH"

  egress {
    description = "All outbound (SSM + EKS API + DNS + package downloads)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.project}-${local.environment}-bastion-sg" }

  lifecycle { create_before_destroy = true }
}

# ─── EC2 Instance ────────────────────────────────────────────────────────────

resource "aws_instance" "bastion" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  iam_instance_profile   = aws_iam_instance_profile.bastion.name
  vpc_security_group_ids = [aws_security_group.bastion.id]

  # user_data가 cluster_name을 문자열로만 참조해 암묵 의존성이 없음 → bastion이 EKS·IAM 정책보다
  # 먼저 부팅해 cloud-init의 update-kubeconfig가 권한 오류로 죽는 레이스(#182, 06-11 02:44 실측:
  # 인라인 정책은 존재했으나 cloud-init 시점에 미전파). 명시 의존 + 아래 재시도로 이중 방어.
  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy.bastion_eks,
  ]

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    # SSM Agent 설치 (AL2023 최소 AMI에 미포함될 수 있음)
    dnf install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    # kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl

    # helm
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    # kubeconfig for ec2-user (ssm-user는 첫 SSM 세션 시 자동 생성)
    # IAM 전파 지연·EKS 미가용 대비 재시도(최대 30회×30s) — 단발 실패가 set -e로
    # cloud-init 전체를 죽여 bring-up 자동화가 중단됐던 #182 재발 방지.
    for i in $(seq 1 30); do
      if runuser -l ec2-user -c "aws eks update-kubeconfig --name ${local.cluster_name} --region ${var.aws_region}"; then
        break
      fi
      echo "update-kubeconfig 실패(시도 $i/30) — 30s 후 재시도"
      sleep 30
    done
  EOF

  tags = { Name = "${local.project}-${local.environment}-bastion" }
}
