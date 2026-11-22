# Poison Runner

Prepares permanent failures that no runbook covers for a human decision. It groups them by cause and builds the context an operator needs.

| | |
| --- | --- |
| Watches | `awaiting_operator` with `notified_at` empty |
| Writes | Cause group; `notified_at`; `poisoned` transition |
| Plugins | — |
| Scales | N instances, by claim |

## Responsibility

- Update the cause group of the message: count, first and last occurrence, sample payload and error.
- Attach the context: enrichment snippet and links, trace link, message history, past operator actions on the same `group_key`.
- Suggest a runbook when operators took the same action on the same group three times. See [runbook lifecycle](runbook-runner.md#lifecycle).
- Record a `poisoned` transition. The [Alerts Watcher](alerts-watcher.md) decides whether to notify.

## Does not

- Notify. Ten thousand messages in one group must become one alert, not ten thousand. Only the Alerts Watcher can deduplicate across messages.
- Move a message out of `awaiting_operator`. Only an operator does: replay, discard or reclassify. See [operations](../operations.md#actions).
