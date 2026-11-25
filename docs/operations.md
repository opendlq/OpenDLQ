# Operations

What an operator can do with failed messages, and through which interfaces.

## Interfaces

| Interface | For |
| --- | --- |
| **CLI** (`opendlq`) | Configuration (`diff`, `apply`, `export`) and day-to-day actions |
| **API** | Integrations and the UI |
| **MCP server** | AI agents. Same operations as the CLI and API |
| **UI** | Exploring groups, reading context, acting on batches |

All interfaces expose the same operations and write to the same audit log.

## Actions

| Action | Scope | Effect |
| --- | --- | --- |
| **List by cause** | Consumer, cause, dependency, period | Groups of failed messages with count, age and trend |
| **Inspect** | One message or group | Payload, headers, error, attempts, correlated logs, trace link |
| **Reclassify** | One message or group | Change the kind. Permanent to transient sends the messages back to retrying |
| **Replay** | One message or batch | Send to the original topic or another target, with an idempotency key and the original partition key |
| **Edit and replay** | One message or batch | Change the payload, then replay |
| **Discard** | One message or batch | Close with a recorded reason |
| **Approve** | A runbook run | Allow a supervised runbook run to proceed |

Batch actions take a filter (consumer, grouping key, time window) and a rate limit.

## Correlated logs

Inspecting a message or a group shows the log extract and links fetched by the Enricher before classification. An operator can ask for a message to be enriched again. See [Enricher](components/enricher.md).

## Audit log

Every state change is recorded in the same transaction as the change itself: who (person, agent, runbook or controller), what, when, and the result. It is kept for `audit.retention`, `400d` by default. See [retention](configuration.md#retention).

## Purge

Failed messages do not stay forever. TTL and retention are set in the `Policy`. An expired message closes as `expired` from any open state. The payload is archived, then deleted. The audit log follows its own retention. See [Purger](components/purger.md).
