# Migration notes

This folder helps you evaluate moving a Kafka or Amazon MSK workload to Azure Event Hubs. It is an evaluation guide, not a runbook. Event Hubs exposes a Kafka-compatible endpoint, but it is not Apache Kafka, and some Kafka features behave differently or are unavailable. Always verify against the current Microsoft documentation before you commit to a plan.

## Reading order

1. [Migration architecture](./architecture.md): the source and target systems and how traffic moves between them during a migration.
2. [Kafka to Event Hubs migration guide](./kafka-to-event-hubs.md): what stays the same, what changes, a feature checklist, a phased plan and risks.
3. [Compatibility matrix](./compatibility-matrix.md): capability-by-capability comparison with "Verify in current docs" where behaviour depends on tier or version.

## Example system

All files use the same market-data pipeline: topic or event hub `market-events` with 4 partitions, partition key `symbol`, 24 hour retention, consumer group `search-service`. The MSK cluster is `streaming-msk` (`us-east-1`) and the Event Hubs namespace is the placeholder `streaming-prod` (`eastus`). Real namespace names are globally unique.

## See also

- [Diagrams](../diagrams/architecture.md)
- [MSK vs Event Hubs comparison](../docs/comparison.md)
- [Security](../docs/security.md)
- [Networking](../docs/networking.md)
- [Production checklist](../docs/production-checklist.md)
