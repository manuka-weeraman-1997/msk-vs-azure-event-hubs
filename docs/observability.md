# Observability: CloudWatch vs Azure Monitor

A streaming system fails quietly: events back up, consumers fall behind, a partition gets hot. You need signals for each of those before production. The mapping below is conceptual, not 1:1.

## AWS: Amazon MSK with CloudWatch

[Amazon CloudWatch](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html) is the monitoring service MSK publishes to.

- Broker and cluster metrics: published to CloudWatch under the MSK namespace. Examples that exist include `BytesInPerSec`, `BytesOutPerSec`, `MessagesInPerSec`, `CpuUser`, `KafkaDataLogsDiskUsed`, `UnderReplicatedPartitions`, `OfflinePartitionsCount` and `ActiveControllerCount`. The monitoring level you choose on the cluster controls how many metrics (and at what granularity, for example per broker or per topic) are published. Check the MSK docs for the full list per level.
- Consumer lag: MSK publishes consumer-group lag metrics such as `MaxOffsetLag`, `SumOffsetLag` and `EstimatedMaxTimeLag` at suitable monitoring levels. Verify exact names and levels in the docs.
- Open monitoring: optionally exposes Prometheus-format metrics for Kafka and the node, if you run Prometheus and Grafana.
- Logs: broker logs can be delivered to CloudWatch Logs, S3 or Kinesis Data Firehose.
- Alarms: CloudWatch alarms on any metric, notifying through SNS.
- Audit: AWS CloudTrail records control-plane API calls.

## Azure: Event Hubs with Azure Monitor

[Azure Monitor](https://learn.microsoft.com/azure/azure-monitor/overview) is the platform for metrics, logs and alerts for Event Hubs.

- Metrics: Event Hubs publishes namespace-level metrics to Azure Monitor Metrics. Examples that exist include `IncomingMessages`, `OutgoingMessages`, `IncomingBytes`, `OutgoingBytes`, `ThrottledRequests`, `ServerErrors` and `UserErrors`. Look up the full list and the available dimensions (such as event hub name) in the Event Hubs monitoring reference.
- Logs: diagnostic settings send resource logs (for example operational logs and, where available, Kafka-related or runtime audit logs) to a Log Analytics workspace, a storage account or an event hub. Categories vary, so check the current docs.
- Log Analytics: query logs with Kusto Query Language (KQL), build workbooks, join with application telemetry.
- Alerts: Azure Monitor alert rules on metrics or log queries, routed through action groups (email, webhook, ticketing and so on).
- Activity Log: control-plane operations on the namespace.

Important difference: Event Hubs does not expose Kafka broker internals such as under-replicated partitions or controller state. Replication and broker health are managed by the service. Your alerts focus on throughput, errors, throttling and consumer progress.

## Signals that matter in production

| Signal | Why it matters | Amazon MSK (CloudWatch) | Azure Event Hubs (Azure Monitor) |
| --- | --- | --- | --- |
| Throughput in | Detect traffic drops or spikes from the Market Data Application | `BytesInPerSec`, `MessagesInPerSec` | `IncomingMessages`, `IncomingBytes` |
| Throughput out | Confirm consumers are reading | `BytesOutPerSec` | `OutgoingMessages`, `OutgoingBytes` |
| Consumer lag | Consumers falling behind the stream | MSK lag metrics (for example `SumOffsetLag`, `MaxOffsetLag`) or `kafka-consumer-groups.sh` | No built-in lag metric to rely on. Compute lag from the client side: Kafka consumer group offsets, or checkpoint position versus latest sequence number in SDK-based consumers. Check docs for current options |
| Partition / broker health | Loss of capacity or availability | `UnderReplicatedPartitions`, `OfflinePartitionsCount`, `ActiveControllerCount`, CPU | Not exposed as Kafka internals. Watch service health and availability, and `ServerErrors` |
| Errors | Failed produce or consume, auth failures | Broker logs, client-side error metrics | `ServerErrors`, `UserErrors`, diagnostic logs |
| Throttling | Capacity limit reached | Broker CPU and network saturation, client-side throttle metrics | `ThrottledRequests` |
| Storage / retention | Disk filling, retention too short or long | `KafkaDataLogsDiskUsed` and storage metrics | Retention is a setting. Check capacity and size metrics available for your tier in the docs |
| Latency | End-to-end freshness | Client-side produce latency, request time metrics (look up names) | Client-side produce latency. Add an application timestamp (`timestamp` in the event) and measure event age at the consumer |

Where the exact metric name is not given, look it up in the official documentation. Metric availability changes over time and by tier or monitoring level.

## Practical advice

- Measure end-to-end freshness yourself. The event carries `timestamp`. Compare it to the consumer's clock on read and publish the difference as an application metric. This works the same on both platforms.
- Alert on trends and absence, not just thresholds. A producer that goes silent produces no errors, only a flat `IncomingMessages` line.
- Alert on lag for each consumer group (`search-service`, plus `analytics` or `$Default` on Azure) separately.
- Send logs to a central workspace and set retention deliberately, since log storage is a cost driver (see [Cost considerations](./cost-considerations.md)).
- Define dashboards and alarms as code next to the infrastructure. See `monitoring.tf` in [aws](../aws/README.md) and [azure](../azure/README.md).
- Tie each alert to a runbook entry in [Troubleshooting](./troubleshooting.md).

## See also

- [Troubleshooting](./troubleshooting.md)
- [Production checklist](./production-checklist.md)
- [Cost considerations](./cost-considerations.md)
- [Data flow](./data-flow.md)
- [Amazon MSK](./msk.md)
