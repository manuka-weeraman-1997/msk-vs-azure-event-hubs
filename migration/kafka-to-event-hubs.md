# Evaluating a move from Kafka or Amazon MSK to Event Hubs

This guide helps you decide whether and how to move a Kafka workload to Azure Event Hubs. It is not a recipe to execute blindly. Event Hubs is a managed event streaming service with a Kafka-compatible endpoint. It is not Apache Kafka, and it does not support every Kafka feature. Verify each item against the [current Microsoft documentation](https://learn.microsoft.com/azure/event-hubs/azure-event-hubs-apache-kafka-overview) for your tier and client versions. The mapping used below is conceptual, not 1:1.

## Current and target state

| Layer | Current (AWS) | Target (Azure) |
|---|---|---|
| Source | Market Data Application | Market Data Application |
| Producer | Kafka producer | Producer (Kafka protocol, AMQP or HTTPS) |
| Network/Security | VPC, security groups, TLS + SASL/IAM | VNet, Private Endpoint, TLS + Entra ID / SAS |
| Platform | Amazon MSK `streaming-msk` | Event Hubs namespace `streaming-prod` (placeholder, real names are globally unique) |
| Stream | Topic `market-events` | Event hub `market-events` |
| Partitions | P0..P3 | P0..P3 |
| Consumer group | `search-service` | `search-service` (also `$Default`, `analytics`) |
| Consumers | C1..C4 | C1..C4 |
| Monitoring | CloudWatch | Azure Monitor |

See [the migration architecture](./architecture.md) for the diagram.

## What can remain unchanged

- Application business logic and the event shape, for example `{"event_type":"market-price","symbol":"AAPL","price":227.31,"timestamp":"2026-10-05T08:00:00Z"}`.
- The partition key (`symbol`) and the one-consumer-per-partition model.
- Consumer group names and the general producer and consumer programming model, if you keep Kafka client libraries.
- Serialization format (JSON, Avro, others), as long as message size stays within the target limit.

## What needs configuration changes

For Kafka clients the usual changes are connection and security settings:

| Setting | Kafka / MSK | Event Hubs Kafka endpoint |
|---|---|---|
| `bootstrap.servers` | MSK broker list | `<namespace>.servicebus.windows.net:9093` (verify the current port and format) |
| `security.protocol` | `SASL_SSL` (or `SSL`) | `SASL_SSL` |
| `sasl.mechanism` | `AWS_MSK_IAM`, `SCRAM-SHA-512` | `PLAIN` with a SAS connection string, or `OAUTHBEARER` with Entra ID (verify current client support) |
| Credentials | IAM role or SCRAM secret | Connection string from a secret store, or Entra ID identity |
| Topic name | `market-events` | Event hub name `market-events` |
| Client tuning | Broker-aligned values | Re-test timeouts, batching and retry settings against the Event Hubs guidance |

Keep secrets out of source control. Use environment variables or a secret store. See `kafka/configs/client.properties.example` for placeholder-style configuration.

## What may require application changes

- Code that uses the Kafka admin API to create topics, change partitions or alter configs.
- Kafka Streams applications, Kafka Connect connectors and any use of transactions or compacted topics (see the checklist).
- IAM-specific authentication libraries that must be replaced.
- Code that depends on broker-side behaviour such as exact rebalance timing or offset reset semantics.
- If you choose the Event Hubs SDK (AMQP or HTTPS) instead of Kafka clients, producers and consumers need rewriting.

## Authentication differences

MSK commonly uses TLS with SASL/IAM, SCRAM or mutual TLS. Event Hubs uses TLS with Microsoft Entra ID (preferred for managed identities and RBAC) or Shared Access Signatures. Authorization moves from IAM policies or Kafka ACLs to Azure RBAC roles or SAS policy rights. Re-design access per producer and consumer, with least privilege, rather than translating policies. See [security](../docs/security.md).

## Networking differences

MSK runs in your VPC with security groups controlling access. Event Hubs is a namespace-level service with a public endpoint by default. Private access uses a Private Endpoint in your VNet plus Private DNS, and network rules can restrict public access. Private Endpoint support depends on tier: verify in current docs. If producers or consumers stay in AWS during migration, you need a path from AWS to Azure, and you must decide whether it is public (restricted) or private (VPN or similar). See [networking](../docs/networking.md).

## Monitoring differences

CloudWatch metrics and broker logs are replaced by Azure Monitor metrics and diagnostic logs. Metric names and meanings differ. Alerts, dashboards and consumer-lag measurement must be rebuilt and tested. Do not assume a one-to-one metric mapping. See [observability](../docs/observability.md).

## Scaling differences

MSK scales by broker type, count, storage and partitions. Event Hubs scales through capacity units whose names and rules depend on tier, plus partition count. Size from measured throughput and the current Microsoft documentation, not from broker counts. Partition count changes after creation depend on tier: verify in current docs. Because the partition key `symbol` determines placement, changing partitions can change key-to-partition mapping and ordering assumptions.

## Retention differences

Kafka retention is configured per topic by time or size. Event Hubs retention is configured per event hub and maximum values depend on tier. The examples use 24 hours. If you need longer replay windows, check the tier limits or use an archival feature (for example Event Hubs Capture, tier-dependent). Retention is not a backup: consider where long-term history lives.

## Kafka feature compatibility checklist

Mark each item as required or not for your workload, then verify it in current Microsoft documentation. Do not treat any entry as supported until you have confirmed it.

| Feature | Question to answer | Status |
|---|---|---|
| Log compaction | Do any topics use `cleanup.policy=compact`? Is it available for your tier? | Verify in current docs |
| Transactions / exactly-once | Do producers use transactions or idempotence? Is it supported for your tier and client version? | Verify in current docs |
| Kafka Streams | Do applications use Streams or its internal topics and state stores? | Verify in current docs |
| Kafka Connect | Which connectors run, and are they supported against the Kafka endpoint? | Verify in current docs |
| Admin API | Which admin calls do tools and apps make (create, alter, describe, delete)? | Verify in current docs |
| Partition count changes | Do you add partitions after launch? Is that possible on your tier? | Verify in current docs |
| Consumer-group behaviour | Rebalancing, static membership, offset commit and reset behaviour | Verify in current docs and test |
| Message size | Largest event versus the tier limit | Verify in current docs |
| Headers | Are record headers used, and are they preserved for all consumer protocols? | Verify in current docs |
| Retention and replay | Required retention versus the tier maximum | Verify in current docs |
| Schema registry | Which registry is used, and what is the replacement? | Verify in current docs |
| Client versions | Are your Kafka client versions supported by the endpoint? | Verify in current docs |

Replication factor and in-sync replicas are Kafka internals that Event Hubs does not expose. Durability is a property of the managed service and its tier or redundancy options.

## Operational differences

- Create and change event hubs through infrastructure as code (Terraform AzureRM or ARM), not ad hoc admin API calls.
- There are no brokers to patch, resize or rebalance, and no partition reassignment tooling.
- Quotas and throttling apply at namespace level, so one noisy producer can affect others in the same namespace. Check current limits.
- Incident runbooks, on-call alerts and access reviews need rewriting for Azure.
- The cost model changes from broker hours and storage to capacity units and feature charges. Check the current pricing page rather than estimating.

## Phased plan

1. **Inventory.** List topics, partitions, retention, configs, producers, consumers, consumer groups, client libraries and versions, throughput, message sizes, and any Streams, Connect or transactional usage. Complete the checklist above.
2. **Proof of concept.** Run a representative producer and consumer against a non-production namespace on the required tier. Test failure cases: consumer restart, rebalance, throttling.
3. **Recreate topics as event hubs from code.** Define each topic as an event hub (name, partition count, retention, consumer groups) in Terraform. Review in pull requests. Do not create them by hand.
4. **Dual-write or mirror (conceptual).** Either producers write to both platforms, or a replication process copies records from MSK to Event Hubs. MirrorMaker-style replication may or may not be a supported approach for this target. Verify the supported approach in the current Microsoft and Apache Kafka documentation before designing around it. Dual-write risks divergence and double effects, so make consumers idempotent.
5. **Validate.** Compare record counts, key-to-partition ordering, latency, consumer lag and error rates between platforms. Run the downstream search and analytics consumers against the target in a shadow mode.
6. **Cut over.** Choose one order:
   - Consumers first: consumers start reading from the target (which is receiving mirrored or dual-written data), then producers switch. Lower risk of lost reads, but consumers must handle the offset starting point and possible duplicates.
   - Producers first: producers switch to the target, then consumers drain the source and move. Simple for new data, but consumers must read from two places until the source is drained, and ordering across the switch needs care.

   Prefer the order that keeps the least ambiguity for your ordering and duplication requirements. Use a change window and a clear stop condition.
7. **Roll back.** Keep the source platform running and the replication or dual-write path active until the target is proven. Define the rollback trigger and the reverse path in advance, for example switch producers back and let consumers resume from a recorded timestamp. Rollback is only straightforward before you stop writing to the source.
8. **Decommission.** After an agreed observation period, remove the source resources and stale credentials.

## Risks

- A required Kafka feature is unsupported or tier-gated, discovered late.
- Offsets do not carry over, causing duplicate or missed processing at cut-over.
- Ordering differences if partition counts or key hashing change.
- Throttling or tier limits reached under real load.
- Message size or retention limits lower than the source.
- Security model errors when moving from IAM to Entra ID and RBAC, including leaked SAS strings.
- Cross-cloud network paths that add latency, cost or unintended public exposure.
- Monitoring gaps because dashboards and alerts were not rebuilt before cut-over.

## See also

- [Migration architecture](./architecture.md)
- [Compatibility matrix](./compatibility-matrix.md)
- [MSK vs Event Hubs comparison](../docs/comparison.md)
- [Security](../docs/security.md)
- [Production checklist](../docs/production-checklist.md)
