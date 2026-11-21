# Configuration

[Português](configuration.pt-BR.md)

All OpenDLQ configuration is a set of declarative resources, in the style of Kubernetes: one YAML document per resource, with `kind`, `metadata` and `spec`.

## Resources

| Kind | What it declares |
| --- | --- |
| `Consumer` | A consumer: its DLQ source, original topic, serializer, correlation headers |
| `Policy` | Retry, circuit breaker, probe, recovery detection and TTL for a consumer |
| `Classifier` | Classification rules, or the classifier plugin to use |
| `Runbook` | The handling of a known permanent failure. See [runbooks](runbooks.md) |
| `Alert` | An alert condition and where it goes. See [alerts](alerts.md) |

```yaml
kind: Consumer
metadata:
  name: order-events
spec:
  source: { plugin: kafka, topic: order-events.dlq }
  replay_to: { plugin: kafka, topic: order-events }
  serde: json
  correlation_headers: [traceparent, x-request-id]
---
kind: Classifier
metadata:
  name: order-events-rules
  consumer: order-events
spec:
  transient: [timeout, 5xx, 429, connection_refused, deadlock]
  permanent: [4xx, parse_error, validation, nil_dereference]
```

## Two ways to operate, one effect

- **Declarative.** The files live in a repository. Changes go through pull request and review.
- **Interactive.** API, CLI and UI, for one-off actions and for exploring.

```sh
opendlq diff   -f ./config/   # declared vs. applied
opendlq apply  -f ./config/   # apply the declared state
opendlq export <kind>/<name>  # write the applied state back to a file
```

## Drift

When a resource is declared in a file, the file is the source of truth. A change made through the API or the UI to a declared resource is recorded as **drift** and shows up in `opendlq diff`. The operator chooses:

- `opendlq export` to bring the change into the file, or
- `opendlq apply` to restore the file and discard the change.

One-off actions (replay, discard, reclassify, approve a runbook run) are not resources and do not cause drift.

## Agents

AI agents use the same path as people: edit the YAML, run `opendlq diff`, open a pull request. Changes go through the same review. There is no privileged API.
