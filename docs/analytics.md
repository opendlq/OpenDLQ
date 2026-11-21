# Analytics

OpenDLQ measures what happens to failed messages, so the engineering team can see what to fix. Analytics read only the state store and the audit log. No metric depends on the content of a message.

Analytics are eventually consistent, with a declared maximum lag. State, replay and audit are not.

## Base metrics

Per consumer, cause, dependency and day:

- Messages in. Messages out, by destination.
- Age of open messages: mean, p95, max. **Max age is the main alert.** Queue depth hides old messages at the back.
- Self-recovery rate: the share of messages that left without human action. This is the metric of the transient path.
- Time to triage for permanent failures: from arrival to the first operator action.
- Attempts per recovered message.
- Time with the circuit open, per dependency.

## Resolution funnel

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

## Cost

Each failed message accumulates cost in three parts:

| Part | Calculation |
| --- | --- |
| Storage | Bytes × time in the state store |
| Replay | Attempts × configurable unit cost |
| Operator | Minutes of human action in the audit log × configurable hourly cost |

Summed per cause and per consumer, cost answers two questions: how much a cause cost in the period, and which consumer is the largest share. The cost trend is the argument for fixing upstream instead of replaying forever.

## Recurrence

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

A cause with three or more episodes and growing cost raises a recurrence alert. See [alerts](alerts.md).

## Export

Instrumentation uses OpenTelemetry:

- Metrics and traces go out over OTLP to any compatible backend.
- The same metrics are also exposed on a Prometheus endpoint, `/metrics`, for teams that scrape.
- A replay continues the original trace when the message carries `traceparent`. The full chain shows in your tracing tool: original failure, DLQ, replay, success.

Detailed queries (funnel, cost, recurrence) are available on `/analytics`. Dashboards belong in the tools the team already uses, not in OpenDLQ.

## Storage

In V0, analytics are SQL over the state store, with hourly and daily rollups. When volume grows, the `transitions` table moves to a columnar database through change data capture. The transactional side does not change.
