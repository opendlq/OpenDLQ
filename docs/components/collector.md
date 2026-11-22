# Collector

Reads failed messages from the DLQs and stores them. It is the only way a message enters OpenDLQ.

| | |
| --- | --- |
| Reads | Sources declared in `Consumer` resources |
| Writes | `messages` in `received`; `transitions` |
| Plugins | Source, Serde |
| Scales | By source partitions. Instances share a consumer group |

## Responsibility

- Consume from N sources. Each `Consumer` resource names one source.
- Read the [failure headers](../header-contract.md#failure-headers) and the [correlation headers](../header-contract.md#correlation-headers).
- Extract the trace context (`traceparent`).
- Compute `group_key` with the CEL expression of the `Consumer`.
- Recognize a re-entry by `x-dlq-id`. Attach the new attempt to the existing record and move it from `replaying` to `received`. The message keeps its identity.
- Commit the source offset only after the database commit.

Everything the Collector extracts comes from the message itself. That work costs nothing and cannot fail on an external system.

## Does not

- Call an external system. Logs are the [Enricher](enricher.md)'s job.
- Classify, retry or notify.

## Failure behavior

| Case | Behavior |
| --- | --- |
| Crash after the insert, before the offset commit | The source delivers the message again. The unique key `(topic, partition, offset)` rejects the copy |
| State store unavailable | The Collector stops consuming. The messages stay in the DLQ |
| Serde cannot decode the payload | The message is stored with the raw bytes and `failure_reason: undecodable`. It is never dropped |
| Header `x-dlq-id` with no matching record | Stored as a new message. The header is kept for audit |
