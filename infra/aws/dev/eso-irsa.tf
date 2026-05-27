# External Secrets Operator IRSA — terraform화 (A2, 기존 수동 생성분 코드화)
# image-updater-irsa.tf 패턴 미러링. SA: external-secrets/external-secrets (step5-eso-secrets.md).
#
# ⚠️ 라이브 apply 전 주의: 기존에 aws CLI로 수동 생성한 role "synapse-dev-eso-role"이
#    계정에 남아있으면 EntityAlreadyExists 충돌. T12 라이브 사이클 전
#    `terraform import aws_iam_role.eso synapse-dev-eso-role` 하거나 수동 role/policy 삭제.

data "aws_iam_policy_document" "eso_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-secrets:external-secrets"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "eso_secrets_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecrets",
    ]
    # synapse/* 와일드카드가 dev·staging·monitoring·gitops 전부 포함 (step5-eso-secrets.md 정합)
    resources = ["arn:aws:secretsmanager:${var.aws_region}:*:secret:synapse/*"]
  }
}

resource "aws_iam_policy" "eso_secrets_read" {
  name        = "synapse-dev-eso-secrets-read"
  description = "ESO read access to synapse/* secrets (dev, staging, monitoring, gitops)"
  policy      = data.aws_iam_policy_document.eso_secrets_read.json
}

resource "aws_iam_role" "eso" {
  name               = "synapse-dev-eso-role"
  assume_role_policy = data.aws_iam_policy_document.eso_assume.json
}

resource "aws_iam_role_policy_attachment" "eso" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.eso_secrets_read.arn
}

output "eso_role_arn" {
  description = "ESO IRSA role ARN (annotate external-secrets SA with this)"
  value       = aws_iam_role.eso.arn
}
