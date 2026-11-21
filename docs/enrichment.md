# Enrichment

Enrichment adds context that the DLQ does not have: the application logs and the trace of the failure. An alert or a group page without that context starts the investigation from zero, so OpenDLQ treats enrichment as part of the alert path, not as an extra.

Enrichment never runs inside the Collector. Ingestion must not depend on the logging backend: if that backend is slow or down, messages are still stored and classified.

## What gets enriched

When a consumer sends a message to the DLQ, it usually also writes an error log with correlation IDs: trace ID, span ID, message ID, request ID. The Collector extracts those IDs from the headers and stores them. The Enricher uses them to fetch the matching logs.

Enriching every message would be expensive and rarely useful: a thousand messages with the same cause have the same story. The Enricher works on a sample:

- The first `sample_per_group` messages of every new group (default 3).
- Any message that is the subject of an alert.
- Any message an operator opens, on demand.

## Enrichment status

Every message has an enrichment status:

| Status | Meaning |
| --- | --- |
| `skipped` | Not sampled, or no correlation IDs. No lookup will happen |
| `pending` | Waiting for the first lookup or for a retry |
| `enriched` | Logs found. A link and a short snippet are stored |
| `not_found` | Lookups finished; no matching logs |
| `unavailable` | The log provider failed on every retry |

`enriched`, `not_found` and `unavailable` are final. The time to reach a final status is bounded:

```
max time = delay + retries × (timeout + backoff)
```

With the defaults (15 s delay, 3 retries, 10 s timeout, 5 s backoff) that is at most 60 s.

## Indexing delay

A log is often not searchable yet when the message reaches the DLQ. The Enricher waits `delay` after the failure timestamp before the first lookup. A lookup with no result before the last retry counts as "not indexed yet", not as `not_found`.

## Alerts wait for enrichment

Each `Alert` declares how it relates to enrichment:

| Mode | Behavior | Use for |
| --- | --- | --- |
| `required` (default) | The alert waits until enrichment reaches a final status. It is never sent while enrichment is `pending`. | Most alerts |
| `wait` | The alert waits up to `max_wait`, then is sent with whatever exists. | Pages where seconds matter |
| `best_effort` | The alert is sent immediately. | Low-value or very high-volume alerts |

In every mode, when enrichment finishes after the alert was sent, the Alerts Watcher sends a follow-up (a thread reply or an update, if the notifier supports it).

### Why there is no "never send without logs" mode

If an alert waited until logs were found, a logging backend outage would silence every alert, exactly when the system is most likely to be failing. `required` waits for a final status, and `unavailable` is a final status. The alert is then sent and says so: "logs unavailable: provider `loki-prod` failed 3 lookups".

The wait is bounded by the formula above, so `required` delays an alert by at most about a minute with the defaults.

## Configuration

Enrichment is configured per consumer:

```yaml
kind: Consumer
metadata:
  name: order-events
spec:
  correlation_headers: [traceparent, x-request-id]
  enrichment:
    provider: loki-prod        # a Provider resource
    sample_per_group: 3
    delay: 15s
    timeout: 10s
    retries: 3
    backoff: 5s
```

Alert gating is configured per alert:

```yaml
kind: Alert
metadata:
  name: order-events-new-group
  consumer: order-events
spec:
  when: event == "poisoned" and group.is_new
  severity: page
  notify: [pagerduty-oncall]
  enrichment: { mode: required }
```

The log provider itself is a `Provider` resource. See [configuration](configuration.md#provider).

## Deep links without an API

When the logging backend has no API access, OpenDLQ still builds a link from a URL template (Grafana Explore, Kibana Discover, Datadog Log Explorer). The status is then `skipped`, and alerts carry the link without a snippet.
