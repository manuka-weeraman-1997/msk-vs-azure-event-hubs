# Azure: Event Hubs with Terraform

Terraform for the Azure side of the market-data pipeline. It builds an Event Hubs namespace with a `market-events` event hub (4 partitions, 1 day retention), consumer groups, optional private networking, optional Microsoft Entra ID role assignments and Azure Monitor alerting. The AWS counterpart is in [../aws/README.md](../aws/README.md). The mapping between the two is conceptual, not 1:1.

## What it builds

| File | Resources |
|------|-----------|
| `main.tf` | Resource group (created or referenced), role assignments for Data Sender and Data Receiver |
| `event-hubs.tf` | Event Hubs namespace, event hub per entry in `topics`, consumer groups |
| `networking.tf` | Optional: VNet, subnet, Private Endpoint, private DNS zone `privatelink.servicebus.windows.net`, VNet link |
| `monitoring.tf` | Log Analytics workspace, diagnostic setting, action group, alerts on `ThrottledRequests` and `ServerErrors` |

The `$Default` consumer group exists automatically on each event hub, so only `search-service` and `analytics` are declared.

## Flow

```text
Market Data Application
        |
   Event producer (Kafka protocol, AMQP or HTTPS)
        |
   Network / security: TLS 1.2, Entra ID or SAS, optional Private Endpoint + Private DNS
        |
   Event Hubs namespace (streaming-prod)
        |
   Event hub: market-events  [P0] [P1] [P2] [P3]
        |
   Consumer groups: $Default | search-service | analytics
        |
   Consumers C1..C4 (one per partition) -> search / analytics / application
```

## Prerequisites

- Terraform 1.5 or newer, AzureRM provider `~> 3.100` (installed by `terraform init`)
- Azure CLI, signed in with `az login`
- A subscription you can create resources in. Select it with `ARM_SUBSCRIPTION_ID` or `az account set`, or set `subscription_id` in an uncommitted `terraform.tfvars`. Never commit subscription IDs.
- A globally unique `namespace_name`. The default `streaming-prod` is a placeholder.
- Permission to create role assignments if you set the principal ID variables.

## Run

```bash
cd azure/terraform
cp terraform.tfvars.example terraform.tfvars   # edit values
export ARM_SUBSCRIPTION_ID="<subscription-id>"
terraform init
terraform plan
terraform apply
```

To deploy into an existing resource group, set `create_resource_group = false` and `resource_group_name`.

Use `kafka_bootstrap_server` from the outputs in the client configuration under [../kafka/README.md](../kafka/README.md).

## What it does not do

- It does not create producers, consumers or secrets, and it does not output SAS keys.
- It does not configure a remote state backend.
- It does not set network rules beyond the optional Private Endpoint. Verify in current Microsoft documentation which tiers support Private Endpoints before enabling it.
- It does not enable Capture, geo-disaster recovery or schema registry.
- Sizing (`capacity`, partition count) is an example, not guidance.

## Cleanup

```bash
terraform destroy
```

If you used an existing resource group (`create_resource_group = false`), only the resources created here are removed. Resource group deletion is not part of destroy in that case.

## See also

- [Azure Event Hubs](../docs/azure-event-hubs.md)
- [Networking](../docs/networking.md)
- [Security](../docs/security.md)
- [Observability](../docs/observability.md)
- [Kafka to Event Hubs migration](../migration/kafka-to-event-hubs.md)
- [Kafka client configuration](../kafka/README.md)
