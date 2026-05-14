resource "aws_msk_configuration" "main" {
  name              = "${local.project}-${local.environment}-kafka-config"
  kafka_versions    = ["3.6.0"]
  server_properties = <<-EOF
    auto.create.topics.enable=false
    default.replication.factor=3
    min.insync.replicas=2
    num.partitions=3
    log.retention.hours=168
    log.segment.bytes=1073741824
  EOF
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "${local.project}-${local.environment}-kafka"
  kafka_version          = "3.6.0"
  number_of_broker_nodes = var.msk_broker_count

  broker_node_group_info {
    instance_type   = var.msk_instance_type
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 10
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  tags = { Name = "${local.project}-${local.environment}-kafka" }
}
