# Configuration

OpenDLQ has two layers of configuration:

| Layer | What it sets | Where it lives | Changed by |
| --- | --- | --- | --- |
| **Runtime** | How the process runs: store, controllers, API, telemetry, plugins | `opendlq.yaml` and environment variables | Deploy |
| **Resources** | What OpenDLQ does: consumers, policies, classifiers, runbooks, alerts, providers | YAML resources in a configuration repository | `opendlq apply` |

## Runtime

```yaml
# opendlq.yaml
store:
  dsn: ${OPENDLQ_STORE_DSN}          # Postgres
controllers: [collector, policy, transient, runbook, poison, enricher, publisher, purger, analytics, alerts]
api:
  listen: :8080
  mcp: true
telemetry:
  otlp_endpoint: ${OTEL_EXPORTER_OTLP_ENDPOINT}
  prometheus: :9090                  # serves /metrics
plugins:
  dir: ./plugins                     # out-of-process plugins
```

`controllers` lists which controllers this process runs. One binary can run all of them, or each deployment can run a subset to scale them separately.

## Resources

Every resource is a YAML document with `kind`, `metadata` and `spec`, in the style of Kubernetes.

| Kind | Declares | Scope |
| --- | --- | --- |
| [`Provider`](#provider) | A connection to an external system: log backend, notification channel, archive | Global |
| [`Consumer`](#consumer) | A DLQ to watch, where replays go, how to decode, how to group and enrich | One consumer |
| [`Policy`](#policy) | Retry, circuit breaker, probe, recovery detection, TTL, retention | Default or one consumer |
| [`Classifier`](#classifier) | Classification rules or plugin | Default or one consumer |
| [`Runbook`](#runbook) | The handling of a known permanent failure | One consumer or global |
| [`Alert`](#alert) | A condition and its audience | One consumer or global |

### Defaults and overrides

A `Policy` or `Classifier` without `metadata.consumer` is the default for every consumer. A resource with `metadata.consumer` overrides the default field by field. `opendlq diff` shows the effective values for each consumer.

### Provider

```yaml
kind: Provider
metadata:
  name: loki-prod
spec:
  type: loki                          # log provider plugin
  url: https://loki.internal
  auth: { secret_ref: loki-token }
  link_template: "https://grafana.internal/explore?traceId={{trace_id}}"
```

| Field | Meaning |
| --- | --- |
| `type` | Plugin: `loki`, `elasticsearch`, `cloudwatch-logs`, `datadog-logs`, `slack`, `pagerduty`, `opsgenie`, `webhook`, `s3` |
| `auth.secret_ref` | Name of a secret. Secrets never go in the resource |
| `link_template` | URL template for deep links, used even without API access |

### Consumer

```yaml
kind: Consumer
metadata:
  name: order-events
spec:
  source:    { plugin: kafka, topic: order-events.dlq, group: opendlq }
  replay_to: { plugin: kafka, topic: order-events }
  serde: json
  group_key: 'headers["x-failure-reason"]'
  correlation_headers: [traceparent, x-request-id]
  enrichment:
    sources:
      - provider: loki-prod
        extract:
          error_class: 'log.json.error.type'
    timeout: 3s
    retries: 2
    backoff: 1s
    reuse_window: 10m
```

| Field | Default | Meaning |
| --- | --- | --- |
| `source` | — | Where the DLQ is |
| `replay_to` | Original topic from headers | Where replays go |
| `serde` | `json` | How to decode and encode payloads |
| `correlation_headers` | `[traceparent]` | Headers to extract for enrichment and tracing |
| `enrichment.sources` | none | Providers to query, each with an `extract` map of JSON paths. Without sources, enrichment is `skipped` |
| `enrichment.timeout`, `retries`, `backoff` | `3s`, `2`, `1s` | Bound the time a message waits before classification. See [enrichment](components/enricher.md) |
| `enrichment.reuse_window` | `10m` | Reuse a recent result for the same `group_key` instead of querying again |
| `group_key` | `headers["x-failure-reason"]` | CEL expression the Collector uses to group messages |

### Policy

```yaml
kind: Policy
metadata:
  name: order-events
  consumer: order-events
spec:
  retry:    { max: 5, base: 30s, factor: 2, cap: 30m, jitter: 0.2 }
  breaker:  { window: 60s, threshold: 20 }
  probe:    { type: canary, every: 30s, cap: 5m }
  drain:    { rate: 50 }
  recovery: { mode: ack, topic: opendlq.ack, timeout: 10s }
  ttl: 72h
  retention: { payload: 30d, archive: s3-archive }
```

| Field | Default | Meaning |
| --- | --- | --- |
| `retry` | 5, 30 s, ×2, 30 min, ±20% | Backoff for transient failures. See [recovery](components/transient-runner.md) |
| `breaker.window`, `threshold` | `60s`, `20` | Distinct transient failures on one dependency that open the circuit |
| `probe.type` | `canary` | `canary` or `health_check` (with `url`) |
| `probe.every`, `cap` | `30s`, `5m` | Probe interval and its ceiling as it doubles |
| `drain.rate` | `50` | Messages per second after the circuit closes |
| `recovery.mode` | `ack` | `ack` or `silence` (with `window`) |
| `ttl` | none | Open messages expire after this time |
| `retention.payload` | `30d` | How long payloads are kept after a message closes |
| `retention.archive` | none | A `Provider` to archive payloads before deletion |

### Classifier

```yaml
kind: Classifier
metadata:
  name: order-events
  consumer: order-events
spec:
  transient: [timeout, 5xx, 429, connection_refused, deadlock]
  permanent: [4xx, parse_error, validation, nil_dereference]
  rules:
    - when: 'enrichment.error_class == "PoolExhaustedException"'
      kind: transient
      dependency: orders-db
  group_memory: 24h
  inference: { same_message_failures: 3 }
  plugin: none
```

| Field | Default | Meaning |
| --- | --- | --- |
| `transient`, `permanent` | Built-in lists | Error types per kind. See [classification](components/policy-engine.md) |
| `rules` | none | CEL rules over headers, error and enrichment fields, each with a `kind` and an optional `dependency` |
| `group_memory` | `24h` | How long a group's classification applies to new messages of the same `group_key` |
| `inference.same_message_failures` | `3` | Repeated failures with the same error that make a message permanent |
| `plugin` | none | A classifier plugin replaces the rules |

### Runbook

See [runbooks](components/runbook-runner.md) for `match`, `action` and the required `guardrails`.

### Alert

```yaml
kind: Alert
metadata:
  name: order-events-new-group
  consumer: order-events
spec:
  when: event == "poisoned" and group.is_new
  severity: page
  audience: operational
  notify: [pagerduty-oncall]
  dedupe: 30m
```

| Field | Default | Meaning |
| --- | --- | --- |
| `when` | — | CEL expression over events, metrics and recurrence. See [alerts](components/alerts-watcher.md) |
| `severity` | `report` | `page` or `report` |
| `audience` | `operational` | `operational` or `decision` |
| `notify` | — | One or more notifier `Provider` names |
| `schedule` | none | Send as a digest (`daily`, `weekly`) instead of per event |
| `dedupe` | `30m` | Window in which the same alert for the same group is not repeated |

## Applying changes

```sh
opendlq diff   -f ./config/   # declared vs. applied, with effective values
opendlq apply  -f ./config/   # apply the declared state
opendlq export <kind>/<name>  # write the applied state back to a file
```

Resources are versioned on apply. Every state transition records the version of the resource that decided it.

## Drift

When a resource is declared in a file, the file is the source of truth. A change made through the API or the UI to a declared resource is recorded as **drift** and shows up in `opendlq diff`. The operator chooses:

- `opendlq export` to bring the change into the file, or
- `opendlq apply` to restore the file and discard the change.

One-off actions (replay, discard, reclassify, approve a runbook run) are not resources and do not cause drift.

## Agents

AI agents use the same path as people: edit the YAML, run `opendlq diff`, open a pull request. Changes go through the same review. There is no privileged API.
