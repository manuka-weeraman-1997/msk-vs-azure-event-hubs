# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment label used in tags (for example dev, staging, prod)."
  type        = string
  default     = "dev"
}

variable "owner" {
  description = "Owner tag value."
  type        = string
  default     = "platform-engineering"
}

variable "extra_tags" {
  description = "Additional tags merged into every resource."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Networking
# ---------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones (one private subnet each). MSK needs 2 or 3."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "private_subnet_newbits" {
  description = "Extra prefix bits added to vpc_cidr for each private subnet (/16 + 4 = /20)."
  type        = number
  default     = 4
}

variable "additional_client_cidrs" {
  description = "Optional CIDR blocks (for example a peered network or VPN range) allowed to reach the Kafka client ports."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# MSK cluster
# ---------------------------------------------------------------------------
variable "cluster_name" {
  description = "MSK cluster name."
  type        = string
  default     = "streaming-msk"
}

# REQUIRES ACCOUNT CONFIGURATION: set to a Kafka version that Amazon MSK
# currently supports in your region. Check the MSK documentation and
# `aws kafka list-kafka-versions` before applying. No default is assumed here.
variable "kafka_version" {
  description = "Apache Kafka version for the cluster. Check which versions MSK currently supports."
  type        = string
}

variable "broker_instance_type" {
  description = "MSK broker instance type. Check MSK documentation for current options."
  type        = string
  default     = "kafka.m5.large"
}

variable "number_of_broker_nodes" {
  description = "Total broker count. Must be a multiple of az_count."
  type        = number
  default     = 3
}

variable "broker_ebs_volume_size_gb" {
  description = "EBS volume size per broker in GiB."
  type        = number
  default     = 100
}

variable "default_replication_factor" {
  description = "Default replication factor for new topics (server.properties)."
  type        = number
  default     = 3
}

variable "min_insync_replicas" {
  description = "min.insync.replicas (server.properties). Keep below the replication factor."
  type        = number
  default     = 2
}

variable "default_num_partitions" {
  description = "num.partitions default for topics created without an explicit count."
  type        = number
  default     = 4
}

variable "log_retention_hours" {
  description = "log.retention.hours default. 24 matches the 24 hour example for market-events."
  type        = number
  default     = 24
}

variable "enhanced_monitoring" {
  description = "MSK enhanced monitoring level: DEFAULT, PER_BROKER, PER_TOPIC_PER_BROKER or PER_TOPIC_PER_PARTITION."
  type        = string
  default     = "PER_BROKER"

  validation {
    condition     = contains(["DEFAULT", "PER_BROKER", "PER_TOPIC_PER_BROKER", "PER_TOPIC_PER_PARTITION"], var.enhanced_monitoring)
    error_message = "enhanced_monitoring must be DEFAULT, PER_BROKER, PER_TOPIC_PER_BROKER or PER_TOPIC_PER_PARTITION."
  }
}

# ---------------------------------------------------------------------------
# Encryption and authentication
# ---------------------------------------------------------------------------
# REQUIRES ACCOUNT CONFIGURATION: optional customer-managed KMS key ARN for
# encryption at rest. When null, MSK uses an AWS managed key.
variable "kms_key_arn" {
  description = "KMS key ARN for encryption at rest. Null uses the AWS managed key."
  type        = string
  default     = null
}

variable "enable_mutual_tls" {
  description = "Enable TLS client authentication (port 9094). Requires private CA ARNs."
  type        = bool
  default     = false
}

# REQUIRES ACCOUNT CONFIGURATION: ACM Private CA ARNs, needed only when
# enable_mutual_tls is true.
variable "tls_certificate_authority_arns" {
  description = "ACM Private CA ARNs used to validate client certificates."
  type        = list(string)
  default     = []
}

variable "enable_sasl_scram" {
  description = "Enable SASL/SCRAM client authentication (port 9096). Secrets must be associated separately."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------
variable "log_retention_days" {
  description = "CloudWatch retention in days for broker logs."
  type        = number
  default     = 14
}

# REQUIRES ACCOUNT CONFIGURATION: an existing SNS topic ARN for alarm
# notifications. When null, alarms are created without notification actions.
variable "sns_topic_arn" {
  description = "SNS topic ARN notified when alarms fire and recover."
  type        = string
  default     = null
}

variable "cpu_user_threshold_percent" {
  description = "CpuUser alarm threshold in percent."
  type        = number
  default     = 60
}

variable "disk_used_threshold_percent" {
  description = "KafkaDataLogsDiskUsed alarm threshold in percent."
  type        = number
  default     = 80
}

variable "enable_consumer_lag_alarm" {
  description = "Create a MaxOffsetLag alarm for the consumer group. Check the MSK docs for which monitoring level publishes consumer lag metrics."
  type        = bool
  default     = true
}

variable "consumer_group_name" {
  description = "Consumer group used for the lag alarm."
  type        = string
  default     = "search-service"
}

variable "topic_name" {
  description = "Topic used for the lag alarm."
  type        = string
  default     = "market-events"
}

variable "consumer_lag_threshold" {
  description = "MaxOffsetLag alarm threshold (messages)."
  type        = number
  default     = 10000
}
