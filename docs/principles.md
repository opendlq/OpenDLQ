# Design principles

Principles decide trade-offs. Each one is a position a reasonable project could reject.

## 1. Classify before acting.

**What it means.** The first thing OpenDLQ does with a failed message is decide whether it is transient or permanent. Everything after depends on that answer.

**Why.** The two kinds need opposite handling. Retrying a permanent failure only adds load to a dependency. Paging a person for a transient one wastes their time on a 30-second timeout. Broker-native retry treats every failure the same way. OpenDLQ exists because that is wrong.

**Consequences.**
- Classification uses every signal available: headers, rules, group memory, logs, behavior. See [Policy Engine](components/policy-engine.md).
- Every decision records which signal answered, so a wrong classification can be traced and fixed.
- Classification is never final. An operator can reclassify a message or a group.

## 2. Humans decide permanent failures.

**What it means.** A transient failure is recovered automatically. A permanent failure is not, unless an operator declared in advance what to do with it, in a runbook.

**Why.** A permanent failure means the message or the code is wrong. Changing or replaying it without a decision can corrupt data.

**Consequences.**
- There is no automatic transition from permanent back to retrying.
- Runbooks require guardrails: rate limit, approval for the first runs, expiry date.
- A runbook is a documented workaround, not a fix. Recurrence analytics show when the root cause still needs fixing.

## 3. Declarative first.

**What it means.** Policies, classifiers, runbooks and alerts are YAML resources. They live in a repository, go through review and are applied with `opendlq apply`. The API and UI can change the same resources, but the file is the source of truth.

**Why.** Configuration that only exists in a UI cannot be reviewed, versioned or reproduced. In a large organization, that is how a DLQ setup becomes nobody's responsibility.

**Consequences.**
- `opendlq diff` shows the difference between declared and applied state before anything changes.
- A change made outside the file shows up as drift.
- One-off actions (replay, discard, reclassify) are not resources and do not cause drift.
- People and agents use the same path: edit the file, open a pull request. There is no privileged API.

## 4. Beside your stack, not instead of it.

**What it means.** OpenDLQ reads from the DLQ the team already has, replays to the topics it already uses, queries the logs where they already are, and exports metrics to the dashboards it already has.

**Why.** Teams will not migrate their messaging, logging or observability to adopt a DLQ tool. A tool that sits beside the existing stack can be adopted one consumer at a time and removed without a migration.

**Consequences.**
- OpenDLQ does not store messages in transit, route traffic, store logs or draw dashboards.
- Short retries stay in the consumer. OpenDLQ handles what survived them.
- The only required dependency is Postgres. A broker, a CDC service or a columnar database is never required to run OpenDLQ.

## 5. Opinionated defaults. Adaptable everywhere except the core.

**What it means.** Every company has its own brokers, tools, domain, scale and tolerance for risk. OpenDLQ works with no configuration, and every default can change:

| Level | Adapts | Example |
| --- | --- | --- |
| Defaults | Nothing to do | Retry schedule, classification table, enrichment timeout |
| Configuration | Any default, per consumer | Wait for logs before classifying; a stricter breaker |
| Expressions | Rules and transforms, no build | CEL classifier rule, JSONata transform |
| Plugins | Integrations and domain logic | Broker, log backend, notifier, a team's classifier |
| Deployment | Scale and footprint | One binary and Postgres, up to split components and ClickHouse |

The core does not adapt: the state machine, the audit log, the header contract, the resource model, the analytics calculations and the runbook guardrails.

**Why.** Two installations must still be able to compare their numbers and share their runbooks. If the core adapted, every installation would speak a different language.

**Consequences.**
- Every default is documented and can be overridden in a file.
- Adaptation never changes the core. A company can make context required. It cannot make state optional.
- Changing the core is a fork. That is a legitimate choice. Ordinary adaptation should never need one.
