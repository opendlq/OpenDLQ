# Analytics Engine

Turns the history of state changes into metrics, trends and findings. It reads. It never changes a message.

| | |
| --- | --- |
| Reads | Change stream of `transitions` |
| Writes | Analytics store; `findings` |
| Plugins | Analytics store: `postgres`, `duckdb`, `clickhouse` |
| Scales | One active instance per replication slot. Queries scale with the analytics store |

## Responsibility

1. **Ingest.** Read every transition in commit order and write it to the analytics store.
2. **Compute.** Base metrics, resolution funnel, cost and recurrence, per consumer, cause, dependency and period.
3. **Detect.** Compare current behavior with its history and record what looks abnormal as a [finding](#findings).
4. **Serve.** Answer queries on `/analytics`, the CLI and MCP. Export metrics over OpenTelemetry and `/metrics`.

## Does not

- Notify. A finding is data. The [Alerts Watcher](alerts-watcher.md) decides whether it becomes a notification.
- Change the state of a message.
- Read payloads. No metric depends on the content of a message.
- Carry real-time alerts. It lags by design. An incident alert reads transitions directly, through the Alerts Watcher.

## Pipeline

```
Postgres (logical replication slot) → Analytics Engine → analytics store
```

- The engine reads the slot directly, with the Postgres replication protocol. No broker and no CDC service in between.
- The publication contains only `transitions`. That table is the fact table: every metric derives from it.
- The engine confirms its position in the slot only after the write to the analytics store. A crash replays from the last confirmed position. Writes are idempotent by transition `id`.
- The slot keeps WAL until the engine confirms it. Set `max_slot_wal_keep_size` on Postgres. The engine reports its lag as `opendlq_analytics_lag_seconds`.
- The analytics store is derived data. `transitions` is never purged, so the store can be rebuilt from it at any time: snapshot, then stream.

Why not poll `transitions` by increasing `id`: ids are assigned before commit, so a smaller id can commit after a larger one. A watermark on `id` skips it. The replication stream delivers in commit order.

Analytics are eventually consistent, with a declared maximum lag (`max_lag`). Above it, the engine records an `analytics_lag` finding. State, replay and audit never lag.

## Analytics store

| Backend | Runs as | For |
| --- | --- | --- |
| `postgres` | Tables in the State Store database | Small installations. No extra process |
| `duckdb` | Embedded in the engine, a local file | Single node with more volume. No extra process |
| `clickhouse` | External server | Large installations |

All backends answer the same queries. Changing the backend changes no metric.

## What it computes

### Base metrics

Per consumer, cause, dependency and day:

- Messages in. Messages out, by destination.
- Age of open messages: mean, p95, max. **Max age is the main alert.** Queue depth hides old messages at the back.
- Self-recovery rate: the share of messages that left without human action. This is the metric of the transient path.
- Time to triage for permanent failures: from arrival to the first operator action.
- Attempts per recovered message.
- Time with the circuit open, per dependency.

### Resolution funnel

For each period and each cut (consumer, cause, dependency), where every message ended:

| Outcome | Meaning |
| --- | --- |
| Recovered on its own | Transient path, no human involved |
| Replayed by an operator | Permanent, fixed by a person |
| Handled by a runbook | Permanent, fixed by a declared decision |
| Routed | Sent to another destination |
| Discarded | Dropped with a reason |
| Expired | TTL reached |
| Still open | Waiting |

Each outcome comes with the distribution of time to reach it. The funnel answers three questions: what we solve on our own, what needs people, and what is stuck.

### Cost

Each failed message accumulates cost in three parts:

| Part | Calculation |
| --- | --- |
| Storage | Bytes × time in the state store |
| Replay | Attempts × configurable unit cost |
| Operator | Minutes of human action in the audit log × configurable hourly cost |

Summed per cause and per consumer, cost answers two questions: how much a cause cost in the period, and which consumer is the largest share. The cost trend is the argument for fixing upstream instead of replaying forever.

### Recurrence

A recurrence is the same cause coming back after it was handled. OpenDLQ detects three forms:

1. **Same message.** Replayed, then back in the DLQ with the same `x-dlq-id`. The fix did not work, or the problem is a different one.
2. **Same cause, new messages.** A grouping key comes back after a period with no occurrences. The root cause was never fixed.
3. **Same dependency.** The circuit breaker for a dependency opens again and again. The dependency is unstable.

For each cause, OpenDLQ keeps:

- First and last occurrence.
- Number of episodes. An episode is a window of occurrences, separated from the next by a configurable silence period.
- Messages per episode.
- Accumulated cost.
- Trend: growing, stable, falling.

A cause with three or more episodes and growing cost produces a `recurrence` finding. See [findings](#findings).

## Findings

A finding is an abnormal pattern, recorded with its evidence. Findings are stored in the State Store, so the CLI, the API, MCP and the Alerts Watcher read them in one place.

| Field | Holds |
| --- | --- |
| `detector` | Which detector found it |
| `subject` | Consumer, `group_key` or dependency |
| `observed`, `expected` | The value now and the baseline |
| `score` | Distance from the baseline, in standard deviations |
| `window` | The period evaluated |
| `status` | `open` or `closed` |
| `opened_at`, `closed_at` | Lifecycle |

### Detectors

Built in. Statistical, no machine learning.

| Detector | Opens when |
| --- | --- |
| `rate` | The DLQ inflow of a consumer is above its seasonal baseline: same hour of the week, previous weeks, smoothed with EWMA |
| `new_group` | A `group_key` appears that was not seen in the lookback period |
| `recurrence` | A cause has three or more episodes and growing cost |
| `mix_shift` | The share of permanent failures in a consumer or group rises above its baseline |
| `self_recovery_drop` | The self-recovery rate falls below its baseline |
| `unstable_dependency` | The circuit breaker of a dependency opens repeatedly in the window |
| `analytics_lag` | The engine is behind by more than `max_lag` |

### Rules

- **Warm-up.** A detector needs a baseline. No baseline-based finding opens for a subject with less history than `warmup`.
- **Minimum volume.** A window with fewer than `min_events` events is not evaluated. Low volume produces noise, not signal.
- **Sensitivity.** `low`, `medium` and `high` set the score threshold: 4, 3 and 2 standard deviations.
- **One open finding per detector and subject.** A finding updates while it stays open.
- **Closing.** A finding closes when the value stays within the baseline for one full window.

Real-time and trend signals have separate paths:

| | Alerts Watcher on transitions | Analytics Engine findings |
| --- | --- | --- |
| Source | State Store | Analytics store |
| Latency | Seconds | Lag plus window |
| Example | Retries exhausted; new poisoned group | Inflow of a consumer 4σ above the usual for this hour |
| Nature | Deterministic | Statistical |

## Configuration

Runtime settings in `opendlq.yaml`:

```yaml
analytics:
  store: { type: postgres }        # postgres | duckdb | clickhouse
  slot: opendlq_analytics
  max_lag: 60s
  detectors:
    sensitivity: medium
    warmup: 14d
    min_events: 30
    lookback: 30d
```

Detectors are built in. Alerting on a finding is declared in an `Alert` resource. See [alerts](alerts-watcher.md#conditions).

## Export

Instrumentation uses OpenTelemetry:

- Metrics and traces go out over OTLP to any compatible backend.
- The same metrics are also exposed on a Prometheus endpoint, `/metrics`, for teams that scrape.
- A replay continues the original trace when the message carries `traceparent`. The full chain shows in your tracing tool: original failure, DLQ, replay, success.

Detailed queries (funnel, cost, recurrence, findings) are available on `/analytics`, the CLI and MCP. Dashboards belong in the tools the team already uses, not in OpenDLQ.
