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

output "sg_opensearch_id" {
  description = "OpenSearch SG ID"
  value       = aws_security_group.opensearch.id
}

output "eks_oidc_id" {
  description = "EKS OIDC provider ID (마지막 path 세그먼트)"
  value       = element(split("/", aws_iam_openid_connect_provider.eks.url), length(split("/", aws_iam_openid_connect_provider.eks.url)) - 1)
}
