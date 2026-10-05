# Security: Amazon MSK vs Azure Event Hubs

This document compares how the market-data pipeline (`market-events`, 4 partitions, consumer group `search-service`) is secured on [Amazon MSK](./msk.md) and on [Azure Event Hubs](./azure-event-hubs.md). The mapping is conceptual, not 1:1. The two services have different identity models, different network primitives and different admin surfaces.

Principles that apply to both:

- Authenticate every client. Authorize each client for the minimum it needs.
- Encrypt in transit. Keep the data path off the public internet.
- Keep secrets out of code and out of Git. Prefer identity-based access over shared secrets.

## AWS: Amazon MSK

### Identity and authorization

MSK supports several client authentication options. For new workloads the usual choice is IAM access control, which uses SASL over TLS with the `AWS_MSK_IAM` mechanism. See the [MSK IAM access control docs](https://docs.aws.amazon.com/msk/latest/developerguide/iam-access-control.html).

- Producers and consumers run under an IAM role (for example an EC2 instance profile, an ECS task role or an EKS service account role). They obtain short-lived credentials, so no password is stored.
- Authorization is an IAM policy. Actions are scoped to the cluster, topic and group resources (for example connect to the cluster, write to topic `market-events`, read from topic `market-events`, join group `search-service`). Look up the exact action names in the MSK IAM docs.
- Other options exist (mutual TLS, SASL/SCRAM with credentials in AWS Secrets Manager). Use them when clients cannot use IAM. Check the current MSK docs for how each option combines with the others on a cluster.
- Kafka ACLs are a separate mechanism. IAM access control and Kafka ACLs are different layers, so decide which one is the source of truth and document it.

### Encryption

- In transit: TLS between clients and brokers, and between brokers. Configure the cluster so that plaintext client traffic is disabled.
- At rest: broker storage is encrypted, with an AWS-managed key or a customer-managed key in AWS KMS.

### Network controls

- The cluster is created in private subnets of a VPC, normally across multiple Availability Zones.
- Security groups act as the firewall. Allow the Kafka client port only from the security groups of the producer and consumer workloads, not from broad CIDR ranges. The listener port depends on the authentication mode (for example the IAM listener differs from the TLS listener). Confirm ports in the MSK docs.
- Public access is an opt-in setting. Leave it off for production unless you have a specific, reviewed need.

### Secrets management

- With IAM there is nothing to store. With SASL/SCRAM, keep credentials in AWS Secrets Manager and associate the secret with the cluster.
- Never place credentials in `client.properties`. Commit only `client.properties.example`.

## Azure: Event Hubs

### Identity and authorization

Event Hubs offers two ways to authorize clients.

| Method | What it is | Notes |
| --- | --- | --- |
| Microsoft Entra ID (recommended) | OAuth 2.0 tokens issued to a user, service principal or managed identity. Access is granted with Azure RBAC. | No shared secret to distribute. Short-lived tokens. Auditable per identity. See [Microsoft Entra ID](https://learn.microsoft.com/entra/fundamentals/whatis). |
| Shared Access Signature (SAS) | A policy name plus key, or a token derived from it. Scoped to a namespace or an event hub. | Simple, but it is a bearer secret. Anyone holding it has its rights until the key is rotated. |

Built-in RBAC data roles for Event Hubs:

- Azure Event Hubs Data Sender: send events.
- Azure Event Hubs Data Receiver: receive events.
- Azure Event Hubs Data Owner: full data access, including management of entities.

For the pipeline, assign Data Sender to the producer's identity and Data Receiver to the consumer identities. Scope the role assignment to the event hub `market-events` where possible rather than the whole namespace.

### Managed Identity

Workloads running on Azure compute (for example App Service, Container Apps, AKS with workload identity, virtual machines) can use a managed identity. Azure issues and rotates the credential. The application requests a token and presents it to Event Hubs. No connection string is needed.

### Why prefer Entra ID over SAS

- No long-lived secret to leak, copy into a pipeline variable or forget to rotate.
- Per-identity audit trail and per-identity revocation, instead of a key shared by many clients.
- Role scope is narrower and expressed in RBAC alongside your other Azure access.
- Conditional access and lifecycle controls from Entra apply.

SAS is still reasonable for a client that cannot obtain Entra tokens. If you use it, scope a policy to one event hub, grant only the needed claim (send or listen), store the key in Key Vault and rotate it.

For Kafka clients, Event Hubs accepts SASL PLAIN with a connection string as the password, and SASL OAUTHBEARER with an Entra token. Which Kafka client libraries support OAUTHBEARER well varies, so verify against the [Event Hubs for Apache Kafka docs](https://learn.microsoft.com/azure/event-hubs/azure-event-hubs-apache-kafka-overview). The Kafka endpoint requires the Standard tier or above.

### Encryption

- In transit: TLS. Clients connect over an encrypted channel. Check the current docs for the minimum TLS version the service enforces and whether it is configurable on your tier.
- At rest: data is encrypted by the service. Customer-managed keys are an option on some tiers; verify availability for your tier in the current docs.

### Network controls

- Private Endpoint: gives the namespace a private IP address in your VNet. See [Azure Private Endpoint](https://learn.microsoft.com/azure/private-link/private-endpoint-overview). Private Endpoint support depends on the tier, so verify the current docs.
- Private DNS: a private DNS zone (for Event Hubs, `privatelink.servicebus.windows.net`) linked to the VNet so the namespace name resolves to the private IP. See [Networking](./networking.md).
- Public network access: disable it on the namespace once private connectivity is confirmed. Namespace firewall rules (IP and virtual network rules) are the alternative when you cannot use Private Endpoint.

### Key Vault

Use Azure Key Vault where a secret is unavoidable: a SAS key, a certificate, a downstream credential. Applications read it through their managed identity. With Entra ID authentication to Event Hubs there is usually no Event Hubs secret to put in Key Vault.

## Comparison table

| Area | Amazon MSK | Azure Event Hubs |
| --- | --- | --- |
| Preferred authentication | SASL/IAM (`AWS_MSK_IAM`) over TLS | Microsoft Entra ID (OAuth 2.0) |
| Fallback authentication | mTLS, SASL/SCRAM | SAS (connection string or token) |
| Workload identity | IAM role (instance profile, task role, IRSA) | Managed Identity |
| Authorization model | IAM policies on cluster, topic and group resources; Kafka ACLs as a separate layer | Azure RBAC: Data Sender, Data Receiver, Data Owner |
| Secret store | AWS Secrets Manager (SCRAM) | Azure Key Vault (SAS, certificates) |
| Encryption in transit | TLS | TLS |
| Encryption at rest | AWS-managed or KMS customer-managed key | Service-managed; customer-managed keys on some tiers (verify) |
| Private connectivity | Cluster in private subnets of a VPC | Private Endpoint in a VNet |
| Name resolution | Broker DNS names resolve inside the VPC | Private DNS zone linked to the VNet |
| Traffic filtering | Security groups | Namespace network rules, NSGs on the client subnet |
| Audit | CloudTrail for control plane; broker logs to CloudWatch | Azure Activity Log and diagnostic logs to Azure Monitor |

## Recommended production practices

1. Use identity-based auth on both platforms (IAM roles, Entra managed identities). Avoid shared keys.
2. One identity per application. Do not share a producer and a consumer identity.
3. Grant least privilege, scoped to `market-events` and the consumer groups in use.
4. Disable public access and plaintext listeners. Verify with a connection test from outside the private network.
5. Put the data path on private networking. Confirm DNS resolves to private addresses (see [Troubleshooting](./troubleshooting.md)).
6. Keep secrets in Secrets Manager or Key Vault if you have any. Rotate them. Never commit them.
7. Send audit and diagnostic logs to a central store and alert on authorization failures (see [Observability](./observability.md)).
8. Manage all of the above as code so reviews and drift detection apply.

## See also

- [Networking](./networking.md)
- [Production checklist](./production-checklist.md)
- [Troubleshooting](./troubleshooting.md)
- [Comparison](./comparison.md)
- [Architecture](./architecture.md)
