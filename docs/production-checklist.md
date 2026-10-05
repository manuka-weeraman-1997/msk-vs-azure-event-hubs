# Production checklist

Use this before taking the market-data pipeline live on either platform. Items apply to both unless marked (MSK) or (Event Hubs). The mapping is conceptual, not 1:1, so some items have different mechanics on each side.

## Availability and resilience

- [ ] High availability: the platform spans failure domains. (MSK) brokers across multiple Availability Zones, replication factor and minimum in-sync replicas set deliberately. (Event Hubs) review the zone-redundancy and availability options for your tier in the current docs.
- [ ] Multi-AZ: client applications also run across zones, so a zone failure does not stop producers or consumers.
- [ ] Disaster recovery: a documented recovery target and approach, including a region-level failure. Check what geo-recovery or replication options exist for your platform and tier, and test the procedure.
- [ ] Backup and recovery: decide what is recoverable from the stream (replay within retention) and what needs a separate copy (for example Capture on Event Hubs, or a sink to object storage). Test a restore or replay.

## Data model and processing

- [ ] Partition strategy: `market-events` has 4 partitions with `symbol` as the partition key. Check for key skew and plan growth, since changing partition counts later can affect ordering and mapping.
- [ ] Consumer scaling: at most one active consumer per partition within a group (C1..C4 for P0..P3). Scale by adding partitions before adding consumers beyond that.
- [ ] Consumer lag: per-group lag is measured, and a lag threshold is defined.
- [ ] Retry handling: bounded retries with backoff for transient failures. Producers use idempotent or retry-safe settings where the platform supports them (verify on Event Hubs).
- [ ] Dead-letter strategy: where an event that cannot be processed goes (for example a separate topic or event hub, or a store), with a reprocess path. Kafka has no built-in dead-letter queue, so this is application design.
- [ ] Schema management: a versioned event schema (see `examples/event-schema.json`), a compatibility policy, and a registry or review process. Check which schema registry options exist on each platform.
- [ ] Idempotent consumers: processing the same event twice is safe.
- [ ] Retention: set to match replay needs (24 hours in the examples) and confirmed against storage and cost.

## Security

- [ ] Authentication: identity-based. (MSK) IAM roles with SASL/IAM. (Event Hubs) Microsoft Entra ID with managed identities. SAS only by exception.
- [ ] Authorization: least privilege per application, scoped to `market-events` and the `search-service` group. (Event Hubs) Data Sender and Data Receiver roles, not Data Owner.
- [ ] TLS: enforced in transit. Plaintext listeners disabled. Certificate and truststore handling documented.
- [ ] Private networking: (MSK) private subnets and tight security groups. (Event Hubs) Private Endpoint, Private DNS zone linked to every client VNet, public network access disabled.
- [ ] DNS verified from every client network: names resolve to private addresses.
- [ ] Secrets management: no secrets in Git. Secrets Manager or Key Vault where any secret remains. Rotation defined.

## Operations

- [ ] Monitoring: dashboards for throughput in and out, consumer lag, errors, throttling, storage or capacity. See [Observability](./observability.md).
- [ ] Alerting: alerts on lag, error rates, throttling, and absence of traffic. Each alert has an owner and a runbook entry in [Troubleshooting](./troubleshooting.md).
- [ ] Audit and diagnostic logs: sent to a central workspace with defined retention.
- [ ] Infrastructure as code: all resources defined in Terraform and reviewed through pull requests. State stored remotely and locked. See [aws](../aws/README.md) and [azure](../azure/README.md).
- [ ] Environments: dev, test and prod separated, created from the same code.
- [ ] Upgrades and maintenance: understood and scheduled. (MSK) Kafka version and patching. (Event Hubs) service-managed, but client library upgrades remain yours.

## Capacity and testing

- [ ] Capacity planning: expected and peak events per second, event size, consumer groups and retention are written down. (MSK) broker size, count and storage. (Event Hubs) throughput or processing unit capacity for the tier, and scaling limits from the current docs.
- [ ] Cost model: estimated with the official calculators and reviewed. See [Cost considerations](./cost-considerations.md).
- [ ] Load testing: run at and above peak with realistic keys and consumer behaviour. Measure lag, latency and throttling, not just producer success.
- [ ] Failure testing: restart consumers, fail a zone or broker where you can, and break DNS in a test environment. Confirm alerts fire.
- [ ] Client settings reviewed: timeouts, batch size, acks and poll intervals tuned for each platform.

## Migration only

- [ ] Cutover plan, rollback plan and a parallel-run period are agreed. See the [migration guide](../migration/kafka-to-event-hubs.md).
- [ ] Compatibility gaps checked against the [compatibility matrix](../migration/compatibility-matrix.md).

## See also

- [Security](./security.md)
- [Networking](./networking.md)
- [Observability](./observability.md)
- [Cost considerations](./cost-considerations.md)
- [Migration guide](../migration/kafka-to-event-hubs.md)
