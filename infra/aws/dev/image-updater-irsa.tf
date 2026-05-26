# argocd-image-updater가 ECR 태그를 읽기 위한 IRSA (SA: argocd/argocd-image-updater)
data "aws_iam_policy_document" "image_updater_assume" {
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
      values   = ["system:serviceaccount:argocd:argocd-image-updater"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "image_updater" {
  name               = "synapse-dev-image-updater-role"
  assume_role_policy = data.aws_iam_policy_document.image_updater_assume.json
}

resource "aws_iam_role_policy_attachment" "image_updater_ecr" {
  role       = aws_iam_role.image_updater.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

output "image_updater_role_arn" {
  description = "argocd-image-updater IRSA role ARN"
  value       = aws_iam_role.image_updater.arn
}
