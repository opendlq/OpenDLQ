# Alerts Watcher

Turns events and findings into notifications. It is the only component that notifies.

| | |
| --- | --- |
| Watches | Events in `transitions`; `findings`; metrics |
| Writes | `alert_instances`: `pending`, `sent` |
| Plugins | Notifier |
| Scales | One active instance per alert, by claim on the alert instance |

## Responsibility

- Evaluate every `Alert` resource against three inputs: events in `transitions` (seconds after they commit), metrics (on each evaluation), and [findings](analytics-engine.md#findings) of the Analytics Engine (when they open or close).
- Create one alert instance per alert and subject, with `dedupe` applied. Ten thousand messages in one group produce one instance.
- Build the context of the notification. See [context in every notification](#context-in-every-notification).
- Deliver through a Notifier, then mark the instance `sent`. Digests (`schedule`) collect instances and send them together.

## Does not

- Detect anomalies. The Analytics Engine does, and records findings.
- Change the state of a message.

## Alerts

Alerts are declared, not configured in a UI. Each alert is an `Alert` resource in the configuration repository. `notify` names notifier `Provider` resources. The full field reference is in [configuration](../configuration.md#alert).

```yaml
kind: Alert
metadata:
  name: order-events-stuck
  consumer: order-events
spec:
  when: max_age > 2h
  severity: page
  audience: operational
  notify: [pagerduty-oncall]
---
kind: Alert
metadata:
  name: recurring-causes
spec:
  when: recurrence.episodes >= 3 and recurrence.cost_trend == "growing"
  severity: report
  audience: decision
  notify: [slack-eng-priorities]
  schedule: weekly
---
kind: Alert
metadata:
  name: inflow-anomaly
spec:
  when: finding.detector == "rate" and finding.score >= 3
  severity: report
  audience: operational
  notify: [slack-oncall]
  dedupe: 2h
```

### Two audiences

OpenDLQ separates alerts by who should act:

| Kind | For | Examples |
| --- | --- | --- |
| **Operational** | The person on call | Retries exhausted, new permanent group, circuit open too long, max age above threshold |
| **Decision** | Whoever sets priorities | A cause keeps coming back, cost growing, a runbook about to expire |

An operational alert says "act now". A decision alert says "this keeps costing us, fix the root cause". Mixing them trains people to ignore both.

### Conditions

An alert condition is a CEL expression over events, metrics and findings:

| Source | Examples |
| --- | --- |
| Events | `exhausted`, `poisoned` (new message waiting for an operator), `circuit_opened`, `runbook_step`, `runbook_expiring` |
| Metrics | `max_age`, `open_count`, `self_recovery_rate`, `time_to_triage` |
| Recurrence | `recurrence.episodes`, `recurrence.cost_trend` |
| Findings | `finding.detector`, `finding.subject`, `finding.score`, `finding.status` |

Events and metrics come from the State Store and fire in seconds. Findings come from the Analytics Engine and carry its lag. Page on events and metrics. Use findings for trends.

### Context in every notification

An alert that fires with no context starts the investigation from zero. Every notification carries:

- The cause and its grouping key.
- How many messages, since when, and the trend.
- A sample payload and error.
- The correlated log snippet, or the reason it is missing ("logs unavailable", "no matching logs").
- Links: the group in OpenDLQ, the logs, the trace.
- The matching runbook, if one exists.

### Alerts carry enrichment

Every message is enriched before it is classified, so an alert about a message always has a final enrichment status when it fires. There is nothing to wait for. When logs are missing, the alert says why: no matching logs, or the source was unavailable. See [enrichment](enricher.md).

### Who sends notifications

Only the Alerts Watcher. Runners write transitions and the Analytics Engine writes findings. None of them notifies directly. Each alert is an alert instance in the state store (`pending`, `sent`), so a restart never loses or repeats a notification. This keeps every alert rule in one place, declared and reviewed.

Notification channels are plugins: Slack, PagerDuty, Opsgenie, webhook. `dedupe` keeps the same alert for the same group from repeating within a window.
