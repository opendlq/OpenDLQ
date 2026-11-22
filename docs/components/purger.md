# Purger

Closes messages that reached their TTL and removes data past its retention: payloads and the audit log.

| | |
| --- | --- |
| Watches | Open messages past `expires_at`; payloads and `transitions` past retention |
| Writes | `expired`; archived payload reference |
| Plugins | Store (archive) |
| Scales | One active instance is enough |

## Responsibility

- Move a message past `expires_at` to `expired`, from any open state. The move uses compare-and-set, so it never overwrites a concurrent change.
- Archive the payload to cold storage, through an archive `Provider`, before deleting it.
- Delete payloads past retention.
- Delete `transitions` of closed messages older than `audit.retention`, after archiving them through `audit.archive`. Record each removal: period, row count, archive reference.

TTL and payload retention are set per consumer or per cause in the `Policy`. Audit retention is global, in `opendlq.yaml`. See [retention](../configuration.md#retention).

## Does not

- Delete history of an open message. Its transitions stay until it closes and passes `audit.retention`.
- Delete analytics aggregates. They follow `analytics.retention`, in the Analytics Engine.
- Discard by cause. A known and accepted cause is handled by a runbook with the `discard` action, so the decision is declared and audited.
