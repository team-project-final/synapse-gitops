resource "aws_db_subnet_group" "main" {
  name       = "${local.project}-${local.environment}-db-subnet"
  subnet_ids = aws_subnet.private[*].id

  tags = { Name = "${local.project}-${local.environment}-db-subnet" }
}

resource "aws_db_parameter_group" "postgres16" {
  name   = "${local.project}-${local.environment}-pg16"
  family = "postgres16"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = { Name = "${local.project}-${local.environment}-pg16-params" }
}

resource "aws_db_instance" "main" {
  identifier = "${local.project}-${local.environment}-postgres"

  engine         = "postgres"
  engine_version = "16.9"
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
  apply_immediately   = true

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  tags = { Name = "${local.project}-${local.environment}-postgres" }
}

# #156: staging 전용 RDS 인스턴스 — staging이 dev RDS 공유하던 환경격리 갭 해소.
# 동일 VPC/서브넷/SG/파라미터그룹 재사용(force_ssl=1), db.t3.small(dev medium 대비 비용↓).
# 서비스별 DB 5종(synapse_*)은 기동 후 psql 수동 생성(dev 패턴). 윈도우 종료 시 destroy로 과금0.
resource "aws_db_instance" "staging" {
  identifier = "${local.project}-staging-postgres"

  engine         = "postgres"
  engine_version = "16.9"
  instance_class = var.rds_staging_instance_class

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
  apply_immediately   = true

  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  tags = { Name = "${local.project}-staging-postgres" }
}
