# Flows

How a message moves through OpenDLQ in each situation. Every arrow into the state store is a single transaction that changes the message state, writes a row to `transitions`, and, when something must be published, writes a row to the `outbox`. Components never call each other; they read and write state. See [architecture](architecture.md) for the rules and the full state machine.

| Flow | Starts with | Ends with |
| --- | --- | --- |
| [1. Ingestion](#1-ingestion) | A message lands in the DLQ | `received` |
| [2. Classification](#2-classification) | `received` | `retrying`, `held`, `runbook_matched` or `awaiting_operator` |
| [3. Transient recovery](#3-transient-recovery) | `retrying` | `recovered`, or back to `received` |
| [4. Dependency outage](#4-dependency-outage) | Many failures on one dependency | Backlog drained |
| [5. Permanent failure and alert](#5-permanent-failure-and-alert) | `awaiting_operator` | Enriched alert sent |
| [6. Runbook](#6-runbook) | `runbook_matched` | `replaying`, `routed`, `discarded` or `awaiting_operator` |
| [7. Operator action](#7-operator-action) | An operator command | `replaying`, `retrying` or `discarded` |
| [8. Expiry and purge](#8-expiry-and-purge) | TTL or retention reached | `expired`, payload archived |
| [9. Configuration change](#9-configuration-change) | A YAML change | Resources applied |

## 1. Ingestion

```mermaid
sequenceDiagram
    participant DLQ as DLQ (broker)
    participant C as Collector
    participant S as State store
    DLQ->>C: message + headers
    C->>C: decode headers, extract correlation IDs
    alt has x-dlq-id (a replay that failed again)
        C->>S: append attempt, state = received
    else new message
        C->>S: insert, state = received
    end
    C->>DLQ: commit offset
    S-->>S: NOTIFY policy
```

- The offset is committed only after the transaction commits. A crash in between re-delivers the message; the unique constraint on `(topic, partition, offset)` makes the second insert a no-op.
- The Collector calls no external service. Nothing outside the broker and the store can stop ingestion.

## 2. Classification

```mermaid
sequenceDiagram
    participant S as State store
    participant P as Policy Engine
    S->>P: next received message (SKIP LOCKED)
    P->>P: attempts >= policy max?
    P->>P: matching runbook?
    P->>P: classify: header, rule, inference
    P->>P: dependency circuit open?
    P->>S: new state + transition
```

Precedence:

1. Attempts exhausted → `awaiting_operator`.
2. A runbook matches → `runbook_matched`.
3. Transient and the dependency circuit is open → `held`.
4. Transient → `retrying`, with `next_retry_at` from the backoff.
5. Permanent → `awaiting_operator`.

## 3. Transient recovery

```mermaid
sequenceDiagram
    participant S as State store
    participant T as Transient Runner
    participant Pub as Publisher
    participant Q as Original topic
    participant App as Consumer
    S->>T: retrying, next_retry_at <= now
    T->>S: state = replaying, outbox row
    S->>Pub: pending outbox row
    Pub->>Q: publish with x-dlq-id, x-dlq-attempt
    Pub->>S: outbox.sent_at
    Q->>App: message
    alt success
        App->>Q: ack to opendlq.ack (mode ack)
        T->>S: state = recovered
    else fails again
        App->>Q: publish to DLQ with same x-dlq-id
        Note over S: Flow 1 attaches the attempt and sets received
    end
```

- In `silence` mode, the Transient Runner marks the message `recovered` when it does not come back within the configured window.
- A message that comes back goes through classification again. Exhaustion is checked there.

## 4. Dependency outage

```mermaid
sequenceDiagram
    participant S as State store
    participant T as Transient Runner
    participant Dep as Dependency
    T->>S: 20 distinct transient failures on dep in 60 s
    T->>S: open circuit, retrying → held for dep
    loop every canary interval (doubles up to cap)
        T->>Dep: probe (canary replay or health check)
        Dep-->>T: fails
    end
    T->>Dep: probe
    Dep-->>T: passes
    T->>S: close circuit, held → retrying at drain.rate
```

- Held messages keep their attempt count. Time held is not an attempt.
- The drain releases messages in arrival order, at `drain.rate`, and keeps partition-key order.
- Opening and closing the circuit are events. The Alerts Watcher can alert on them.

## 5. Permanent failure and alert

```mermaid
sequenceDiagram
    participant S as State store
    participant PH as Poison Handler
    participant E as Enricher
    participant LP as Log provider
    participant AW as Alerts Watcher
    participant N as Notifier
    S->>PH: awaiting_operator, not announced
    PH->>S: update group, notified_at, event poisoned
    PH->>S: sampled? enrichment = pending
    S->>AW: event poisoned
    AW->>S: alert instance, state = pending_enrichment
    S->>E: enrichment pending
    E->>E: wait delay (indexing)
    E->>LP: query by correlation IDs
    LP-->>E: logs (or retry, or fail)
    E->>S: enrichment = enriched / not_found / unavailable
    S->>AW: enrichment final
    AW->>N: alert with group, sample, logs, links, runbook
    AW->>S: alert instance = sent
```

- With `mode: required`, the alert waits for a final enrichment status. `unavailable` is final, so a logging outage delays the alert but never silences it.
- With `mode: wait`, the alert is sent at `max_wait` with what exists, then followed up.
- With `mode: best_effort`, the alert is sent at once, then followed up.
- See [enrichment](enrichment.md).

## 6. Runbook

```mermaid
sequenceDiagram
    participant S as State store
    participant R as Runbook Runner
    participant Op as Operator
    S->>R: runbook_matched
    R->>R: guardrails: expired? rate limit? approvals left?
    alt approval required
        R->>S: state = awaiting_approval
        Op->>S: approve (or reject → awaiting_operator)
        S->>R: runbook_matched (approved)
    end
    alt transform + replay
        R->>S: transformed payload, state = replaying, outbox row
    else route
        R->>S: state = routed, outbox row to target
    else discard
        R->>S: state = discarded, reason
    else action fails or guardrail blocks
        R->>S: state = awaiting_operator
    end
```

- An expired runbook never matches. The messages it covered go to `awaiting_operator` again.
- Every step writes the runbook name and version to `transitions`.

## 7. Operator action

```mermaid
sequenceDiagram
    participant Op as Operator (CLI, API, MCP)
    participant API as API
    participant S as State store
    participant Ctl as Responsible controller
    Op->>API: replay group X, rate 50/s
    API->>S: desired state + audit (who, what, filter)
    S->>Ctl: work available
    Ctl->>S: state changes, outbox rows
```

- The API never publishes. It writes the decision; the controllers execute it.
- Edit-and-replay stores the new payload with the decision. The original payload stays in history.
- Reclassifying permanent as transient moves the messages to `retrying`. It is the only path back to automatic retries.

## 8. Expiry and purge

```mermaid
sequenceDiagram
    participant S as State store
    participant Pu as Purger
    participant Arc as Cold storage
    S->>Pu: open message with expires_at <= now
    Pu->>S: state = expired
    S->>Pu: payload past retention
    Pu->>Arc: archive payload (if configured)
    Pu->>S: delete payload, keep record and transitions
```

## 9. Configuration change

```mermaid
sequenceDiagram
    participant Dev as Person or agent
    participant Git as Config repository
    participant CLI as opendlq CLI
    participant S as State store
    Dev->>Git: pull request with YAML change
    Git->>Git: review, merge
    CLI->>S: opendlq diff (declared vs applied)
    CLI->>S: opendlq apply
    S-->>S: controllers reload resources
```

- A change made through the API or UI to a declared resource is drift. `opendlq diff` shows it; `export` keeps it, `apply` discards it.
- Resources are versioned. Every transition records the version of the policy, classifier or runbook that decided it.
