# Alerts

Alerts are declared, not configured in a UI. Each alert is an `Alert` resource in the configuration repository. `notify` names notifier `Provider` resources. The full field reference is in [configuration](configuration.md#alert).

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
  enrichment: { mode: wait, max_wait: 30s }
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
```

## Two audiences

OpenDLQ separates alerts by who should act:

| Kind | For | Examples |
| --- | --- | --- |
| **Operational** | The person on call | Retries exhausted, new permanent group, circuit open too long, max age above threshold |
| **Decision** | Whoever sets priorities | A cause keeps coming back, cost growing, a runbook about to expire |

An operational alert says "act now". A decision alert says "this keeps costing us, fix the root cause". Mixing them trains people to ignore both.

## Conditions

An alert condition is an expression over events and metrics:

| Source | Examples |
| --- | --- |
| Events | `exhausted`, `poisoned` (new message waiting for an operator), `circuit_opened`, `runbook_step`, `runbook_expiring` |
| Metrics | `max_age`, `open_count`, `self_recovery_rate`, `time_to_triage` |
| Recurrence | `recurrence.episodes`, `recurrence.cost_trend` |

## Context in every notification

An alert that fires with no context starts the investigation from zero. Every notification carries:

- The cause and its grouping key.
- How many messages, since when, and the trend.
- A sample payload and error.
- The correlated log snippet, or the reason it is missing ("logs unavailable", "no matching logs").
- Links: the group in OpenDLQ, the logs, the trace.
- The matching runbook, if one exists.

## Alerts wait for enrichment

By default an alert is not sent while its enrichment is still `pending`. Each alert chooses how long to wait:

| `enrichment.mode` | Behavior |
| --- | --- |
| `required` (default) | Wait until enrichment reaches a final status: `enriched`, `not_found` or `unavailable` |
| `wait` | Wait up to `max_wait`, then send with what exists |
| `best_effort` | Send immediately |

When enrichment finishes after the alert was sent, the Alerts Watcher sends a follow-up. A logging outage delays alerts by a bounded time but never silences them. See [enrichment](enrichment.md).

## Who sends notifications

Only the Alerts Watcher. The other components emit events and never notify directly. Each alert is an alert instance in the state store (`pending_enrichment`, `sent`, `followed_up`), so a restart never loses or repeats a notification. This keeps every alert rule in one place, declared and reviewed.

Notification channels are plugins: Slack, PagerDuty, Opsgenie, webhook. `dedupe` keeps the same alert for the same group from repeating within a window.
