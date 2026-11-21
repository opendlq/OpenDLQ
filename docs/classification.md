# Classification

[Português](classification.pt-BR.md)

Every message that reaches OpenDLQ gets one of two kinds. The kind decides what happens next.

| | Transient | Permanent |
| --- | --- | --- |
| Cause | The environment: dependency, network, lock, quota | The message or the code: schema, business rule, bug |
| Does a retry help? | Yes, with time | No |
| Examples | Timeout, `connection refused`, 503, 429, deadlock | Parse error, missing required field, validation 4xx, `nil dereference` |
| Handling | Retry with backoff, circuit breaker | Group, show context, wait for a decision |
| Human involvement | Only when retries are exhausted | Always, unless a runbook covers it |
| Success metric | Time to recovery | Time to triage |

Treating both kinds the same way causes one of two errors. Retrying everything loads an unavailable dependency with messages that will never pass. Retrying nothing pages a human for a 30-second timeout.

## How a message is classified

The classifier checks three signals in order and stops at the first one that answers.

1. **Consumer header.** The consumer publishes to the DLQ with the headers of the [header contract](#header-contract). This is the recommended path. It is the cheapest and most precise signal.
2. **Rule by error type.** Rules in configuration map an exception or status to a kind. Defaults: 5xx, timeout, `connection refused`, `ECONNRESET`, 429 and deadlock are transient; validation 4xx, parse or serialization errors, constraint violations and `nil dereference` are permanent. Rules are per consumer and override the defaults.
3. **Inference from behavior.** With no header and no rule, the message starts as transient. OpenDLQ then watches two patterns:
    - **The same message fails N times with the same error.** The message is the problem. It is treated as permanent.
    - **Many different messages fail in the same window with the same error or dependency.** The dependency is the problem, not the messages. The circuit breaker for that dependency opens and the messages are held until a probe passes. See [recovery](recovery.md).

The second pattern detects an unavailable dependency without an external health check.

## Classification is never final

An operator can reclassify any message. The reclassification is recorded and can feed the consumer's rules. Reclassifying a permanent message as transient is the only way it goes back to retrying.

## Classification is a plugin

The core defines the interface:

- **Input:** message, headers, error.
- **Output:** kind (`transient` or `permanent`), dependency, grouping key.

The three signals above are the default classifier. A team replaces it with its own plugin when its domain needs it, for example when a field in the payload identifies the cause. Nothing else in the system changes.

## Header contract

Consumers that publish to the DLQ with these headers get the most precise classification.

| Header | Value | Required |
| --- | --- | --- |
| `x-failure-kind` | `transient` or `permanent` | Recommended |
| `x-failure-reason` | Short error description, stable across occurrences | Recommended |
| `x-failure-dependency` | Name of the dependency involved | When there is one |
| `x-attempt` | Attempt number in the consumer | Optional |

`x-failure-reason` is also the default grouping key. Keep it stable: `validation: sku format`, not the full error message with IDs in it.

OpenDLQ adds two headers to every replay:

| Header | Meaning |
| --- | --- |
| `x-dlq-id` | Identity of the message in OpenDLQ. Stays the same across replays. |
| `x-dlq-attempt` | Replay attempt number |

A consumer that already processed an `x-dlq-id` successfully should skip it and acknowledge. A message that fails again after a replay goes back to the DLQ with the same `x-dlq-id`, and OpenDLQ attaches the new failure to the existing record.

OpenDLQ also reads correlation headers when present: `traceparent`, `x-request-id`, `x-message-id`, and any names set in configuration. See [operations](operations.md#correlated-logs).
