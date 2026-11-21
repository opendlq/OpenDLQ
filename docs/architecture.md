# Architecture

OpenDLQ follows the controller pattern used by Kubernetes. A single state store holds the state of every message and is the source of truth. Each component is a controller: it watches the messages in the state it owns, acts, and writes the new state. Components never call each other. The step-by-step sequence for each situation is in [flows](flows.md).

```mermaid
flowchart LR
    DLQ[(External DLQ)] --> Source
    Source --> Collector
    CLI[API · CLI · MCP] --> Store
    CFG[Declarative config] --> Store
    Collector -->|insert| Store[(State store)]
    Store <--> Policy[Policy Engine]
    Store <--> Transient[Transient Runner]
    Store <--> Runbook[Runbook Runner]
    Store <--> Poison[Poison Handler]
    Store <--> Enricher
    Store <--> Publisher
    Store <--> Purger
    Publisher --> Sink
    Sink --> Topic[(Original topic)]
    Store -->|CDC| Analytics[Analytics Engine]
    Store -. events .-> Alerts[Alerts Watcher]
    Analytics --> Alerts
    Alerts --> Notifier
```

## Rules of the model

- A controller takes work with `SELECT ... FOR UPDATE SKIP LOCKED`. Two instances never take the same message.
- Every state change uses compare-and-set on `version`. A concurrent change fails and is discarded.
- Every state change writes a row to `transitions` in the same transaction. That table is both the audit log and the fact table for analytics.
- `LISTEN/NOTIFY` only wakes controllers up. It is not a source of truth. Without it, the controller finds the work on its next poll.
- No controller publishes to the broker. A controller that needs to replay writes a row to the `outbox` in the same transaction as the state change. Only the Publisher reads the outbox and publishes.
- An operator action is a write of desired state. The responsible controller carries it out.
- Any component can crash and restart without losing anything. The state is in the store.

## Components

| Component | Watches | Does | Writes | Plugins |
| --- | --- | --- | --- | --- |
| **Collector** | Source | Consumes the DLQ. Extracts headers and correlation IDs. Recognizes re-entries by `x-dlq-id`. Calls no external service. Commits the offset after the insert. | New message or re-entry in `received` | Source, Serde |
| **Policy Engine** | `received` | Classifies. Checks exhaustion. Routes by precedence: matching runbook, then transient, then permanent. | `runbook_matched`, `retrying`, `held` or `awaiting_operator` | Classifier |
| **Transient Runner** | `retrying` due; `held`; `replaying` | Schedules retries with backoff. Opens and closes circuit breakers. Runs probes. Confirms recovery. | `outbox`; `replaying`, `held`, `retrying`, `recovered` or `received` | Probe, Recovery Detector |
| **Runbook Runner** | `runbook_matched` | Executes the runbook action within its guardrails. Records each step. | `outbox`; `replaying`, `routed`, `discarded`, `awaiting_approval` or `awaiting_operator` | Transformer, Runbook Action |
| **Poison Handler** | `awaiting_operator` not yet announced | Updates the cause group. Marks sampled messages for enrichment. Emits an event. | `notified_at`; `enrichment = pending`; `poisoned` event | — |
| **Enricher** | Messages with `enrichment = pending` | Waits for indexing, fetches logs by correlation IDs, retries. Asynchronous: never blocks another controller. | `enrichment` status, log link and snippet | Log Provider |
| **Publisher** | Pending `outbox` rows | Serializes and publishes to the target. Marks the row as sent. | `outbox.sent_at` | Sink, Serde |
| **Purger** | Expired messages; payloads past retention | Moves messages to `expired`. Archives and deletes payloads. Never deletes `transitions`. | `expired`; archived payload | Store |
| **Analytics Engine** | `transitions` (CDC or rollup) | Computes funnel, cost, trends, recurrence. Exports OpenTelemetry and `/metrics`. Serves `/analytics`. | Rollups; analytic condition events | — |
| **Alerts Watcher** | Events from `transitions` and Analytics; alert instances | Evaluates declared `Alert` resources. Waits for enrichment as each alert declares. The only component that notifies. | Alert instances: `pending_enrichment`, `sent`, `followed_up` | Notifier |

The Collector never queries logs. If the logging backend is down, ingestion continues.

Runners never notify. They emit events (`exhausted`, `poisoned`, `runbook_step`). The Alerts Watcher decides whether and whom to notify.

## Message state machine

