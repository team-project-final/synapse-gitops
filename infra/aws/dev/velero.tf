# Velero 백업용 S3 버킷 + IRSA. eso-irsa.tf 패턴 미러링.
# SA: velero/velero. ns(synapse-prod/staging)+PV 일일 백업 → 이 버킷.
# data.aws_caller_identity.current 는 main.tf 에 정의됨(재정의 금지).

locals {
  velero_bucket = "synapse-velero-backups-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "velero" {
  bucket = local.velero_bucket
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket                  = aws_s3_bucket.velero.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "velero_assume" {
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
      values   = ["system:serviceaccount:velero:velero"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "velero" {
  # S3: 백업 객체 read/write
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
    ]
    resources = ["${aws_s3_bucket.velero.arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.velero.arn]
  }
  # EC2: PV(EBS) 스냅샷
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeSnapshots",
      "ec2:CreateTags",
      "ec2:CreateVolume",
      "ec2:CreateSnapshot",
      "ec2:DeleteSnapshot",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "velero" {
  name        = "synapse-dev-velero"
  description = "Velero backup: S3 (velero bucket) + EBS snapshot"
  policy      = data.aws_iam_policy_document.velero.json
}

resource "aws_iam_role" "velero" {
  name               = "synapse-dev-velero-role"
  assume_role_policy = data.aws_iam_policy_document.velero_assume.json
}

resource "aws_iam_role_policy_attachment" "velero" {
  role       = aws_iam_role.velero.name
  policy_arn = aws_iam_policy.velero.arn
}
