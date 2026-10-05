output "cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.this.arn
}

output "bootstrap_brokers_sasl_iam" {
  description = "Bootstrap broker string for SASL/IAM clients (TLS, port 9098)."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
}

output "client_security_group_id" {
  description = "Attach this security group to producers and consumers."
  value       = aws_security_group.client.id
}

output "msk_security_group_id" {
  description = "Security group on the MSK brokers."
  value       = aws_security_group.msk.id
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs hosting the brokers."
  value       = aws_subnet.private[*].id
}

output "broker_log_group" {
  description = "CloudWatch log group receiving broker logs."
  value       = aws_cloudwatch_log_group.broker.name
}
