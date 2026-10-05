# Diagrams

All diagrams use the same nine-layer flow for the market-data pipeline: Application, Producer, Network/Security, Streaming platform, Topic / Event Hub, Partitions, Consumer group, Consumers, Downstream. The mapping between AWS and Azure components is conceptual, not 1:1. Each diagram is also available as a standalone `.mermaid` file in this folder.

## Amazon MSK architecture

The source flow on AWS: a Kafka producer reaches the `streaming-msk` cluster through VPC networking, writes to the `market-events` topic, and four consumers in the `search-service` group read one partition each. File: [msk-architecture.mermaid](./msk-architecture.mermaid).

```mermaid
flowchart TD
    APP["Market Data Application"] --> PROD["Kafka Producer"]
    PROD -->|"TLS + SASL/IAM"| NET["VPC, private subnets,<br/>security groups"]
    NET --> MSK["Amazon MSK<br/>streaming-msk"]
    MSK --> TOPIC["Kafka Topic<br/>market-events"]
    TOPIC --> P0["P0"]
    TOPIC --> P1["P1"]
    TOPIC --> P2["P2"]
    TOPIC --> P3["P3"]
    P0 --> CG["Consumer group<br/>search-service"]
    P1 --> CG
    P2 --> CG
    P3 --> CG
    CG --> C1["C1"]
    CG --> C2["C2"]
    CG --> C3["C3"]
    CG --> C4["C4"]
    C1 --> DS["Downstream:<br/>search / analytics / app"]
    C2 --> DS
    C3 --> DS
    C4 --> DS
    MSK -.-> CW["CloudWatch"]
```

## Azure Event Hubs architecture

The same flow on Azure: an event producer (Kafka protocol, AMQP or HTTPS) reaches the namespace through a Private Endpoint, writes to the `market-events` event hub, and consumers in the `search-service` group read the partitions. `streaming-prod` is a placeholder namespace name. File: [event-hubs-architecture.mermaid](./event-hubs-architecture.mermaid).

```mermaid
flowchart TD
    APP["Market Data Application"] --> PROD["Event Producer<br/>Kafka, AMQP or HTTPS"]
    PROD -->|"TLS + Entra ID / SAS"| NET["VNet, Private Endpoint,<br/>Private DNS"]
    NET --> NS["Event Hubs Namespace<br/>streaming-prod"]
    NS --> EH["Event Hub<br/>market-events"]
    EH --> P0["P0"]
    EH --> P1["P1"]
    EH --> P2["P2"]
    EH --> P3["P3"]
    P0 --> CG["Consumer group<br/>search-service"]
    P1 --> CG
    P2 --> CG
    P3 --> CG
    CG --> C1["C1"]
    CG --> C2["C2"]
    CG --> C3["C3"]
    CG --> C4["C4"]
    C1 --> DS["Downstream:<br/>search / analytics / app"]
    C2 --> DS
    C3 --> DS
    C4 --> DS
    NS -.-> AM["Azure Monitor"]
```

## MSK and Event Hubs side by side

Dotted lines link the nearest equivalent on each side. They show a conceptual mapping, not feature parity. File: [msk-vs-event-hubs.mermaid](./msk-vs-event-hubs.mermaid).

```mermaid
flowchart LR
    subgraph AWS["AWS: Amazon MSK"]
        direction TB
        A1["Kafka Producer"] --> A2["VPC, subnets,<br/>security groups"]
        A2 --> A3["Amazon MSK cluster"]
        A3 --> A4["Kafka Topic"]
        A4 --> A5["Partitions"]
        A5 --> A6["Consumer group"]
        A6 --> A7["Consumers"]
        A3 -.-> A8["CloudWatch"]
    end
    subgraph AZ["Azure: Event Hubs"]
        direction TB
        B1["Event Producer"] --> B2["VNet, Private Endpoint,<br/>Private DNS"]
        B2 --> B3["Event Hubs Namespace"]
        B3 --> B4["Event Hub"]
        B4 --> B5["Partitions"]
        B5 --> B6["Consumer group"]
        B6 --> B7["Consumers"]
        B3 -.-> B8["Azure Monitor"]
    end
    A1 -.- B1
    A2 -.- B2
    A3 -.- B3
    A4 -.- B4
    A5 -.- B5
    A6 -.- B6
    A7 -.- B7
    A8 -.- B8
```

## Migration flow

An AWS source workload moves to an Azure target through six phases. Treat it as an evaluation path: each phase has a validation gate. File: [migration-flow.mermaid](./migration-flow.mermaid).

```mermaid
flowchart LR
    subgraph SRC["AWS source"]
        S1["Producers"] --> S2["Amazon MSK<br/>market-events"]
        S2 --> S3["Consumers<br/>search-service"]
    end
    subgraph PH["Migration phases"]
        direction TB
        M1["1. Inventory"] --> M2["2. Recreate as event hubs<br/>from code"]
        M2 --> M3["3. Dual-write or mirror"]
        M3 --> M4["4. Validate"]
        M4 --> M5["5. Cut over"]
        M5 --> M6["6. Decommission<br/>or roll back"]
    end
    subgraph TGT["Azure target"]
        T1["Producers"] --> T2["Event Hubs Namespace<br/>Event Hub market-events"]
        T2 --> T3["Consumers<br/>search-service"]
    end
    S2 -.-> M1
    M3 -.-> T2
    M5 -.-> T3
    M6 -.-> T1
```

## See also

- [Architecture](../docs/architecture.md)
- [Data flow](../docs/data-flow.md)
- [MSK vs Event Hubs comparison](../docs/comparison.md)
- [Migration architecture](../migration/architecture.md)
- [Kafka to Event Hubs migration guide](../migration/kafka-to-event-hubs.md)
