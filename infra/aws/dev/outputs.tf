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

output "rds_username" {
  description = "RDS master username (dev+staging 공통). phase_db_init psql 접속용."
  value       = var.rds_username
  sensitive   = true # var.rds_username이 sensitive → output도 명시 필요. terraform output -raw는 정상 동작.
}

# #156: staging 전용 RDS 엔드포인트(staging 오버레이 DATABASE_HOST 전환용).
output "rds_staging_endpoint" {
  description = "Staging RDS PostgreSQL endpoint"
  value       = aws_db_instance.staging.endpoint
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

# ─── Bastion ────────────────────────────────────────────────────────────────

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID (for SSM session)"
  value       = aws_instance.bastion.id
}

# ─── Bring-up automation outputs ──────────────────────────────────────────
output "eks_cluster_security_group_id" {
  description = "EKS 클러스터 auto-managed SG (D-026 source)"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "sg_rds_id" {
  description = "RDS SG ID"
  value       = aws_security_group.rds.id
}

output "sg_redis_id" {
  description = "Redis SG ID"
  value       = aws_security_group.redis.id
}

output "sg_msk_id" {
  description = "MSK SG ID"
  value       = aws_security_group.msk.id
}

output "eks_oidc_id" {
  description = "EKS OIDC provider ID (마지막 path 세그먼트)"
  value       = element(split("/", aws_iam_openid_connect_provider.eks.url), length(split("/", aws_iam_openid_connect_provider.eks.url)) - 1)
}

# ─── Velero (백업) ──────────────────────────────────────────────────────────
output "velero_role_arn" {
  description = "Velero IRSA role ARN (annotate velero SA with this)"
  value       = aws_iam_role.velero.arn
}

output "velero_bucket" {
  description = "Velero backup S3 bucket"
  value       = aws_s3_bucket.velero.id
}
