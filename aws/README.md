# AWS: Amazon MSK (Terraform)

Terraform for the AWS side of the market-data pipeline. It builds a private network, an [Amazon MSK](https://docs.aws.amazon.com/msk/latest/developerguide/what-is-msk.html) cluster named `streaming-msk`, and CloudWatch logging and alarms. Amazon MSK is managed Apache Kafka.

## What it builds

| Area | Resources | File |
|---|---|---|
| Network | VPC, private subnets (one per AZ, default 3), route table, client and MSK security groups | `terraform/networking.tf` |
| Cluster | `aws_msk_configuration` (server.properties) and `aws_msk_cluster` with TLS, encryption at rest, SASL/IAM | `terraform/msk.tf` |
| Monitoring | CloudWatch log group for broker logs, alarms on `AWS/Kafka` metrics | `terraform/monitoring.tf` |

Tags are applied to everything through the provider `default_tags`.

## AWS flow

```
Market Data Application
        |
   Kafka producer
        |
  VPC / private subnets / security groups   (TLS + SASL/IAM)
        |
   Amazon MSK cluster: streaming-msk
        |
   Topic: market-events (partitions P0..P3, key = symbol, 24h retention)
        |
   Consumer group: search-service  (C1..C4, one consumer per partition)
        |
   Downstream: search / analytics / application
```

The Azure side has the same logical flow, and the mapping is conceptual, not 1:1. See [../docs/msk.md](../docs/msk.md).

## Ports

The MSK security group allows only these inbound ports, from the client security group and from the optional `additional_client_cidrs` list:

| Port | Protocol | When |
|---|---|---|
| 9098 | TLS with SASL/IAM | always |
| 9094 | TLS (mutual TLS) | only if `enable_mutual_tls = true` |
| 9096 | TLS with SASL/SCRAM | only if `enable_sasl_scram = true` |

## Prerequisites

- Terraform 1.5 or later and the AWS provider `~> 5.0` (installed by `terraform init`).
- AWS credentials with permission to create VPC, MSK, CloudWatch and security group resources.
- A Kafka version that MSK currently supports. Check the [MSK documentation](https://docs.aws.amazon.com/msk/latest/developerguide/what-is-msk.html) or `aws kafka list-kafka-versions`. `kafka_version` has no default on purpose.
- Optional: a KMS key ARN, an SNS topic ARN for alarms, ACM Private CA ARNs for mutual TLS. Search for `REQUIRES ACCOUNT CONFIGURATION` in `terraform/` to find every account-specific value.

## How to run

```bash
cd aws/terraform
cp terraform.tfvars.example terraform.tfvars   # edit values, never commit real ones
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Use `terraform output bootstrap_brokers_sasl_iam` for the client bootstrap string. Attach the `client_security_group_id` output to producers and consumers. Client settings are in [../kafka/README.md](../kafka/README.md).

## What it does NOT do

- It does not create topics. MSK topics are created with Kafka admin tooling (for example `kafka-topics.sh` or an admin client). The `market-events` topic definition is in [../kafka/README.md](../kafka/README.md).
- It does not create IAM policies or roles for clients. Grant them per [MSK IAM access control](https://docs.aws.amazon.com/msk/latest/developerguide/iam-access-control.html).
- It does not create compute for the producer or consumer, an internet gateway, NAT or VPN.
- It does not create the KMS key, SNS topic or private CA. Pass existing ARNs.
- It does not configure a remote state backend.
- Alarm thresholds are starting points. Consumer-group lag metrics depend on the monitoring level and an active group, so verify the `MaxOffsetLag` alarm against the current MSK documentation.

## Cleanup

```bash
cd aws/terraform
terraform destroy
```

MSK clusters and their EBS storage incur cost while they exist. Check the destroy plan before confirming.

## See also

- [MSK notes](../docs/msk.md)
- [Networking](../docs/networking.md)
- [Security](../docs/security.md)
- [Observability](../docs/observability.md)
- [Kafka to Event Hubs migration](../migration/kafka-to-event-hubs.md)
- [Kafka topic and client config](../kafka/README.md)
