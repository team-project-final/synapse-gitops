terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # dev 스택과 분리된 standalone state — ECR 레포는 윈도우 destroy(infra/aws/dev)에서
  # 살아남아야 함(이미지 보존). dev 스택에 넣으면 teardown마다 레포·이미지가 전부 삭제되어
  # 다음 bring-up이 ImagePullBackOff로 시작함(#182 근본 원인 2 재발).
  backend "s3" {
    bucket         = "synapse-terraform-state"
    key            = "ecr/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "synapse-terraform-locks"
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "ap-northeast-2"
}

# 서비스 7종 + elasticsearch(nori 커스텀, shared#53). team-lead 수동 선생성분(2026-06-11,
# MUTABLE·scanOnPush)을 IaC 편입 — 기존 레포는 `terraform import`로 흡수(아래 README).
locals {
  repositories = [
    "synapse/elasticsearch",
    "synapse/engagement-svc",
    "synapse/frontend",
    "synapse/gateway",
    "synapse/knowledge-svc",
    "synapse/learning-ai",
    "synapse/learning-card",
    "synapse/platform-svc",
  ]
}

resource "aws_ecr_repository" "this" {
  for_each = toset(local.repositories)

  name = each.value
  # IU(image-updater) write-back·dev-latest 운용이 mutable 태그 전제(#165 결정 전까지 유지).
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    # 윈도우 teardown·실수 destroy로부터 이미지 보호. 정리가 필요하면 명시적으로 해제 후 진행.
    prevent_destroy = true
  }

  tags = {
    Project   = "synapse"
    ManagedBy = "terraform"
  }
}

output "repository_urls" {
  value = { for k, r in aws_ecr_repository.this : k => r.repository_url }
}