```mermaid
stateDiagram-v2
    [*] --> received
    received --> retrying: transient
    received --> held: transient, circuit open
    received --> runbook_matched: runbook matches
    received --> awaiting_operator: permanent or exhausted
    retrying --> held: circuit opens
    held --> retrying: probe passes
    retrying --> replaying: retry due
    runbook_matched --> awaiting_approval: approval required
    awaiting_approval --> runbook_matched: approved
    awaiting_approval --> awaiting_operator: rejected
    runbook_matched --> replaying: transform and replay
    runbook_matched --> routed: route
    runbook_matched --> discarded: discard
    runbook_matched --> awaiting_operator: action fails
    awaiting_operator --> replaying: operator replays
    awaiting_operator --> retrying: operator reclassifies
    awaiting_operator --> discarded: operator discards
    replaying --> recovered: success confirmed
    replaying --> received: back in the DLQ
    recovered --> [*]
    discarded --> [*]
    routed --> [*]
    expired --> [*]
```

| State | Meaning | Left by |
| --- | --- | --- |
| `received` | Stored by the Collector, not yet classified | Policy Engine |
| `retrying` | Transient, retry scheduled at `next_retry_at` | Transient Runner |
| `held` | Transient, dependency circuit open. Nothing is scheduled | Transient Runner |
| `replaying` | In the outbox or published, waiting for confirmation | Transient Runner or Collector |
| `runbook_matched` | A runbook matched and will act | Runbook Runner |
| `awaiting_approval` | The runbook's guardrail requires approval | Operator |
| `awaiting_operator` | Permanent or exhausted. Grouped by cause, waiting for a decision | Operator |
| `recovered` | Terminal. The consumer processed it successfully | — |
| `discarded` | Terminal. Dropped with a reason | — |
| `routed` | Terminal. Sent to another destination by a runbook | — |
| `expired` | Terminal. TTL reached from any open state | — |

- Exhausted is not a state. When attempts reach the policy maximum, the Policy Engine sends the message to `awaiting_operator`.
- There is no automatic transition from `awaiting_operator` to `retrying`. Only an operator reclassifies.
- A replayed message that fails again returns to the DLQ with the same `x-dlq-id`. The Collector attaches the new attempt to the existing record and moves it back to `received`. The message keeps its identity.
- Time in `held` does not count as an attempt.

## Message record

| Field | Type | Holds |
| --- | --- | --- |
| `id` | UUID | Identity in OpenDLQ. Sent as `x-dlq-id` on every replay |
| `source_topic`, `partition`, `offset` | string, int, int | Where it came from in the DLQ |
| `original_topic`, `partition_key` | string, bytes | Where it goes back, and with which key |
| `payload`, `headers` | bytes, map | The message as it arrived |
| `consumer` | string | Who failed |
| `failure_kind` | enum | `transient`, `permanent`, `unknown` |
| `failure_reason`, `failure_dependency` | string | Short error and dependency involved |
| `group_key` | string | Grouping key by root cause |
| `classified_by` | enum | `header`, `rule`, `inference`, `operator` |
| `state`, `version` | enum, int | Current state and version for compare-and-set |
| `attempts` | list | Each attempt: when, result, error |
| `next_retry_at` | timestamp | Next scheduled retry |
| `runbook` | string | Name and version of the matching runbook |
| `expires_at` | timestamp | TTL deadline |
| `notified_at` | timestamp | When the Poison Handler announced it |
| `enrichment` | enum | `skipped`, `pending`, `enriched`, `not_found`, `unavailable` |
| `correlation` | map | Correlation IDs extracted from headers |

The history of state changes and the audit trail live in `transitions`, not on the message.

## Plugins

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

Three levels of extension:

1. **Expressions in configuration** (CEL, JSONata). Cover most classifiers, transformers and matches. No build step.
2. **Out-of-process plugins** (gRPC in the `hashicorp/go-plugin` model, or WASM). For domain logic. Isolate failures. Any language.
3. **Compiled adapters** (Go interfaces). For Source, Sink, Serde, Store and Log Provider. Maintained by the project.

Not pluggable: the state machine, the resource model, the audit log, the header contract, the analytics calculations and the runbook guardrails. That is what keeps every installation compatible. Changing the core is a fork.

## Store requirements

A pluggable store must provide ACID transactions across `messages`, `transitions` and `outbox`; compare-and-set per row; and row locks with skip. A database without all three cannot be a store. The analytics database is separate and has no such requirements.

## Consistency guarantees

| Where | Guarantee | Mechanism |
| --- | --- | --- |
| Ingestion | No message lost; none duplicated in the store | Insert before offset commit; unique constraint on `(topic, partition, offset)` |
| State changes | One decision per message at a time | `SKIP LOCKED` + compare-and-set on `version` |
| Replay | One decision produces one send from OpenDLQ | Transactional outbox |
| Audit | Every state change recorded | `transitions` in the same transaction |
| Analytics | Eventual, with a declared maximum lag | CDC or periodic rollup |
| Consumer | Not guaranteed by OpenDLQ | Idempotency key in the header; the consumer deduplicates |
