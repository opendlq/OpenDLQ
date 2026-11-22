# Transient Runner

Recovers transient failures without human involvement.

| | |
| --- | --- |
| Watches | `retrying` when due; `held`; `replaying` |
| Writes | `outbox`; `replaying`, `held`, `retrying`, `recovered`, or `enriched` on a failed replay |
| Plugins | Probe, Recovery Detector |
| Scales | N instances, by claim. Breaker state is in the State Store |

## Does not

- Decide that a message is exhausted. A failed replay returns the message to `enriched`, and the Policy Engine checks the attempt count.
- Retry a permanent failure.
- Publish. It writes to the `outbox`. See [Publisher](publisher.md).

## Recovery

OpenDLQ recovers transient failures without human involvement. Four mechanisms work together. All of them are set per consumer in a `Policy` resource. The full field reference is in [configuration](../configuration.md#policy).

```yaml
kind: Policy
metadata:
  name: order-events-default
  consumer: order-events
spec:
  retry:    { max: 5, base: 30s, factor: 2, cap: 30m, jitter: 0.2 }
  breaker:  { window: 60s, threshold: 20 }
  probe:    { type: canary, every: 30s, cap: 5m }
  drain:    { rate: 50 }
  recovery: { mode: ack, topic: opendlq.ack, timeout: 10s }
  ttl: 72h
```

### Retry with exponential backoff and jitter

Default: 5 attempts, base 30 s, factor 2, cap 30 min, jitter ±20%.

The jitter keeps messages that failed together from coming back together. When attempts run out, the message is treated as permanent and waits for an operator.

### Circuit breaker per dependency

The breaker key is `x-failure-dependency` when the consumer sends it, or the consumer name when it does not.

The breaker opens when 20 or more distinct messages fail with the same error or dependency within 60 s. While it is open:

- No message for that key is retried. The messages are **held**.
- Time spent held does not count as an attempt.

Only failures classified as transient count toward opening the breaker. Twenty messages with the same validation error do not look like an unavailable dependency.

### Probe

While the breaker is open, a probe checks whether the dependency is back. The probe is a plugin:

- **Canary (default):** every 30 s, replay one held message, the oldest. The interval doubles on each failure, up to 5 min.
- **Health check:** call an HTTP endpoint of the dependency. Useful when replaying a real message is not safe.

When the probe passes, the breaker closes.

### Controlled drain

After the breaker closes, the held backlog drains in arrival order, at a configurable rate (default 50 msg/s). The rate keeps a dependency that just recovered from going down again under the backlog.

Messages with the same partition key replay in their original order.

### Recovery detection

A replay is not a recovery until the consumer confirms it. Two modes, set per consumer:

| Mode | How it works | Trade-off |
| --- | --- | --- |
| `ack` | The consumer publishes the `x-dlq-id` to `opendlq.ack` after processing. No ack within the timeout counts as a failure. | Precise. Needs a small change in the consumer. |
| `silence` | The message counts as recovered if it does not come back to the DLQ within N seconds. | No consumer change. Can count a slow failure as a success. |

### Idempotency

Every replay carries `x-dlq-id` and `x-dlq-attempt`. The contract with the consumer: if it already processed that `x-dlq-id` successfully, skip and acknowledge.

OpenDLQ does not guarantee idempotency on its own. It guarantees that the consumer has the information to be idempotent. A replay without this contract is not safe.

### What a policy never does

- Retry a permanent failure without an operator or a runbook.
- Change a payload without an operator or a runbook.
- Replay outside the original partition key.

### Why short retries stay in the consumer

A retry of a few seconds belongs in the consumer. OpenDLQ handles what survived it: an outage of minutes or hours, where the consumer cannot hold the message without blocking its partition. Today that message becomes a human problem even though the fix is to wait. That is the case recovery exists for.
