resource "aws_db_subnet_group" "main" {
  name       = "${local.project}-${local.environment}-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${local.project}-${local.environment}-db-subnet" }
}

resource "aws_db_parameter_group" "postgres16" {
  name   = "${local.project}-${local.environment}-pg16"
  family = "postgres16"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "shared_preload_libraries"
    value = "pg_stat_statements"
  }

  tags = { Name = "${local.project}-${local.environment}-pg16-params" }
}

resource "aws_db_instance" "main" {
  identifier = "${local.project}-${local.environment}-postgres"

  engine         = "postgres"
  engine_version = "16.3"
  instance_class = var.rds_instance_class

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.rds_db_name
  username = var.rds_username
  password = var.rds_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = aws_db_parameter_group.postgres16.name

  publicly_accessible = false
  multi_az            = false
  skip_final_snapshot = true

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  tags = { Name = "${local.project}-${local.environment}-postgres" }
}
