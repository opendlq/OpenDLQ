# Documentation

Start with the principles and the architecture. Then read the page of each component you work on.

## Design

| Page | Covers |
| --- | --- |
| [Principles](principles.md) | The rules that decide trade-offs |
| [Architecture](architecture.md) | Controller model, components, deployment, consistency |
| [State machine](state-machine.md) | States, owners, message record |
| [Flows](flows.md) | Step-by-step sequence for each situation |

## Components

| Component | Owns | Page covers |
| --- | --- | --- |
| [Collector](components/collector.md) | Sources | Ingestion, `group_key`, re-entries |
| [State Store](components/state-store.md) | All state | Claim, compare-and-set, outbox, tables |
| [Enricher](components/enricher.md) | `received` | Correlated logs, statuses, reuse by group |
| [Policy Engine](components/policy-engine.md) | `enriched` | Classification and routing |
| [Transient Runner](components/transient-runner.md) | `retrying`, `held`, `replaying` | Retry, circuit breaker, probe, drain, recovery detection |
| [Runbook Runner](components/runbook-runner.md) | `runbook_matched` | Runbooks, actions, guardrails, lifecycle |
| [Poison Runner](components/poison-runner.md) | `awaiting_operator` | Grouping and context for operators |
| [Publisher](components/publisher.md) | `outbox` | Replay delivery and its guarantee |
| [Purger](components/purger.md) | Expired messages | TTL, archive, retention |
| [Analytics Engine](components/analytics-engine.md) | Change stream | Metrics, funnel, cost, recurrence, findings |
| [Alerts Watcher](components/alerts-watcher.md) | `alert_instances` | Declared alerts, audiences, context |

## Integration and operation

| Page | Covers |
| --- | --- |
| [Header contract](header-contract.md) | The headers a consumer sends and receives |
| [Plugins](plugins.md) | Plugin contracts and extension levels |
| [Configuration](configuration.md) | Runtime settings and resource reference |
| [Operations](operations.md) | Interfaces, operator actions, audit |

## Project

| Page | Covers |
| --- | --- |
| [Use cases](use-cases.md) | How the mix of failures changes by scenario |
| [Roadmap](roadmap.md) | V0 scope, milestones, non-goals, open questions |
| [RFC 0001](rfc/0001-opendlq.md) | Why OpenDLQ exists and the alternatives considered |
