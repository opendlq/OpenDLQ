# State Store

The single source of truth. It holds every message, every state change, the outbox and the enrichment results. Every component reads and writes through it.

| | |
| --- | --- |
| Backend | Postgres |
| Access | Only through the `internal/state` package |
| Plugins | Store |
| Scales | Postgres primary. Read replicas for queries |

## Responsibility

The State Store plays the role of the Kubernetes API server and etcd together. Components never call each other. They read state, act, and write the next state.

It exposes three operations:

| Operation | Does |
| --- | --- |
| `Claim(state, limit)` | Takes messages in a state with `SELECT ... FOR UPDATE SKIP LOCKED`. Two instances never get the same message |
| `Transition(t)` | One transaction: compare-and-set on `version`, a `transitions` row, and optionally an `outbox` row. A concurrent change fails and is discarded |
| `Watch(filter)` | Wakes a component up with `LISTEN/NOTIFY`. A hint, not a source of truth. Without it, the next poll finds the work |

Only `internal/state` imports the database driver. That keeps the transaction rules in one place.

The State Store is a library inside each process, not a separate service. A separate service would add a network hop between ingestion and the commit, and a window where a message has left the source but is not stored.

## Tables

| Table | Holds | Written by |
| --- | --- | --- |
| `messages` | Current state of each message. See [message record](../state-machine.md#message-record) | All controllers |
| `transitions` | Every state change: who, what, when, result. Audit log and analytics fact table. Never purged | All controllers, same transaction |
| `outbox` | Replays to publish | Runners, same transaction |
| `enrichments` | Log extracts and links | Enricher |
| `alert_instances` | Alerts `pending` and `sent` | Alerts Watcher |
| `findings` | Anomalies found by the Analytics Engine | Analytics Engine |
| `resources` | Applied configuration and its version | `opendlq apply` |

## Store requirements

A pluggable store must provide:

- ACID transactions across `messages`, `transitions`, `outbox` and `enrichments`.
- Compare-and-set per row.
- Row locks with skip.
- An ordered change stream, for the [Analytics Engine](analytics-engine.md#pipeline).

A database without all four cannot be a store.

## Does not

- Hold business logic. It enforces versions and transactions, not rules.
