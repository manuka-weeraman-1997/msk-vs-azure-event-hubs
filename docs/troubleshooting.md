# Troubleshooting

Symptom, likely cause, first check. Replace placeholders such as `<bootstrap-broker>` and `<namespace>` with your values. Event Hubs namespace names are globally unique, so `streaming-prod` is only an example. Never paste real keys or tokens into tickets or chats.

## Quick diagnostic commands

```bash
# DNS: what does the name resolve to, and is it a private address?
nslookup <namespace>.servicebus.windows.net
nslookup <bootstrap-broker>

# TCP and TLS: can we connect and complete the handshake?
openssl s_client -connect <host>:<port> -servername <host> </dev/null

# Kafka metadata: can the client authenticate and list topics?
kcat -b <bootstrap-server> -F client.properties -L

# Consumer group position and lag
kafka-consumer-groups.sh --bootstrap-server <bootstrap-server> \
  --command-config client.properties --describe --group search-service
```

The client configuration is in [kafka/configs/client.properties.example](../kafka/README.md). For Event Hubs the Kafka endpoint uses the namespace host and the port given in the [Event Hubs for Apache Kafka docs](https://learn.microsoft.com/azure/event-hubs/azure-event-hubs-apache-kafka-overview). For MSK the port depends on the authentication mode, so use the bootstrap string from the cluster.

Some Kafka tooling expects broker-level admin features that Event Hubs does not expose, so a `kafka-consumer-groups.sh` or `kafka-topics.sh` command may behave differently against Event Hubs. Verify in current Microsoft docs.

## Amazon MSK

| Symptom | Likely cause | Check |
| --- | --- | --- |
| Cannot connect (timeout) | Security group does not allow the client. Wrong subnet or route. Wrong port for the auth mode | Cluster SG inbound rules from the client SG. `openssl s_client` to a broker on the expected port |
| Connects to bootstrap, then times out on produce or fetch | Client can reach some brokers but not others, or advertised addresses do not resolve | Test every broker address from `-L` output. Check DNS and SG |
| TLS handshake error | Client does not trust the CA, wrong port, or plaintext client on a TLS port | `openssl s_client`. Check `security.protocol` and truststore |
| Authentication or authorization failed (IAM) | Missing IAM action or wrong resource ARN for topic or group. Wrong role in use | IAM policy, effective role (`aws sts get-caller-identity`), client SASL config |
| Name does not resolve | Client is outside the VPC or lacks DNS path to the broker names | `nslookup` from the client network |
| Consumer lag growing | Consumers too slow, fewer consumers than partitions, hot partition, downstream slow, frequent rebalances | `kafka-consumer-groups.sh --describe`. Per-partition lag. Consumer CPU and processing time |
| Rebalance storms | `max.poll.interval.ms` exceeded by slow processing, unstable consumers, frequent restarts, short session timeout | Consumer logs for rebalance messages. Increase poll interval or reduce batch size. Check deployment churn |
| Producer timeouts | Network path problems, broker overload, too-small `request.timeout.ms` or `delivery.timeout.ms`, large batches | Producer logs, broker CPU and network metrics, round-trip time |
| Throttling or slowdowns | Broker CPU or network saturated, undersized brokers or partitions | Broker metrics in CloudWatch. See [Observability](./observability.md) |
| Topic missing | Auto-create disabled, topic not provisioned, typo in name | `kafka-topics.sh --list`. Topic definition in [kafka/](../kafka/README.md) |

## Azure Event Hubs

| Symptom | Likely cause | Check |
| --- | --- | --- |
| Cannot connect (timeout) | Client cannot reach the Private Endpoint. NSG, route or DNS issue. Wrong port | `nslookup`, then `openssl s_client` to the namespace host and Kafka port |
| DNS resolves to a public IP instead of private | Private DNS zone `privatelink.servicebus.windows.net` missing, not linked to the client VNet, or client uses a resolver that does not see the zone. Missing DNS forwarding from other networks | `nslookup <namespace>.servicebus.windows.net` from the client. Look for the privatelink CNAME and a private address. Check zone virtual network links and resolver config |
| Connection forbidden after disabling public access | Client resolved the public IP | Fix DNS first. See [Networking](./networking.md) |
| TLS handshake error | Wrong port, plaintext client, outdated TLS library or truststore | `openssl s_client`. Check `security.protocol=SASL_SSL` in the client config |
| Authentication failed (SASL PLAIN) | Wrong or expired SAS key, wrong policy, connection string malformed, wrong username (must be the literal value in the Event Hubs Kafka docs) | Recreate or rotate the policy. Compare with the docs |
| Authentication failed (Entra / OAUTHBEARER) | Token for the wrong audience or tenant. Identity lacks a role assignment. Role assignment not yet propagated | Role assignments for the identity at namespace or event hub scope (Data Sender or Data Receiver). Token claims |
| Authorization error on send or receive | Identity has only the wrong role, or role scoped to a different event hub | Compare role with action. Sender needs Data Sender, consumer needs Data Receiver |
| Consumer lag growing | Same causes as MSK: slow consumers, one consumer per partition limit, hot partition | Lag from consumer group offsets or SDK checkpoints. Check partition key skew on `symbol` |
| Rebalance storms | Consumer processing exceeds poll interval, restarts, session timeout too short | Consumer logs. Tune poll and session settings. Check restarts |
| Producer timeouts | Network latency, throttling, large batches, idle connection handling | Producer logs, `ThrottledRequests`, round-trip time. Check Event Hubs docs for recommended Kafka client settings |
| Throttling | Namespace capacity (throughput units or processing units, depending on tier) exceeded | `ThrottledRequests` metric. Review capacity and see [Cost considerations](./cost-considerations.md) |
| Event hub (topic) missing or "unknown topic" | Event hub not created in the namespace. Kafka auto-topic-creation does not behave as on a Kafka cluster | List event hubs in the namespace. Create `market-events` via Terraform in [azure](../azure/README.md) |
| Consumer group missing | Group must exist, or is created on first use, depending on client type | Check the event hub's consumer groups. Verify behaviour in current docs |

## Method

1. Name resolution: does the host resolve to the address you expect?
2. Reachability: can you open a TCP connection on the right port?
3. TLS: does the handshake complete?
4. Authentication: does a metadata request succeed?
5. Authorization: can this identity send or receive on `market-events`?
6. Behaviour: lag, rebalances, throttling.

Work in that order. Most "Kafka errors" are failures at steps 1 to 3.

## See also

- [Networking](./networking.md)
- [Security](./security.md)
- [Observability](./observability.md)
- [Production checklist](./production-checklist.md)
- [Data flow](./data-flow.md)
