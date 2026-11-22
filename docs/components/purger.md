# Purger

Closes messages that reached their TTL and removes payloads past retention.

| | |
| --- | --- |
| Watches | Open messages past `expires_at`; payloads past retention |
| Writes | `expired`; archived payload reference |
| Plugins | Store (archive) |
| Scales | One active instance is enough |

## Responsibility

- Move a message past `expires_at` to `expired`, from any open state. The move uses compare-and-set, so it never overwrites a concurrent change.
- Archive the payload to cold storage, through an archive `Provider`, before deleting it.
- Delete payloads past retention.

TTL and retention are set per consumer or per cause in the `Policy`. See [configuration](../configuration.md#policy).

## Does not

- Delete `transitions`. The audit log and the aggregated metrics stay.
- Discard by cause. A known and accepted cause is handled by a runbook with the `discard` action, so the decision is declared and audited.
