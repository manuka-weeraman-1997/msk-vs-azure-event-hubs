# Amazon MSK vs Azure Event Hubs

A technical comparison for the `market-events` pipeline. MSK is managed Apache Kafka. Event Hubs is a managed event streaming service with a Kafka-compatible endpoint. They solve the same problem with different models, so treat the mapping as conceptual, not 1:1.

Details that change often (tiers, limits, quotas, pricing, feature support) are deliberately not quoted. Check [Amazon MSK](https://docs.aws.amazon.com/msk/latest/developerguide/what-is-msk.html) and [Azure Event Hubs](https://learn.microsoft.com/azure/event-hubs/event-hubs-about) for current values.

| Area | Amazon MSK | Azure Event Hubs |
|---|---|---|
| Model | Managed Apache Kafka cluster of brokers | Managed event streaming service; namespace containing event hubs |
| Stream name | Topic | Event hub (a Kafka topic maps to an event hub) |
| Protocol | Kafka protocol | Kafka protocol (compatible endpoint, Standard tier or above, verify), AMQP, HTTPS |
| Partitions | Set per topic; can be increased later (key mapping changes) | Set per event hub; limits and later changes are tier dependent |
| Replication | Configurable replication factor, ISR and `min.insync.replicas` | Handled by the service; replication and ISR are not exposed |
| Ordering | Per partition | Per partition |
| Consumer groups | Kafka consumer groups, offsets stored in Kafka | Consumer groups per event hub; Kafka clients use the Kafka group protocol on the compatible endpoint |
| Auth | TLS, SASL/IAM, SASL/SCRAM, mutual TLS | TLS with Microsoft Entra ID (RBAC, Managed Identity) or SAS |
| Networking | VPC, private subnets, security groups | VNet, Private Endpoint, Private DNS |
| Scaling | Choose broker count, type and storage; add partitions; scale consumers | Tier capacity units; partitions bound consumer parallelism |
| Retention | Per topic, time or size based, under your control | Bounded and tier dependent; Capture to storage for longer term |
| Monitoring | CloudWatch metrics and logs | Azure Monitor metrics and diagnostic logs |
| Operations | You own topics, configs, partition planning and lag; AWS owns broker infrastructure | You own the event hub design, access and consumers; Azure owns the engine, with less low-level control |
| Ecosystem | Full Kafka ecosystem (Connect, Streams, Schema Registry options, admin tooling) at the Kafka version in use | Azure-native SDKs, Capture, Schema Registry, Azure integrations; Kafka ecosystem support varies by feature |

## How to choose

Choose MSK when you need full Kafka behaviour and control: broker and topic configuration, the Kafka Admin API, Kafka Streams or Connect depending on tight Kafka version alignment, or you already run on AWS.

Choose Event Hubs when you are on Azure and want a lower-operations service, native Azure identity and integration, and your Kafka usage fits the compatible endpoint.

Moving between them with Kafka clients is mostly a configuration change (endpoint, auth, topic naming). Verify advanced features first. See [migration](../migration/kafka-to-event-hubs.md) and the [compatibility matrix](../migration/compatibility-matrix.md).

The decision usually follows where your workloads and identities already live. Test with your real client code before committing.

## See also

- [Amazon MSK](./msk.md)
- [Azure Event Hubs](./azure-event-hubs.md)
- [Architecture](./architecture.md)
- [Cost considerations](./cost-considerations.md)
- [Compatibility matrix](../migration/compatibility-matrix.md)
