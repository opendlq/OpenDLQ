# Guarantees

Invariants that hold in every installation, under any configuration and any crash. No setting relaxes them. They are the properties the [formal specifications](#verification) check.

## 1. No message leaves without a recorded transition.

A message read from a DLQ is stored before the source offset is committed. From then on it leaves OpenDLQ only through a terminal state (`recovered`, `discarded`, `routed`, `expired`), and every move is a row in `transitions`.

- **Mechanism:** insert before offset commit; unique key `(topic, partition, offset)`; `transitions` written in the same transaction as the state change.
- **Not guaranteed:** that a message stays forever. TTL and retention remove messages and payloads, and that removal is recorded.

## 2. A decision is applied at most once.

Two concurrent decisions about the same message never both take effect.

- **Mechanism:** claim with `SELECT ... FOR UPDATE SKIP LOCKED`; every write is optimistic locking, a compare-and-set on `version`.
- **Applies to every writer:** controllers, runbooks, operators, agents, the Purger.

## 3. A replay exists only if its decision was committed.

A replay is written to the `outbox` in the same transaction as the decision. Only the Publisher publishes.

- **Delivery:** at least once. A copy after a Publisher crash carries the same `x-dlq-id` and `x-dlq-attempt`, so the consumer and the recovery detection can recognize it.
- **Not guaranteed:** that the consumer processes it once. That depends on the consumer honoring the [header contract](header-contract.md).

## 4. Every change records who made it.

Person, agent, runbook or controller: every state change and every applied resource records the actor, the time, the result and the version of the resource that decided it.

- **Retention:** the record stays for `audit.retention` (default `400d`, or `unlimited`). Only history of closed messages is removed, and each removal is itself recorded. See [retention](configuration.md#retention).
- **Not guaranteed:** that the record stays forever, unless retention is `unlimited`.

## 5. State fails closed. Context fails open by default.

- **State.** If the State Store is unavailable, OpenDLQ stops. The Collector stops consuming and messages stay in the DLQ. Nothing proceeds on a guess.
- **Context.** If logs, analytics, notifications or telemetry are unavailable, messages keep moving with less information, and the gap is recorded. A consumer can make enrichment required. See [Enricher](components/enricher.md#when-a-source-is-unavailable).
- **Always bounded.** No external dependency holds a message forever. Every wait has a maximum.

## Verification

These guarantees are the properties for the TLA+ specifications of the state machine, the outbox and the recovery detection. The same properties are checked in Go property tests.
