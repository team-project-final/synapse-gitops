# aws-load-balancer-controller IRSA (SA: kube-system/aws-load-balancer-controller).
# ALB Ingress(infra/ingress/*, infra/ingress/nipio/*) 프로비저닝에 필요.
# 정책은 공식 v2.7.2 iam_policy.json(alb-controller-iam-policy.json)을 그대로 사용.
# (W5 clearance window 발견: 컨트롤러 미부트스트랩 → #121 차단. gitops#121 참조.)

data "aws_iam_policy_document" "alb_controller_assume" {
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
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "alb_controller" {
  name   = "synapse-dev-alb-controller"
  policy = file("${path.module}/alb-controller-iam-policy.json")
}

resource "aws_iam_role" "alb_controller" {
  name               = "synapse-dev-alb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.alb_controller_assume.json
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

output "alb_controller_role_arn" {
  description = "aws-load-balancer-controller IRSA role ARN"
  value       = aws_iam_role.alb_controller.arn
}
