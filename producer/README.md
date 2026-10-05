# Producer

A small Python producer that publishes `market-price` events to the `market-events` topic (Amazon MSK) or event hub (Azure Event Hubs). The client code is identical on both platforms. Only configuration changes. The mapping between the two services is conceptual, not 1:1: see [../docs/comparison.md](../docs/comparison.md) for the differences.

## What it does

- Generates events such as `{"event_type":"market-price","symbol":"AAPL","price":227.31,"timestamp":"2026-10-05T08:00:00Z"}` for a few symbols with jittered prices.
- Serializes to JSON and uses `symbol` as the partition key, so all events for one symbol land on one partition and stay ordered.
- Logs every delivery report (partition and offset) as structured JSON.
- Retries transient errors (client-level retries, local queue back-pressure), flushes on exit, and exits non-zero if any message failed.
- Refuses to start with a clear message if a required value is missing. Secrets are redacted in logs.

In the pipeline diagram this is the **Producer** stage, between the Market Data Application and the network/security layer.

## Run against Amazon MSK

Prerequisites: a network path to the brokers (same VPC, peering, VPN or Direct Connect), AWS credentials that allow `kafka-cluster:Connect` and `kafka-cluster:WriteData` on the topic, and the topic created (see [../kafka/README.md](../kafka/README.md)).

```bash
cd producer
pip install -r requirements.txt
export KAFKA_PLATFORM=msk
export AWS_REGION=us-east-1
export KAFKA_BOOTSTRAP_SERVERS="<broker-1>:9098,<broker-2>:9098,<broker-3>:9098"
python producer.py --count 20 --rate 5
```

Credentials come from the standard AWS provider chain (environment, shared config, instance or task role).

## Run against Azure Event Hubs

Prerequisites: a Standard-tier-or-above namespace (the Kafka endpoint is not available on Basic), an event hub named `market-events` with 4 partitions, and a connection string with Send rights. Network access to `<namespace>.servicebus.windows.net:9093` (public or through a Private Endpoint).

```bash
cd producer
pip install -r requirements.txt
export KAFKA_PLATFORM=eventhubs
export EVENTHUBS_NAMESPACE=<namespace>        # e.g. streaming-prod (placeholder)
export EVENTHUBS_CONNECTION_STRING="<connection-string-with-Send-rights>"
python producer.py --count 20 --rate 5
```

Microsoft Entra ID (OAuth) is the preferred authentication option for Event Hubs where your Kafka client supports it, because it avoids shared keys. This sample uses the connection string (SAS) path because it is the simplest to run anywhere. See [../docs/security.md](../docs/security.md).

## Configuration

Settings come from an optional YAML file (`CONFIG_FILE`) and environment variables. Environment variables override the file. Start from `config/config.example.yaml`.

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `KAFKA_PLATFORM` | yes | none | `msk` or `eventhubs` |
| `KAFKA_BOOTSTRAP_SERVERS` | MSK; Event Hubs if no namespace | none | Broker list. MSK IAM uses port 9098, Event Hubs uses 9093 |
| `EVENTHUBS_NAMESPACE` | Event Hubs, if no bootstrap set | none | Builds `<namespace>.servicebus.windows.net:9093` |
| `AWS_REGION` | MSK | none | Region used to sign IAM tokens, for example `us-east-1` |
| `EVENTHUBS_CONNECTION_STRING` | Event Hubs | none | Secret. Environment only, never read from the file, never logged |
| `KAFKA_TOPIC` | no | `market-events` | Topic or event hub name |
| `KAFKA_CLIENT_ID` | no | `market-producer` | Client identifier |
| `CONFIG_FILE` | no | none | Path to a YAML file |
| `LOG_LEVEL` | no | `INFO` | Python log level |

CLI flags: `--count N` (default 20, `0` runs until Ctrl+C), `--rate R` events per second (default 5, `0` unthrottled), `--seed S`, `--log-level`.

## Notes

- Delivery is at-least-once with `acks=all`. On MSK the idempotent producer is enabled. On Event Hubs it is disabled in this sample; check the current Microsoft documentation for what your tier supports.
- Exit codes: `0` success, `1` some messages failed or were not flushed, `2` configuration error.

## See also

- [../consumer/README.md](../consumer/README.md)
- [../kafka/README.md](../kafka/README.md)
- [../docs/msk.md](../docs/msk.md)
- [../docs/azure-event-hubs.md](../docs/azure-event-hubs.md)
- [../docs/security.md](../docs/security.md)
- [../migration/kafka-to-event-hubs.md](../migration/kafka-to-event-hubs.md)
