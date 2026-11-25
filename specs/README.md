# Specifications

Executable descriptions of how a message moves through OpenDLQ, in [Gherkin](https://cucumber.io/docs/gherkin/reference/). Like [docs/](../docs/README.md), they describe the target design, independent of version. They will run as acceptance tests in Go with `godog`.

## Two levels

| File | Describes |
| --- | --- |
| [journeys.feature](flows/journeys.feature) | The whole life of a message, from `received` to a terminal state, one scenario per path. Read this first |
| The other features | One area each, with every rule and every problem |

| Feature | Covers |
| --- | --- |
| [ingestion](flows/ingestion.feature) | New message, duplicate delivery, undecodable payload, store down |
| [enrichment](flows/enrichment.feature) | Every `enrichment_status`, reuse by group, wait mode |
| [classification](flows/classification.feature) | The five signals, their precedence, routing |
| [transient](flows/transient.feature) | Retry schedule, exhaustion, failed replays |
| [breaker](flows/breaker.feature) | Opening the circuit, probe, drain |
| [confirmation](flows/confirmation.feature) | Ack and silence modes, timeouts, late and duplicate acks |
| [runbook](flows/runbook.feature) | Match, actions, approval, guardrails, failure, expiry |
| [operator](flows/operator.feature) | Replay, edit, reclassify, discard, batches |
| [reentry](flows/reentry.feature) | A replay that fails again, Publisher copies |
| [expiry](flows/expiry.feature) | TTL from every open state, retention |
| [concurrency](flows/concurrency.feature) | Races between controllers and events |

## Tags

| Tag | Means |
| --- | --- |
| `@transition:<from>-><to>` | The transition of the [state machine](../docs/state-machine.md#transitions) this scenario covers. `new` is the entry, `open` is any open state |
| `@default` | Holds with no configuration |
| `@config:<key>=<value>` | Holds only with this setting |
| `@failure` | A problem path: something outside OpenDLQ failed |
| `@edge` | An [edge case](../docs/state-machine.md#edge-cases) |

Every transition of the state machine has at least one scenario. A scenario with no `@transition` tag checks a rule that does not move the message.

## Defaults used

Unless a scenario says otherwise, these defaults apply. They are the defaults of the [configuration reference](../docs/configuration.md).

| Setting | Value |
| --- | --- |
| `retry` | max 5, base 30s, factor 2, cap 30m, jitter 0 in scenarios |
| `breaker` | 20 distinct failures in 60s |
| `probe` | canary every 30s, doubling up to 5m |
| `drain.rate` | 50 msg/s |
| `recovery` | mode `ack`, timeout 10s |
| `enrichment` | timeout 3s, retries 2, `reuse_window` 10m, `on_unavailable: continue` |
| `group_memory` | 24h |
| `inference.same_message_failures` | 3 |

Jitter is 0 in scenarios so times are exact.
