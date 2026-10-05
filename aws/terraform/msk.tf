# Cluster configuration (server.properties). Changing it creates a new revision
# that is applied to the cluster.
resource "aws_msk_configuration" "this" {
  name           = "${var.cluster_name}-config"
  description    = "Broker configuration for ${var.cluster_name}"
  kafka_versions = [var.kafka_version]

  server_properties = <<-PROPS
    # Topics are created explicitly (see ../../kafka/README.md), not on first use.
    auto.create.topics.enable=false
    default.replication.factor=${var.default_replication_factor}
    min.insync.replicas=${var.min_insync_replicas}
    num.partitions=${var.default_num_partitions}
    # 24 hours, matching the market-events example.
    log.retention.hours=${var.log_retention_hours}
    # Allow topic deletion with admin tooling.
    delete.topic.enable=true
  PROPS
}

resource "aws_msk_cluster" "this" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.number_of_broker_nodes
  enhanced_monitoring    = var.enhanced_monitoring

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_ebs_volume_size_gb
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.this.arn
    revision = aws_msk_configuration.this.latest_revision
  }

  encryption_info {
    # Encryption at rest. Null uses the AWS managed key.
    encryption_at_rest_kms_key_arn = var.kms_key_arn

    encryption_in_transit {
      client_broker = "TLS" # TLS only, no plaintext listener
      in_cluster    = true
    }
  }

  client_authentication {
    sasl {
      iam   = true
      scram = var.enable_sasl_scram
    }

    dynamic "tls" {
      for_each = var.enable_mutual_tls ? [1] : []
      content {
        certificate_authority_arns = var.tls_certificate_authority_arns
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.broker.name
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.number_of_broker_nodes % var.az_count == 0
      error_message = "number_of_broker_nodes must be a multiple of az_count."
    }
    precondition {
      condition     = var.min_insync_replicas < var.default_replication_factor
      error_message = "min_insync_replicas must be lower than default_replication_factor."
    }
    precondition {
      condition     = !var.enable_mutual_tls || length(var.tls_certificate_authority_arns) > 0
      error_message = "Set tls_certificate_authority_arns when enable_mutual_tls is true."
    }
  }

  tags = { Name = var.cluster_name }
}
