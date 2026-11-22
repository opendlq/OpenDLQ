# RFC 0001: OpenDLQ

- **Status:** Draft
- **Author:** Yuri Costa
- **Created:** 2026-10-27

This RFC records why OpenDLQ exists and the decisions behind it. The design itself lives in the topic docs, linked below. When the design changes, the topic docs change; this RFC records the reasoning.

## Summary

OpenDLQ is a control plane for messages in dead-letter queues. It reads the DLQ, classifies each message as transient or permanent, recovers the transient ones without human involvement, and exposes the permanent ones, grouped by cause, for an operator to decide. Every action is recorded. On top of that core sits a generic management layer: analytics, cost, trends, recurrence and purge.

OpenDLQ does not replace the broker. It runs on top of Kafka, SQS or RabbitMQ.

## Context and problem

A DLQ stores messages a consumer could not process. Either the broker moves the message there, or the consumer publishes it there. In both cases the DLQ is only storage. What happens next depends on each team's tools and process.

The problems below show up repeatedly in operator reports (threads on r/aws, r/sysadmin and r/devops, and the open source tools listed under alternatives). There is no quantitative survey; the list is qualitative.

- **No context.** The DLQ keeps the payload. It usually does not keep the exception, the consumer that failed, the number of attempts or the dependency involved.
- **No distinction between causes.** A message that failed because a dependency was briefly unavailable sits next to a message with an invalid schema. The first one only needs a retry. The second one never succeeds.
- **Manual replay.** Replay is a script or a redrive button, usually without an idempotency key, a record of who ran it, ordering or rate limits.
- **No aggregation.** A thousand messages with the same cause show up as a thousand items, not as one problem.
- **No self-recovery.** The most common case reported is an unstable dependency. The fix is to wait and retry, but that takes a human.
- **Alerts without answers.** Depth alerts exist (CloudWatch, Datadog, cron). The recurring report is that the alert fires and the investigation starts from zero.

Broker-native retry (SQS redrive, Kafka retry topics, RabbitMQ dead-letter exchanges) retries N times in a row. It does not distinguish causes, aggregate, record actions, or stop when an entire dependency is down.

## Goals

- Classify every message as transient or permanent, by header, rule or inference.
- Recover transient failures without human involvement: retry with backoff, circuit breaker per dependency, controlled drain when the dependency comes back.
- Expose permanent failures grouped by cause, with full context: error, consumer, attempts, payload, correlated logs.
- Allow safe replay: one message or a batch, with an idempotency key, with optional payload transformation.
- Let operators declare runbooks for known permanent causes, with guardrails, for automatic handling.
- Record every action: who, what, when, result.
- Provide complete analytics: resolution funnel, cost, trends, recurrence, by cause, consumer and period.
- Configure everything declaratively, versioned and applied by CLI, with the API and UI as equivalent alternatives.
- Keep the core generic. Domain-specific logic comes in through extension points.

Non-goals are listed in [scope](../scope.md#non-goals).

## Central thesis

Every processing failure has one of two natures, and the correct handling is opposite for each. Treating them the same way produces one of two errors: retrying everything overloads an unavailable dependency, and retrying nothing pages a human for a 30-second timeout.

OpenDLQ therefore makes classification the first step, not a manual step afterwards. See [classification](../components/policy-engine.md).

## Design

The design lives in the documentation, one page per component. The index is in [docs/](../README.md).

| Topic | Document |
| --- | --- |
| Principles | [principles.md](../principles.md) |
| Guarantees | [guarantees.md](../guarantees.md) |
| Controller model, components, deployment, consistency | [architecture.md](../architecture.md) |
| States and owners | [state-machine.md](../state-machine.md) |
| Flows | [flows.md](../flows.md) |
| Classification and routing | [Policy Engine](../components/policy-engine.md) |
| Retry, circuit breaker, probe, drain | [Transient Runner](../components/transient-runner.md) |
| Runbooks | [Runbook Runner](../components/runbook-runner.md) |
| Funnel, cost, recurrence, findings | [Analytics Engine](../components/analytics-engine.md) |
| Alerts | [Alerts Watcher](../components/alerts-watcher.md) |
| Header contract | [header-contract.md](../header-contract.md) |
| Configuration | [configuration.md](../configuration.md) |
| Non-goals, open questions | [scope.md](../scope.md) |
| What each version ships | [roadmap](../../roadmap/README.md) |

## Alternatives considered

| Alternative | Limitation |
| --- | --- |
| Broker-native retry (SQS redrive, Kafka retry topics, RabbitMQ DLX) | Retries without distinguishing causes. Does not open a circuit. Does not aggregate. Does not record actions. |
| Republish scripts (`sqsmover` and similar) | No idempotency, no record, no ordering, no rate limit. |
| Retry inside the consumer (Resilience4j, Kafka Cascade, KDLQ) | Covers short transient failures. Blocks the partition while waiting. No central view. |
| DLQ browser with edit and redrive (DLQ Revive, internal UIs) | Covers visibility and audited replay. Does not classify, self-heal or measure cost. |
| Observability over the DLQ (CloudWatch, Datadog, Sentry Queues) | Measures depth, age and attempts. Does not act. Does not classify. |
| Workflow engine (Temporal, Cadence) | Solves durable retry and state. Requires rewriting consumers as workflows. |

OpenDLQ does not compete with retry in code or with depth alerts. It handles what survived the consumer's short retry.

### Known objection

A common argument in operations discussions: never requeue a DLQ automatically; requeue only after you know why, because (a) the dependency came back or (b) the bug was fixed.

OpenDLQ accepts the argument. The probe is criterion (a), automated: OpenDLQ requeues because a probe confirmed the dependency responds, not because time passed. Criterion (b) stays human: a permanent failure never retries on its own, unless an operator declared the decision in a runbook.

### On the absence of a standard tool

Operator reports suggest that every team builds its own DLQ tooling. That is consistent with unmet demand, and also with a problem each team prefers to solve locally. This project does not assume which one is true. It treats automatic classification as the hypothesis to test.

## Risks

- **Replay without idempotency in the consumer duplicates side effects.** Mitigation: the header contract is documented, and the project ships an example consumer that implements it. Without the contract, replay is not safe.
- **Wrong classification.** A transient failure marked permanent only waits for a person. A permanent failure marked transient uses up its retries and then goes to a person. The second case is bounded by the retry limit.
- **Circuit breaker false positive.** Twenty messages with the same validation error can look like an unavailable dependency. Mitigation: the breaker counts only failures classified as transient.
- **Ordering.** A batch replay of messages with the same partition key must keep the original order. The drain orders by `(partition_key, offset)`. Order across keys is not guaranteed.
- **Volume.** Millions of messages fill Postgres. Payload retention and the Purger bound it; the store is replaceable.
