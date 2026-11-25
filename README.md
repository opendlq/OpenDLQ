<p align="center">
  <img src="docs/assets/opendlq-dark.png" alt="OpenDLQ" width="640">
</p>

# OpenDLQ

> **Status:** early design, not built yet. The first version, [V0](roadmap/v0.md), targets Kafka.

## What is OpenDLQ?

OpenDLQ is a declarative control plane for dead-letter queues that runs beside your existing broker.

## Why OpenDLQ?

A failed message should be classified before anything acts on it. Transient failures should recover on their own. Permanent failures should be grouped by cause and decided by a person, through declared and audited actions. Every outcome should be measured.

## The problem

A dead-letter queue (DLQ) stores messages a consumer could not process. What happens next depends on each team's scripts, dashboards and memory.

- **No context.** The DLQ keeps the payload, but not the error, the consumer or the dependency involved.
- **No distinction between causes.** A 30-second outage sits next to an invalid schema. Only the first one heals with a retry.
- **Manual replay.** A script or a "redrive" button, without idempotency, rate limits or an audit trail.
- **No aggregation.** A thousand messages with the same cause look like a thousand problems.

Broker-native retry (SQS redrive, Kafka retry topics, RabbitMQ dead-letter exchanges) retries N times in a row. It does not know why a message failed.

## Documentation

The full index is in [docs/](docs/README.md). Good places to start:

| Page | Covers |
| --- | --- |
| [Principles](docs/principles.md) | The positions that decide trade-offs |
| [Architecture](docs/architecture.md) | Controller model, components, deployment |
| [Flows](docs/flows.md) | Step-by-step sequence for each situation |
| [Specifications](specs/README.md) | Every path and problem of a message, in Gherkin |
| [Header contract](docs/header-contract.md) | The only integration a consumer needs |
| [Configuration](docs/configuration.md) | Runtime settings and resource reference |
| [Roadmap](roadmap/README.md) | What each version ships. V0 scope, demo, milestones |
| [RFC 0001](docs/rfc/0001-opendlq.md) | Why OpenDLQ exists and the alternatives considered |

## License

Apache License 2.0. See [LICENSE](LICENSE).
