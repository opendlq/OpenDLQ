# Plugins

Plugins connect OpenDLQ to the outside world and to a team's domain. The core stays fixed.

## Contracts

| Plugin | Contract | Examples |
| --- | --- | --- |
| Source | Read messages from a DLQ and confirm the read | Kafka, SQS, RabbitMQ, Pub/Sub |
| Sink | Publish a replayed message | Original topic, another topic, HTTP |
| Serde | `Deserialize(bytes, schema)` and `Serialize(value, schema)` | JSON, Avro, Protobuf |
| Classifier | Message + error → kind, dependency, grouping key | Default by header and rule; team plugin |
| Transformer | Payload → corrected payload | JSONata, CEL, code |
| Probe | Check whether a dependency is back | Canary with a real message, HTTP health check |
| Recovery Detector | Confirm that a replay succeeded | Ack topic, no return within N s |
| Log Provider | Correlation IDs + time window → logs | Elasticsearch, Loki, CloudWatch, Datadog Logs |
| Notifier | Deliver an alert | Slack, PagerDuty, Opsgenie, webhook |
| Runbook Action | Execute a declared step | Transform and replay, route, discard, call an API |
| Store | Persist state, outbox and audit log | Postgres in V0 |

## Levels of extension

Three levels:

1. **Expressions in configuration** (CEL, JSONata). Cover most classifiers, transformers and matches. No build step.
2. **Out-of-process plugins** (gRPC in the `hashicorp/go-plugin` model, or WASM). For domain logic. Isolate failures. Any language.
3. **Compiled adapters** (Go interfaces). For Source, Sink, Serde, Store and Log Provider. Maintained by the project.

## Not pluggable

Not pluggable: the state machine, the resource model, the audit log, the header contract, the analytics calculations and the runbook guardrails. That is what keeps every installation compatible. Changing the core is a fork.
