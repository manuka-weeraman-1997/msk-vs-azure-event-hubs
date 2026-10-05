# Kafka topic design

This page describes the `market-events` topic (Amazon MSK) and event hub (Azure Event Hubs) used by the sample producer and consumer. The two services are conceptually similar but not 1:1: a Kafka topic corresponds to an event hub, and Event Hubs exposes a Kafka-compatible endpoint rather than being Apache Kafka itself.

## Design

| Property | Value | Why |
| --- | --- | --- |
| Name | `market-events` | One stream of market-price events |
| Partitions | 4 | Upper bound on parallel consumers in one group |
| Message key | `symbol` | Same symbol always maps to the same partition |
| Retention | 24 hours (1 day) in these examples | Enough to replay a day; tune per requirement |
| Ordering | Per partition only | No ordering across partitions |
| Consumer group | `search-service` | Azure also shows `$Default` and `analytics` |

The declarative definition lives in [topics/market-events.yaml](./topics/market-events.yaml). It is documentation, not something a tool applies automatically.

## Keys and ordering

The producer hashes the key (`symbol`) to choose a partition. Every `AAPL` event goes to the same partition, so a consumer sees them in the order they were written. Events for different symbols can be on different partitions and are not ordered relative to each other. If you change the partition count later, the key-to-partition mapping changes, so plan the count up front.

## How consumer-group assignment works with 4 consumers

```text
Topic market-events:   P0     P1     P2     P3
Group search-service:  C1     C2     C3     C4      one partition each
```

- Members that share a `group.id` split the partitions. Each partition has exactly one owner in the group at a time.
- With 4 members on 4 partitions, each owns one. With 2 members, each owns two. With 5 members, one sits idle.
- When a member joins, leaves or stops heart-beating, the group rebalances and partitions are reassigned. The consumer in this repo logs this from `on_assign` and `on_revoke`.
- Each group tracks its own committed offsets. `search-service` and `analytics` each read every event independently.

## Create the topic on Amazon MSK

Use the Kafka CLI from a host with network access to the brokers and the IAM auth library on its classpath. Copy [configs/client.properties.example](./configs/client.properties.example) to `client.properties` and fill the MSK IAM section.

```bash
kafka-topics.sh --bootstrap-server "<broker-1>:9098" \
  --command-config client.properties \
  --create --topic market-events \
  --partitions 4 --replication-factor 3 \
  --config retention.ms=86400000
```

Replication factor 3 assumes a three-broker cluster across three Availability Zones. Match it to your cluster. Verify with:

```bash
kafka-topics.sh --bootstrap-server "<broker-1>:9098" \
  --command-config client.properties --describe --topic market-events
```

Topic management also needs IAM permissions such as `kafka-cluster:CreateTopic`. See [../docs/msk.md](../docs/msk.md).

## Create the event hub on Azure Event Hubs

Do not create the topic with Kafka tooling. The event hub is created by Terraform (see `azure/terraform/event-hubs.tf`) or in the Azure portal, with name `market-events`, 4 partitions and a message retention of 1 day. The Kafka client then just uses the event hub name as the topic name.

Differences to expect: replication and in-sync replicas are Kafka internals that Event Hubs does not expose, broker-level configs do not apply, and some admin operations differ. Partition count changes and some Kafka features depend on tier. Check the current Microsoft documentation: [Event Hubs for Apache Kafka](https://learn.microsoft.com/azure/event-hubs/azure-event-hubs-apache-kafka-overview).

## See also

- [../producer/README.md](../producer/README.md)
- [../consumer/README.md](../consumer/README.md)
- [../docs/msk.md](../docs/msk.md)
- [../docs/azure-event-hubs.md](../docs/azure-event-hubs.md)
- [../migration/kafka-to-event-hubs.md](../migration/kafka-to-event-hubs.md)
