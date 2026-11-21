# Alerts

[Português](alerts.pt-BR.md)

Alerts are declared, not configured in a UI. Each alert is an `Alert` resource in the configuration repository.

```yaml
kind: Alert
metadata:
  name: order-events-stuck
  consumer: order-events
spec:
  when: max_age > 2h
  severity: page
  notify: [pagerduty:payments-oncall]
---
kind: Alert
metadata:
  name: recurring-causes
spec:
  when: recurrence.episodes >= 3 and recurrence.cost_trend == "growing"
  severity: report
  notify: [slack:#eng-priorities]
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
- The correlated log snippet, when available.
- Links: the group in OpenDLQ, the logs, the trace.
- The matching runbook, if one exists.

## Who sends notifications

Only the Alerts Watcher. The other components emit events and never notify directly. This keeps every alert rule in one place, declared and reviewed.

Notification channels are plugins: Slack, PagerDuty, Opsgenie, webhook.
