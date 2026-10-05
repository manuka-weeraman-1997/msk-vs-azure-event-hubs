# Consumer

A Python consumer-group member that reads `market-price` events from the `market-events` topic (Amazon MSK) or event hub (Azure Event Hubs). The client code is identical on both platforms. Only configuration changes. The service mapping is conceptual, not 1:1.

## What it does

- Joins the consumer group `search-service` (override with `KAFKA_GROUP_ID`).
- Logs which partitions this member owns from the `on_assign` and `on_revoke` callbacks.
- Disables auto-commit and commits offsets manually after each event is processed (at-least-once). Your processing code must be idempotent.
- Skips and logs undecodable messages, logs non-fatal errors, and stops on fatal ones (authentication or authorization failures).
- On SIGINT or SIGTERM it stops polling, commits, and closes the consumer so the group rebalances quickly.

In the pipeline diagram this is the **Consumer group** and **Consumer(s)** stage, before the downstream search, analytics or application systems.

## One consumer per partition

The topic has 4 partitions (P0 to P3). Within one group each partition is owned by exactly one member. Start four copies and each logs a single partition:

```bash
# four terminals, same environment
python consumer.py
```

```json
{"msg":"partitions assigned","owned":[2],"topic":"market-events"}
```

With fewer members, some own several partitions. A fifth member receives nothing until another leaves, so members beyond the partition count do not add throughput. Different groups (for example `analytics`) read the full stream independently. Details: [../kafka/README.md](../kafka/README.md).

## Run against Amazon MSK

Needs IAM permissions such as `kafka-cluster:Connect`, `kafka-cluster:ReadData`, `kafka-cluster:DescribeTopic`, and group permissions (`kafka-cluster:AlterGroup`, `kafka-cluster:DescribeGroup`).

```bash
cd consumer
pip install -r requirements.txt
export KAFKA_PLATFORM=msk
export AWS_REGION=us-east-1
export KAFKA_BOOTSTRAP_SERVERS="<broker-1>:9098,<broker-2>:9098,<broker-3>:9098"
python consumer.py
```

## Run against Azure Event Hubs

Needs a Standard-tier-or-above namespace, the `market-events` event hub, and a connection string with Listen rights. The Kafka `group.id` maps to an Event Hubs consumer group.

```bash
cd consumer
pip install -r requirements.txt
export KAFKA_PLATFORM=eventhubs
export EVENTHUBS_NAMESPACE=<namespace>        # e.g. streaming-prod (placeholder)
export EVENTHUBS_CONNECTION_STRING="<connection-string-with-Listen-rights>"
python consumer.py
```

Microsoft Entra ID (OAuth) is the preferred option for Event Hubs where your Kafka client supports it. This sample uses the connection string path for simplicity. See [../docs/security.md](../docs/security.md).

## Configuration

Settings come from an optional YAML file (`CONFIG_FILE`) and environment variables. Environment variables override the file. Start from `config/config.example.yaml`.

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `KAFKA_PLATFORM` | yes | none | `msk` or `eventhubs` |
| `KAFKA_BOOTSTRAP_SERVERS` | MSK; Event Hubs if no namespace | none | Broker list. MSK IAM uses port 9098, Event Hubs uses 9093 |
| `EVENTHUBS_NAMESPACE` | Event Hubs, if no bootstrap set | none | Builds `<namespace>.servicebus.windows.net:9093` |
| `AWS_REGION` | MSK | none | Region used to sign IAM tokens |
| `EVENTHUBS_CONNECTION_STRING` | Event Hubs | none | Secret. Environment only, never read from the file, never logged |
| `KAFKA_GROUP_ID` | no | `search-service` | Consumer group |
| `KAFKA_TOPIC` | no | `market-events` | Topic or event hub name |
| `KAFKA_AUTO_OFFSET_RESET` | no | `earliest` | Start position for a group with no committed offsets |
| `KAFKA_CLIENT_ID` | no | hostname | Client identifier |
| `CONFIG_FILE` | no | none | Path to a YAML file |
| `LOG_LEVEL` | no | `INFO` | Python log level |

Exit codes: `0` clean shutdown, `1` fatal error, `2` configuration error.

## See also

- [../producer/README.md](../producer/README.md)
- [../kafka/README.md](../kafka/README.md)
- [../docs/msk.md](../docs/msk.md)
- [../docs/azure-event-hubs.md](../docs/azure-event-hubs.md)
- [../docs/security.md](../docs/security.md)
- [../migration/kafka-to-event-hubs.md](../migration/kafka-to-event-hubs.md)
