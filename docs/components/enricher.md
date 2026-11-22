# Enricher

Fetches the context the DLQ does not have, before the message is classified.

| | |
| --- | --- |
| Watches | `received` |
| Writes | `enrichments` row; `ready`, or `awaiting_operator` after `max_wait` |
| Plugins | Log Provider |
| Scales | N instances, by claim |

## Does not

- Classify. It only adds data for the Policy Engine.
- Block by default. On failure or timeout the message moves on as `unavailable`. A consumer can choose to wait, always with a maximum.
- Copy logs. It stores a short extract and a link.

## How enrichment works

Enrichment adds the context the DLQ does not have: the application logs and the trace of the failure. Every message is enriched before it is classified, so the Policy Engine decides with that context, and every alert about a message already carries it.

### Where it sits

```
received → [Enricher] → ready → [Policy Engine] → ...
```

- The **Enricher** owns `received`. It queries the sources configured for the consumer, stores the result and moves the message to `ready`.
- The **Policy Engine** owns `ready`. When it classifies, headers, history and logs are all in the store.
- A consumer with no sources configured passes straight through: the Enricher moves the message to `ready` without querying anything.

The Collector never queries external systems. Ingestion does not depend on the logging backend.

### When a source is unavailable

By default, if a source fails or takes too long, the message still moves to `ready`, with the status `unavailable`. The Policy Engine then classifies without logs. A logging outage makes classification less informed, never stuck.

A consumer that does not accept deciding without logs sets `on_unavailable: wait`:

| `on_unavailable` | `after_max_wait` | Source down |
| --- | --- | --- |
| `continue` (default) | — | Classify without logs, as `unavailable` |
| `wait` | `continue` | Keep the message in `received` and try again until `max_wait`, then classify without logs |
| `wait` | `operator` | Keep the message in `received` and try again until `max_wait`, then send it to `awaiting_operator` |

A wait always has a maximum. No external dependency holds a message forever. See [guarantees](../guarantees.md#5-state-fails-closed-context-fails-open-by-default).

The outcome is stored on the message as `enrichment_status`, an enum. The state does not say whether enrichment succeeded. `ready` only means the Policy Engine can decide.

| `enrichment_status` | Meaning |
| --- | --- |
| `pending` | Not tried yet, or trying again with `on_unavailable: wait` |
| `enriched` | Logs found. Extracted fields, a snippet and a link are stored |
| `reused` | A recent result for the same group was reused. No query was made |
| `not_found` | Queries finished with no matching logs |
| `unavailable` | The source failed or timed out on every attempt |
| `skipped` | No sources configured, or no correlation IDs to query with |

The time a message can spend in `received` is bounded by `timeout × (retries + 1)` plus backoff. With a healthy log backend it is a few seconds: the consumer usually writes its error log before it publishes to the DLQ, and log pipelines make logs searchable within seconds.

### Reuse by group

A thousand messages with the same error tell the same story, and log APIs charge per query and limit the request rate. The Enricher reuses results:

- Every message has a `group_key`, computed by the Collector from headers (by default `x-failure-reason`).
- If a message with the same `group_key` was enriched within `reuse_window`, the Enricher links to that result and marks the message `reused`. No query is made.
- The first message of a new group always pays for a query.

### What is stored

Results go to an `enrichments` table, separate from `messages`, written in the same transaction as the state change. The Policy Engine never sees `ready` without the data.

| Column | Type | Holds |
| --- | --- | --- |
| `id` | UUID | Identity of the result |
| `group_key` | string | The group the result belongs to, for reuse |
| `source` | string | The `Provider` that answered |
| `status` | enum | See above |
| `data` | JSONB | Extracted fields: service, error class, top of the stack trace, trace ID, plus a short snippet |
| `link` | string | Deep link to the logs (Grafana, Kibana, Datadog) |
| `fetched_at` | timestamp | When the query ran |

Messages reference the result by `enrichment_id`.

`data` is bounded in size (default 16 KB). It is an extract, not a copy: the full logs stay in the log backend, which is the right place to search them. Strong consistency applies to the state and the reference between message and result. The content is a copy of external data and does not need to be fresher than a few seconds.

### Sources

Each consumer lists one or more sources. Each source is a `Provider` (see [configuration](../configuration.md#provider)) and an extraction:

```yaml
kind: Consumer
metadata:
  name: order-events
spec:
  correlation_headers: [traceparent, x-request-id]
  enrichment:
    sources:
      - provider: loki-prod
        extract:
          service: 'log.labels.service'
          error_class: 'log.json.error.type'
          stack_top: 'log.json.error.stack[0]'
    timeout: 3s
    retries: 2
    backoff: 1s
    reuse_window: 10m
```

`extract` maps JSON paths in the log to fields in `data`. The Policy Engine and classifier rules can read those fields. See [classification](policy-engine.md).

### Enriching again

A message is enriched again in three cases. Only the first one can change a decision, because the message goes through classification again.

| When | Why |
| --- | --- |
| Re-entry: a replay failed and the message is back in `received` | The new failure may have new logs |
| The message reaches `awaiting_operator` with `unavailable` | The operator should see the logs. Runs in the background |
| An operator asks for it | For example, after the log backend recovers |

In the last two cases the new result replaces the reference and is recorded in the audit log. It never changes a decision already taken.

### Deep links without an API

When the log backend has no API access, OpenDLQ still builds a link from the provider's `link_template` (Grafana Explore, Kibana Discover, Datadog Log Explorer). The status is `skipped` and the message carries the link without a snippet.
