# Runbooks

A runbook tells OpenDLQ what to do with a known permanent failure. The operator writes it. OpenDLQ executes it, within limits.

Without a runbook, a permanent failure always waits for a human. A runbook lets the operator make that decision in advance.

```yaml
kind: Runbook
metadata:
  name: legacy-sku-format
  consumer: order-events
spec:
  match:
    reason: "validation: sku format"
    group_key: "sku-format-v1"
  action:
    transform: ./transforms/sku-v1-to-v2.jsonata
    replay: original
  guardrails:
    max_per_hour: 500
    approval_required_first: 3
    expires: 2027-03-01
```

## Match

A runbook matches on any combination of consumer, reason, grouping key, dependency, or an expression over headers and payload (CEL). Runbooks are checked before the transient path: a runbook can also cover a known transient case.

## Actions

| Action | Effect |
| --- | --- |
| `transform` + `replay` | Change the payload, then replay it |
| `replay` | Replay without changes |
| `route` | Send the message to another topic or endpoint |
| `discard` | Discard with a recorded reason |
| `quiet` | Keep the message waiting for an operator, without notifications |
| `notify` | Send a notification with context, without other changes |

Custom actions are plugins.

## Guardrails

Every runbook must declare:

- **Rate limit:** how many messages per hour it may act on.
- **Approval:** how many first runs need an operator's approval before it runs on its own.
- **Expiry date:** a runbook without one is rejected.

The expiry date is deliberate. A runbook is a documented workaround, not a permanent fix. When it expires, the failures go back to waiting for an operator, and the root cause becomes visible again. [Recurrence analytics](analytics.md#recurrence) show how long a workaround has been covering a problem.

## Lifecycle

1. **Suggestion.** When an operator applies the same action to the same group three times, OpenDLQ suggests a runbook with that match and action.
2. **Dry run.** The operator runs the runbook against the message history in the state store and sees what it would have done.
3. **Approval.** The runbook goes into the configuration repository through a pull request, like any other resource.
4. **Supervised runs.** The first N runs wait for approval.
5. **Automatic runs.** After that, the runbook runs on its own, within its rate limit.
6. **Expiry.** The runbook stops. The operator renews it or fixes the root cause.

Every run is recorded in the audit log with the runbook's name and version.

## What stays true

Permanent failures still never retry on their own. The only change is that a person declared the decision ahead of time, with limits, in a file that went through review.
