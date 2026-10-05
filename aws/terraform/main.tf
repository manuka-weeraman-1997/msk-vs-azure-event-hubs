# Amazon MSK streaming platform for the market-data pipeline.
#
# Flow: producer -> VPC / private subnets / security groups -> MSK cluster
#       -> topic `market-events` (4 partitions) -> consumer group `search-service`
#
# Files:
#   networking.tf  VPC, private subnets, route table, security groups
#   msk.tf         MSK configuration and cluster
#   monitoring.tf  CloudWatch log group and alarms
#
# Topics are NOT created here. MSK topics are created with Kafka admin tooling
# (for example kafka-topics.sh or an admin client). See ../../kafka/README.md for
# the `market-events` topic definition.

locals {
  common_tags = merge(
    {
      Project     = "msk-vs-azure-event-hubs"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = var.owner
    },
    var.extra_tags
  )

  # Availability zones actually used, limited to the requested subnet count.
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)
}

data "aws_availability_zones" "available" {
  state = "available"
}
