# Cost considerations

This document lists cost drivers, not prices. Pricing models, tiers and rates change, so no figures appear here. Estimate with the official calculators and confirm against current pricing pages:

- AWS: https://calculator.aws/
- Azure: https://azure.microsoft.com/pricing/calculator/

The comparison is conceptual, not 1:1. The two services are billed along different dimensions, so a like-for-like number needs a workload model, not a rate card.

## Amazon MSK cost drivers

| Driver | What to consider |
| --- | --- |
| Broker instances | Broker type, size and count. Brokers are billed while they exist, regardless of traffic. A Multi-AZ cluster has brokers in several zones |
| Storage | Provisioned storage per broker. Driven by throughput, retention (24 hours in our examples), and the replication factor |
| Data transfer | Cross-AZ traffic from replication and from consumers reading from a leader in another zone. Traffic leaving AWS or crossing regions |
| Provisioned resources | Provisioned throughput or storage options, if used. Other MSK deployment types are billed differently, so check current docs |
| Monitoring | Higher monitoring levels publish more metrics. CloudWatch metrics, alarms, dashboards and log ingestion and retention are separate charges. Open monitoring adds the cost of running your own Prometheus stack |
| Networking components | NAT gateways, VPC endpoints, Transit Gateway or VPN used to reach the cluster |
| Operations | Engineering time for upgrades, capacity planning and patch windows |

## Azure Event Hubs cost drivers

| Driver | What to consider |
| --- | --- |
| Throughput and capacity | Capacity is bought as throughput units or processing units depending on tier, or as dedicated capacity for the highest tier. Check the current tier documentation for which applies |
| Ingestion | Some tiers bill per ingress event or per volume, in addition to capacity |
| Retention | Retention beyond the tier's included period, or larger stored volume, can add cost depending on the tier |
| Capture | Capture writes events to storage. You pay for the feature (depending on tier) and for the storage account, its transactions and its retention |
| Partitions | Partition count affects parallelism and, on some tiers, limits. Verify current docs |
| Networking | Private Endpoint hours and data processed, Private DNS zones and queries, VNet connectivity, and cross-region or outbound data transfer |
| Monitoring | Log Analytics ingestion and retention, metric alert rules, and diagnostic setting destinations |
| Auto-inflate or scaling settings | If enabled, spend can rise with load. Review the ceiling you set |

## Comparing the two models

- MSK is closer to "pay for the cluster you provision". Cost tracks broker count, size and storage, and does not drop much when traffic drops.
- Event Hubs is closer to "pay for the capacity tier and usage the tier measures". The exact balance between fixed and usage-based depends on the tier.
- Retention and replication are explicit cost levers on MSK. On Event Hubs, replication is handled by the service and retention rules depend on tier.
- Over-provisioning is the most common cost error on both. Under-provisioning shows up as throttling (see [Troubleshooting](./troubleshooting.md)).

## Hidden and indirect costs

- Cross-cloud data transfer during a migration, when both systems run in parallel (see [Networking](./networking.md)).
- Duplicate environments: running MSK and Event Hubs side by side until cutover.
- Dev and test environments left running. Use IaC to create and destroy them (see [aws](../aws/README.md) and [azure](../azure/README.md)).
- Log and metric retention that nobody reviews.
- Replay and backfill traffic after an incident.

## How to estimate

1. Model the workload: events per second, average event size (the `market-price` event is small), peak versus average, number of consumer groups, retention.
2. Run it through both calculators with your region (`us-east-1`, `eastus` in the examples) and the tier you intend to use.
3. Add networking and monitoring, which are easy to omit.
4. Validate with a load test and a small real bill, then revise.
5. Set budgets and alerts in AWS Budgets and Azure Cost Management.

## See also

- [Comparison](./comparison.md)
- [Production checklist](./production-checklist.md)
- [Observability](./observability.md)
- [Amazon MSK](./msk.md)
- [Azure Event Hubs](./azure-event-hubs.md)
