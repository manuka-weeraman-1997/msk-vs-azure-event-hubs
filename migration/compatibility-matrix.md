# Compatibility matrix: Amazon MSK and Azure Event Hubs

Amazon MSK is managed Apache Kafka. Azure Event Hubs is a managed event streaming service that exposes a Kafka-compatible endpoint. The two are not equivalent. Where behaviour depends on tier, version or configuration, this table says "Verify in current docs" instead of asserting. Official references: [Event Hubs for Apache Kafka](https://learn.microsoft.com/azure/event-hubs/azure-event-hubs-apache-kafka-overview), [Amazon MSK](https://docs.aws.amazon.com/msk/latest/developerguide/what-is-msk.html), [Apache Kafka](https://kafka.apache.org/documentation/).

| Capability | Amazon MSK / Kafka | Azure Event Hubs | Notes |
|---|---|---|---|
| Kafka protocol | Native Apache Kafka brokers | Kafka-compatible endpoint on the namespace | The endpoint requires Standard tier or above. Supported Kafka client versions: verify in current docs. |
| Other protocols | Kafka protocol | AMQP and HTTPS in addition to Kafka | Using AMQP or the Event Hubs SDK means application changes. |
| Topic | Kafka topic `market-events` | Event hub `market-events` inside a namespace | Topic maps to event hub. A namespace is roughly the cluster-level container, conceptually only. |
| Partitions | Configurable per topic | Set when the event hub is created | Whether and how the count can change after creation depends on tier: verify in current docs. |
| Consumer groups | Kafka consumer groups, offsets stored by the cluster | Consumer groups per event hub, including `$Default` | Maximum groups per event hub depends on tier: verify in current docs. Offset handling with Kafka clients: verify in current docs. |
| Producer API | Kafka producer | Kafka producer (compatible endpoint), AMQP or HTTPS clients, Event Hubs SDKs | Kafka clients usually need only configuration changes. Test your client version and settings. |
| Consumer API | Kafka consumer | Kafka consumer, or Event Hubs SDK consumers | Rebalance and group behaviour can differ. Test under failure. |
| Ordering | Per partition, by key | Per partition, by partition key | Use `symbol` as key on both. Ordering across partitions is not guaranteed on either. |
| Replication model | Kafka replication, replication factor, ISR, `min.insync.replicas` | Managed by the service, not exposed as Kafka settings | Replication factor and ISR are Kafka internals that Event Hubs does not expose. Durability options (for example zone redundancy): verify in current docs. |
| Delivery semantics | At-least-once by default, idempotent producer and transactions available | At-least-once is the safe assumption | Idempotence and transactions support: verify in current docs. Design consumers to be idempotent. |
| Authentication | TLS with SASL (SCRAM, IAM) or mutual TLS | TLS with Microsoft Entra ID (OAuth) or SAS | Kafka clients use SASL settings on both. Entra ID support with Kafka clients: verify in current docs. |
| Authorization | IAM policies or Kafka ACLs | Azure RBAC roles or SAS policies | Roles and scopes differ. Re-design, do not translate one-to-one. |
| Networking | VPC, private subnets, security groups | VNet, Private Endpoint, Private DNS, network rules | Private Endpoint availability by tier: verify in current docs. |
| Encryption in transit | TLS | TLS | Verify minimum TLS version settings on both. |
| Encryption at rest | Managed, with KMS key options | Managed, with customer-managed key options on some tiers | Verify in current docs. |
| Monitoring | Amazon CloudWatch metrics and broker logs | Azure Monitor metrics, diagnostic settings, logs | Metric names and semantics differ. Rebuild dashboards and alerts. Consumer lag: verify how to measure on each side. |
| Retention | Per topic, time or size based, broker configs | Per event hub, limits depend on tier | 24 hours in examples. Maximum retention by tier: verify in current docs. |
| Log compaction | Supported (`cleanup.policy=compact`) | Verify in current docs | Check tier and current status before relying on it. |
| Transactions | Supported | Verify in current docs | Do not assume exactly-once across topics or event hubs. |
| Kafka Streams | Library runs against Kafka | Verify in current docs | Depends on transactions, compaction and internal topics. Test early. |
| Kafka Connect | Self-managed or MSK Connect | Verify in current docs | Check current guidance for connectors against the Kafka endpoint. |
| Admin operations | Full Kafka admin API and broker configs | Subset through the Kafka endpoint, plus Azure control plane (ARM, Terraform) | Manage event hubs as infrastructure as code. Topic-level and broker-level config support: verify in current docs. |
| Message size | Configurable (`message.max.bytes`) | Tier-dependent limit | Verify the current limit and compare with your largest events. |
| Headers | Kafka record headers | Mapped to properties on the event | Verify behaviour across protocols (Kafka produce, AMQP consume). |
| Schema registry | Not part of Kafka. AWS Glue Schema Registry or Confluent are separate | Azure Schema Registry is a separate feature | Verify tier availability and client library support. |
| Capture and archival | Via connectors (for example S3 sink) | Event Hubs Capture to storage, tier-dependent | Verify tier and format in current docs. |
| Scaling model | Choose broker type, size and count, add partitions and storage | Throughput, processing or capacity units depending on tier | Check the current pricing and scaling pages. Do not translate broker counts to units by formula. |
| Tier requirements | Provisioned or serverless MSK | Kafka endpoint needs Standard tier or above | Other features (Private Endpoint, Capture, larger retention) vary by tier: verify in current docs. |
| Multi-region | Separate cluster plus replication tooling | Geo-replication or disaster recovery options, tier-dependent | Verify current features and consistency guarantees. |

## See also

- [Kafka to Event Hubs migration guide](./kafka-to-event-hubs.md)
- [Migration architecture](./architecture.md)
- [MSK vs Event Hubs comparison](../docs/comparison.md)
- [Azure Event Hubs](../docs/azure-event-hubs.md)
- [Amazon MSK](../docs/msk.md)
