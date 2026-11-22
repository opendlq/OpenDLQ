# Policy Engine

The only component that decides which path a message takes. It classifies the message, then routes it to a runner.

| | |
| --- | --- |
| Watches | `ready` |
| Writes | `retrying`, `held`, `runbook_matched` or `awaiting_operator` |
| Plugins | Classifier |
| Scales | N instances, by claim |

## Responsibility

- Read what it needs from the State Store: headers, enrichment result, message history, group memory.
- Classify the message as transient or permanent. See [classification](#classification).
- Match the message against the catalog of `Runbook` resources.
- Route by precedence:
    1. Attempts exhausted → `awaiting_operator`.
    2. A runbook matches → `runbook_matched`.
    3. Transient → `retrying`, or `held` if the dependency's circuit is open.
    4. Permanent → `awaiting_operator`.
- Skip a path that already failed for this message.

Every failure on any path returns the message to `ready`. The Policy Engine is the only place where a message changes path.

## Does not

- Execute a path. The runners do.
- Retry, publish or notify.

## Classification

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

### How a message is classified

Classification happens in the Policy Engine, after [enrichment](enricher.md). By then the store holds the headers, the message history and the enrichment result. The classifier checks five signals in order and stops at the first one that answers:

1. **Consumer header.** The consumer publishes to the DLQ with the headers of the [header contract](../header-contract.md). This is the recommended path. It is the cheapest and most precise signal.
2. **Rule.** Rules in configuration map an error to a kind. A rule can read headers, the error, and the fields the Enricher extracted from the logs, such as `enrichment.error_class`. Defaults: 5xx, timeout, `connection refused`, `ECONNRESET`, 429 and deadlock are transient; validation 4xx, parse or serialization errors, constraint violations and `nil dereference` are permanent.
3. **Group memory.** If the message's `group_key` was already classified (by a rule on logs, by inference, or by an operator) within the memory window, the message gets the same kind. One decision covers a thousand identical messages.
4. **Error class from the logs.** If the enrichment result carries an exception class that no rule covers, a built-in table maps common classes to a kind: `SocketTimeoutException` or `ConnectException` are transient; `JsonParseException` or `NullPointerException` are permanent. Rules override the table.
5. **Inference from behavior.** With nothing above, the message starts as transient. OpenDLQ then watches two patterns:
    - **The same message fails N times with the same error.** The message is the problem. It is treated as permanent.
    - **Many different messages fail in the same window with the same error or dependency.** The dependency is the problem, not the messages. The circuit breaker for that dependency opens and the messages are held until a probe passes. See [recovery](transient-runner.md).

The last pattern detects an unavailable dependency without an external health check.

Every decision records which signal answered (`classified_by`: `header`, `rule`, `group`, `logs`, `inference`, `operator`, or `plugin` when a team replaces the classifier), so the analytics can show which signals do the work.

### Classification is never final

An operator can reclassify a message or a whole group. The reclassification is recorded, becomes the group's memory, and can feed the consumer's rules. Reclassifying a permanent message as transient is the only way it goes back to retrying.

### Classification is a plugin

The core defines the interface:

- **Input:** message, headers, error, enrichment result, message history.
- **Output:** kind (`transient` or `permanent`), dependency, grouping key.

The signals above are the default classifier. A team replaces it with its own plugin when its domain needs it, for example when a field in the payload identifies the cause. Nothing else in the system changes.
