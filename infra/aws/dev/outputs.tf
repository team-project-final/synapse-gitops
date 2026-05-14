output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "aws_region" {
  description = "AWS region."
  value       = var.aws_region
}

output "rds_endpoint" {
  description = "Private RDS PostgreSQL endpoint."
  value       = aws_db_instance.postgres.address
}

output "redis_endpoint" {
  description = "Private ElastiCache Redis primary endpoint."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "msk_bootstrap_brokers_tls" {
  description = "MSK TLS bootstrap brokers."
  value       = aws_msk_cluster.this.bootstrap_brokers_tls
}

output "opensearch_endpoint" {
  description = "Private OpenSearch endpoint."
  value       = aws_opensearch_domain.this.endpoint
}

output "ecr_repositories" {
  description = "ECR repository URLs by service."
  value = {
    for service, repo in aws_ecr_repository.services : service => repo.repository_url
  }
}

output "schema_registry_internal_url" {
  description = "Internal Schema Registry URL inside the cluster."
  value       = "http://${kubernetes_service.schema_registry.metadata[0].name}.${kubernetes_namespace.infra.metadata[0].name}.svc.cluster.local:8081"
}
