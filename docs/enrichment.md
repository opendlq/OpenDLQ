# Enrichment

Enrichment adds the context the DLQ does not have: the application logs and the trace of the failure. Every message is enriched before it is classified, so the Policy Engine decides with that context, and every alert about a message already carries it.

## Where it sits

```
received → [Enricher] → enriched → [Policy Engine] → ...
```

- The **Enricher** owns `received`. It queries the sources configured for the consumer, stores the result and moves the message to `enriched`.
- The **Policy Engine** owns `enriched`. When it classifies, headers, history and logs are all in the store.
- A consumer with no sources configured passes straight through: the Enricher moves the message to `enriched` without querying anything.

The Collector never queries external systems. Ingestion does not depend on the logging backend.

## Enrichment never blocks

If a source fails or takes too long, the message still moves to `enriched`, with the status `unavailable`. The Policy Engine then classifies without logs. A logging outage makes classification less informed, never stuck.

| Status | Meaning |
| --- | --- |
| `enriched` | Logs found. Extracted fields, a snippet and a link are stored |
| `reused` | A recent result for the same group was reused. No query was made |
| `not_found` | Queries finished with no matching logs |
| `unavailable` | The source failed or timed out on every attempt |
| `skipped` | No sources configured, or no correlation IDs to query with |

The time a message can spend in `received` is bounded by `timeout × (retries + 1)` plus backoff. With a healthy log backend it is a few seconds: the consumer usually writes its error log before it publishes to the DLQ, and log pipelines make logs searchable within seconds.

## Reuse by group

A thousand messages with the same error tell the same story, and log APIs charge per query and limit the request rate. The Enricher reuses results:

- Every message has a `group_key`, computed by the Collector from headers (by default `x-failure-reason`).
- If a message with the same `group_key` was enriched within `reuse_window`, the Enricher links to that result and marks the message `reused`. No query is made.
- The first message of a new group always pays for a query.

## What is stored

Results go to an `enrichments` table, separate from `messages`, written in the same transaction as the state change. The Policy Engine never sees `enriched` without the data.

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

## Sources

Each consumer lists one or more sources. Each source is a `Provider` (see [configuration](configuration.md#provider)) and an extraction:

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

`extract` maps JSON paths in the log to fields in `data`. The Policy Engine and classifier rules can read those fields. See [classification](classification.md).

## On demand

An operator can ask for a message to be enriched again, for example after the log backend recovers. The new result replaces the reference and is recorded in the audit log. It never changes a decision already taken.

## Deep links without an API

When the log backend has no API access, OpenDLQ still builds a link from the provider's `link_template` (Grafana Explore, Kibana Discover, Datadog Log Explorer). The status is `skipped` and the message carries the link without a snippet.
