# Header contract

The headers a consumer sends with a failed message, and the headers OpenDLQ adds on replay. This is the only integration a consumer needs.

## Failure headers

Consumers that publish to the DLQ with these headers get the most precise classification.

| Header | Value | Required |
| --- | --- | --- |
| `x-failure-kind` | `transient` or `permanent` | Recommended |
| `x-failure-reason` | Short error description, stable across occurrences | Recommended |
| `x-failure-dependency` | Name of the dependency involved | When there is one |
| `x-attempt` | Attempt number in the consumer | Optional |

`x-failure-reason` is also the default grouping key. Keep it stable: `validation: sku format`, not the full error message with IDs in it.

## Replay headers

OpenDLQ adds two headers to every replay:

| Header | Meaning |
| --- | --- |
| `x-dlq-id` | Identity of the message in OpenDLQ. Stays the same across replays. |
| `x-dlq-attempt` | Replay attempt number |

A consumer that already processed an `x-dlq-id` successfully should skip it and acknowledge. A message that fails again after a replay goes back to the DLQ with the same `x-dlq-id`, and OpenDLQ attaches the new failure to the existing record.

## Acknowledgement

With recovery mode `ack`, the consumer publishes a record to `opendlq.ack` after it processes a replay:

| Field | Value |
| --- | --- |
| `x-dlq-id` | From the replay headers |
| `x-dlq-attempt` | From the replay headers |

An ack for an older attempt is ignored. With mode `silence`, the consumer publishes nothing. See [recovery detection](components/transient-runner.md#recovery-detection).

## Correlation headers

OpenDLQ also reads correlation headers when present: `traceparent`, `x-request-id`, `x-message-id`, and any names set in configuration. See [Enricher](components/enricher.md).
