resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.project}-${local.environment}-redis-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${local.project}-${local.environment}-redis-subnet" }
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "${local.project}-${local.environment}-redis"
  description          = "Synapse dev Redis cluster"

  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type
  num_cache_clusters   = 1
  port                 = 6379
  parameter_group_name = "default.redis7"

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                 = var.redis_auth_token

  automatic_failover_enabled = false
  multi_az_enabled           = false

  snapshot_retention_limit = 1
  snapshot_window          = "03:00-04:00"
  maintenance_window       = "Mon:04:00-Mon:05:00"

  tags = { Name = "${local.project}-${local.environment}-redis" }
}
