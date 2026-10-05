# Broker logs. The MSK cluster writes here (see logging_info in msk.tf).
resource "aws_cloudwatch_log_group" "broker" {
  name              = "/aws/msk/${var.cluster_name}"
  retention_in_days = var.log_retention_days

  tags = { Name = "${var.cluster_name}-broker-logs" }
}

locals {
  # REQUIRES ACCOUNT CONFIGURATION: sns_topic_arn. Without it alarms still
  # exist and show state in CloudWatch, but nobody is notified.
  alarm_actions = var.sns_topic_arn == null ? [] : [var.sns_topic_arn]

  # Broker IDs are numbered 1..N.
  broker_ids = toset([for i in range(1, var.number_of_broker_nodes + 1) : tostring(i)])
}

# CPU used by user processes, per broker.
resource "aws_cloudwatch_metric_alarm" "cpu_user" {
  for_each = local.broker_ids

  alarm_name          = "${var.cluster_name}-broker-${each.value}-cpu-user-high"
  alarm_description   = "CpuUser above ${var.cpu_user_threshold_percent}% on broker ${each.value}"
  namespace           = "AWS/Kafka"
  metric_name         = "CpuUser"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.cpu_user_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    "Cluster Name" = aws_msk_cluster.this.cluster_name
    "Broker ID"    = each.value
  }
}

# Data volume usage, per broker.
resource "aws_cloudwatch_metric_alarm" "disk_used" {
  for_each = local.broker_ids

  alarm_name          = "${var.cluster_name}-broker-${each.value}-data-disk-high"
  alarm_description   = "KafkaDataLogsDiskUsed above ${var.disk_used_threshold_percent}% on broker ${each.value}"
  namespace           = "AWS/Kafka"
  metric_name         = "KafkaDataLogsDiskUsed"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.disk_used_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    "Cluster Name" = aws_msk_cluster.this.cluster_name
    "Broker ID"    = each.value
  }
}

# Exactly one active controller is expected across the cluster. A sum below 1
# means no controller. Check the MSK docs for the exact aggregation of this metric.
resource "aws_cloudwatch_metric_alarm" "active_controller" {
  alarm_name          = "${var.cluster_name}-no-active-controller"
  alarm_description   = "ActiveControllerCount is below 1"
  namespace           = "AWS/Kafka"
  metric_name         = "ActiveControllerCount"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    "Cluster Name" = aws_msk_cluster.this.cluster_name
  }
}

# Partitions with no active leader.
resource "aws_cloudwatch_metric_alarm" "offline_partitions" {
  alarm_name          = "${var.cluster_name}-offline-partitions"
  alarm_description   = "OfflinePartitionsCount is above 0"
  namespace           = "AWS/Kafka"
  metric_name         = "OfflinePartitionsCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    "Cluster Name" = aws_msk_cluster.this.cluster_name
  }
}

# Consumer lag for the search-service group on market-events. Consumer-group lag
# metrics depend on the cluster monitoring level and on the group being active;
# check the MSK monitoring documentation, and set enable_consumer_lag_alarm = false
# if it does not apply to your setup.
resource "aws_cloudwatch_metric_alarm" "consumer_lag" {
  count = var.enable_consumer_lag_alarm ? 1 : 0

  alarm_name          = "${var.cluster_name}-${var.consumer_group_name}-lag-high"
  alarm_description   = "MaxOffsetLag above ${var.consumer_lag_threshold} for ${var.consumer_group_name} on ${var.topic_name}"
  namespace           = "AWS/Kafka"
  metric_name         = "MaxOffsetLag"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.consumer_lag_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  dimensions = {
    "Cluster Name"   = aws_msk_cluster.this.cluster_name
    "Consumer Group" = var.consumer_group_name
    "Topic"          = var.topic_name
  }
}
