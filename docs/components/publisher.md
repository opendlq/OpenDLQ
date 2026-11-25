# Publisher

Publishes replays to the broker. It is the only component that writes to a broker.

| | |
| --- | --- |
| Watches | `outbox` rows with `sent_at` empty |
| Writes | `outbox.sent_at` |
| Plugins | Sink, Serde |
| Scales | N instances, by claim |

## Responsibility

- Read pending `outbox` rows, oldest first.
- Serialize the payload with the Serde of the consumer.
- Add the [replay headers](../header-contract.md#replay-headers) `x-dlq-id` and `x-dlq-attempt`, and continue the trace with `traceparent`.
- Publish to the Sink with the original partition key.
- Mark the row as sent.

A runner never publishes. It writes an `outbox` row in the same transaction as the state change. The replay exists only if the decision was committed.

## Delivery guarantee

At least once per decision. If the Publisher crashes after the publish and before marking the row, the row is published again, with the same `x-dlq-id` and `x-dlq-attempt`. The copy is identifiable:

- The consumer skips an `x-dlq-id` it already processed.
- The [Transient Runner](transient-runner.md#recovery-detection) counts one ack per attempt.

## Does not

- Decide what to replay or when. Runners decide. The Publisher only delivers.
- Order replays. Messages with the same partition key can be published in any order. See [scope](../scope.md#non-goals).
