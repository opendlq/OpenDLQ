# OpenDLQ

**The open control plane for dead-letter queues.**
Recover what can heal itself, explain what can't, and measure all of it.

> **Status:** early design. The design is in [docs/](docs/README.md). The first version, [V0](roadmap/v0.md), targets Kafka and is not built yet. Everything below describes the intended design, not shipped features.

---

## The problem

A dead-letter queue (DLQ) stores messages a consumer could not process. That is all it does. What happens next depends on each team's scripts, dashboards and memory.

In practice this leads to the same problems again and again:

- **No context.** The DLQ keeps the payload, but usually not the error, the consumer that failed, the number of attempts or the dependency involved.
- **No distinction between causes.** A message that failed because a dependency was down for 30 seconds sits next to a message with an invalid schema. The first one only needs a retry. The second one never succeeds.
- **Manual replay.** Replay is a script or a "redrive" button, usually without idempotency, ordering, rate limits or an audit trail.
- **No aggregation.** A thousand messages with the same cause look like a thousand problems.
- **Alerts without answers.** A depth alert fires and the investigation starts from zero.

Broker-native retry (SQS redrive, Kafka retry topics, RabbitMQ dead-letter exchanges) retries N times in a row. It does not know why a message failed.

## What OpenDLQ does

OpenDLQ sits on top of your existing broker. It does not replace it.

It reads the DLQ and classifies every message into one of two kinds:

| | Transient | Permanent |
| --- | --- | --- |
| Cause | The environment: dependency down, timeout, rate limit, lock | The message or the code: invalid schema, business rule, bug |
| Does a retry help? | Yes, with time | No |
| What OpenDLQ does | Recovers it automatically | Groups it by root cause and waits for a decision |

From there, it works on three fronts:

**Recover** what can heal itself
- Retry with exponential backoff and jitter.
- Circuit breaker per dependency. When many different messages fail against the same dependency, OpenDLQ stops retrying, holds the backlog, probes the dependency, and drains the backlog at a controlled rate when it comes back.
- Runbooks: the operator declares how to handle a known permanent failure (transform and replay, route, discard), with guardrails such as rate limits, approval for the first runs and an expiry date.

**Explain** what can't
- Groups permanent failures by root cause.
- Correlates each failed message with the application logs that produced it (Elasticsearch, Loki, CloudWatch Logs, Datadog Logs) through trace and correlation IDs.
- Safe replay: one message or a batch, with an idempotency key, respecting the original partition key, with optional payload transformation.
- Full audit log: who did what, when, and with what result.
- Alerts with context, declared as code. Operational alerts go to whoever is on call; recurrence and cost alerts go to whoever sets priorities.

**Measure** all of it
- Resolution funnel: how many messages recovered on their own, were replayed by an operator, were handled by a runbook, were discarded, or are still open.
- Age per message, not only queue depth.
- Cost per cause and per consumer (storage, replays, operator time).
- Trends and recurrence: the same cause coming back after it was handled.
- Metrics and traces through OpenTelemetry (OTLP), plus a Prometheus endpoint, so you build dashboards and alerts in the tools you already use.
- Purge with policy: TTL per consumer or cause, archiving before deletion. The audit log is never deleted.

## Design principles

1. **Classify before acting.** Transient and permanent failures need opposite handling.
2. **Humans decide permanent failures.** Automation runs only what an operator declared.
3. **Declarative first.** If it is not in a file, it is drift.
4. **Beside your stack, not instead of it.** Your broker, your logs, your dashboards. Only Postgres is required.
5. **Opinionated defaults.** Adaptable everywhere except the guarantees.

The reasoning is in [principles](docs/principles.md). The invariants that never break are in [guarantees](docs/guarantees.md).

## Documentation

The full index is in [docs/](docs/README.md). Good places to start:

| Page | Covers |
| --- | --- |
| [Architecture](docs/architecture.md) | Controller model, components, deployment, consistency |
| [Flows](docs/flows.md) | Step-by-step sequence for each situation |
| [Header contract](docs/header-contract.md) | The only integration a consumer needs |
| [Configuration](docs/configuration.md) | Runtime settings and resource reference |
| [Roadmap](roadmap/README.md) | What each version ships. V0 scope, demo, milestones |
| [RFC 0001](docs/rfc/0001-opendlq.md) | Why OpenDLQ exists and the alternatives considered |

## License

Apache License 2.0. See [LICENSE](LICENSE).
