# Operations

[Português](operations.pt-BR.md)

What an operator can do with failed messages, and through which interfaces.

## Interfaces

| Interface | For |
| --- | --- |
| **CLI** (`opendlq`) | Configuration (`diff`, `apply`, `export`) and day-to-day actions |
| **API** | Integrations and the UI |
| **MCP server** | AI agents. Same operations as the CLI and API |
| **UI** | Exploring groups, reading context, acting on batches. Not in V0 |

All interfaces expose the same operations and write to the same audit log.

## Actions

| Action | Scope | Effect |
| --- | --- | --- |
| **List by cause** | Consumer, cause, dependency, period | Groups of failed messages with count, age and trend |
| **Inspect** | One message or group | Payload, headers, error, attempts, correlated logs, trace link |
| **Reclassify** | One message or group | Change the kind. Permanent to transient sends the messages back to retrying |
| **Replay** | One message or batch | Send to the original topic or another target, with an idempotency key, in partition order |
| **Edit and replay** | One message or batch | Change the payload, then replay |
| **Discard** | One message or batch | Close with a recorded reason |
| **Approve** | A runbook run | Allow a supervised runbook run to proceed |

Batch actions take a filter (consumer, grouping key, time window) and a rate limit.

## Correlated logs

When a consumer sends a message to the DLQ, it usually also writes an error log with correlation IDs: trace ID, span ID, message ID, request ID. That log has context the DLQ does not: stack trace, consumer state, calls made before the failure.

- The Collector extracts correlation IDs from headers and stores them.
- A **log provider** plugin takes the IDs and a time window and returns the matching logs. Planned providers: Elasticsearch/OpenSearch, Loki, CloudWatch Logs, Datadog Logs.
- Logs are fetched asynchronously, with retry, because a log may not be indexed yet when the message arrives. A logging backend outage never blocks ingestion.
- OpenDLQ stores a link to the query and a short snippet. It does not copy logs.
- When the log backend has no API access, OpenDLQ still builds a deep link from a URL template: Grafana Explore, Kibana Discover, Datadog Log Explorer.

## Audit log

Every state change is recorded in the same transaction as the change itself: who (person, agent, runbook or controller), what, when, and the result. The audit log is never purged.

## Purge

Failed messages do not stay forever. Purge rules live in the `Policy`:

- **TTL** per consumer or per cause. An expired message closes as `expired`, from any open state.
- **Archive** the payload to cold storage before deleting it.
- **Automatic discard** for causes marked as known and accepted.

Purge deletes payloads only. The audit log and aggregated metrics stay.
