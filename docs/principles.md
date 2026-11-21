# Design principles

[Português](principles.pt-BR.md)

These principles decide trade-offs. When two designs both work, pick the one that keeps them.

## 1. Never lose a message. Never apply a decision twice.

**What it means.** Every message read from a DLQ is stored before its offset is committed. Every state transition is atomic, recorded, and applied at most once. Every replay is sent once per decision.

**Why.** A DLQ is already the place where data went wrong. A tool that loses or duplicates messages there makes the problem worse and cannot be trusted.

**Consequences.**
- The state store must support transactions, compare-and-set and row locks.
- Publishing goes through a transactional outbox, never directly from a decision.
- Analytics may lag. State, replay and audit may not.
- OpenDLQ cannot stop a consumer from receiving a duplicate. It sends an idempotency key so the consumer can deduplicate.

## 2. Humans decide permanent failures.

**What it means.** A transient failure is recovered automatically. A permanent failure never is, unless an operator declared in advance what to do with it, in a runbook.

**Why.** A permanent failure means the message or the code is wrong. Retrying it only adds load. Changing it without a decision can corrupt data.

**Consequences.**
- There is no automatic transition from permanent back to retrying.
- Runbooks require guardrails: rate limit, approval for the first runs, expiry date.
- A runbook is a documented workaround, not a permanent fix. Recurrence analytics show when the root cause still needs fixing.

## 3. Declarative first.

**What it means.** Policies, classifiers, runbooks and alerts are YAML resources. They live in a repository, go through review and are applied with `opendlq apply`. The API and UI can change the same resources, but the file is the source of truth. A change made outside the file shows up as drift.

**Why.** Configuration that only exists in a UI cannot be reviewed, versioned or reproduced. In a large organization, that is how a DLQ setup becomes nobody's responsibility.

**Consequences.**
- `opendlq diff` shows the difference between declared and applied state before anything changes.
- One-off actions (replay, discard, reclassify) are not resources and do not cause drift.

## 4. Pluggable at the edges, fixed at the core.

**What it means.** Everything that touches the outside world or depends on a domain is a plugin: sources, sinks, serializers, classifiers, transformers, probes, log providers, notifiers, runbook actions, the state store. The core is not pluggable: the state machine, the resource model, the audit log, the header contract and the analytics calculations.

**Why.** A team must be able to adapt OpenDLQ to its broker and its domain. Two teams must still be able to compare their numbers and share their runbooks. If the core were pluggable, every installation would speak a different language.

**Consequences.**
- Plugin interfaces are public and versioned.
- A change to the core is a fork, not a plugin.

## 5. On top of your broker, never instead of it.

**What it means.** OpenDLQ reads from the DLQ the team already has and writes back to the topics it already uses. It does not store messages in transit, route traffic, or require a new broker.

**Why.** Teams will not migrate their messaging to adopt a DLQ tool. A tool that sits beside the existing system can be adopted one consumer at a time and removed without a migration.

**Consequences.**
- Short retries stay in the consumer. OpenDLQ handles what survived them.
- Broker support comes from source and sink plugins.

## 6. One path for humans and agents.

**What it means.** AI agents operate OpenDLQ the same way people do: edit YAML, run `opendlq diff`, open a pull request. The CLI, the API and the MCP server expose the same operations, with the same audit trail.

**Why.** An agent with a privileged path is a change nobody reviewed. Using the same path keeps every change visible and reversible, whoever made it.

**Consequences.**
- There is no agent-only endpoint.
- Every action records who made it, human or agent.
