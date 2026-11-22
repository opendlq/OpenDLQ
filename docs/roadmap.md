# Roadmap

## V0

V0 is done when the demo below runs end to end with no manual step in between.

**Scope**

- Kafka as the only broker, with Redpanda for local development.
- Postgres as the state store.
- CLI and API. No UI.
- Classification by header, rule and inference.
- Retry, circuit breaker, probe and controlled drain.
- Runbooks with guardrails.
- Operator actions: list by cause, inspect, reclassify, replay, edit and replay, discard.
- Analytics Engine with the `postgres` store, fed by logical replication. Funnel, cost, recurrence and findings, exposed on `/analytics`, `/metrics` and OTLP.
- A log provider plugin over a local file, as a reference. Real integrations come after V0.

**Out of scope for V0:** multiple brokers, multi-tenancy, UI, authentication.

**Demo**

A synthetic producer publishes generic events to `events`. An example consumer calls a fake service `dep` over HTTP and publishes failures to `events.dlq` with the header contract.

1. The operator stops `dep`. OpenDLQ detects the pattern, opens the circuit and holds the backlog.
2. The operator starts `dep`. The probe passes. The backlog drains in order at 50 msg/s.
3. The producer injects 5% invalid payloads. They show up grouped by cause. The operator fixes one through the API and replays it, and discards the rest with a reason.
4. The same invalid cause comes back for the third time. The recurrence alert fires.
5. The audit log shows every action.

**Milestones**

1. **Foundation.** Docker Compose with Redpanda and Postgres. Synthetic producer. Example consumer with the header contract. `dep` service with an endpoint to stop and start it.
2. **Collector and store.** Consume the DLQ, store with metadata, commit the offset afterwards. Schema migration.
3. **Classification.** Header, YAML rules, inference by repetition.
4. **Retry and replay.** Scheduled retries. Publisher with outbox, idempotency headers and partition order. Recovery detection.
5. **Circuit breaker and probe.** Pattern detection, `held` state, canary, rate-limited drain.
6. **Operator.** Grouping by cause, reclassify, replay (single and batch), edit payload, discard with reason, audit.
7. **Runbooks.** Match, actions, guardrails, dry run.
8. **Analytics and recurrence.** Replication pipeline, `postgres` store, `/analytics`, OpenTelemetry export, episode detection, detectors, alerts on findings.
9. **Write-up.** README with the recorded demo, docs updated, open questions answered.

Each milestone ends with an integration test against the Compose environment.

## After V0

- SQS, RabbitMQ and Pub/Sub sources and sinks.
- Real log providers: Elasticsearch/OpenSearch, Loki, CloudWatch Logs, Datadog Logs.
- UI.
- Authentication and multi-tenancy.
- `duckdb` and `clickhouse` analytics stores.
- Published header contract and resource schemas as a standalone specification.

## Non-goals

- Replacing or implementing a message broker.
- Global ordering of replayed messages. Ordering per partition key is a goal; global ordering is not.
- Deciding on its own how to fix a permanent failure.
- Replacing your logging or observability stack. OpenDLQ reads from it; it does not store logs.

## Open questions

- [ ] Default recovery detection: `ack` or `silence`?
- [ ] Canary: oldest held message or newest? The oldest drains in order; the newest is more likely to still be valid.
- [ ] Payload edits before replay: JSON Patch or full replacement?
- [ ] Custom detectors: declared SQL, or a plugin? Built-in detectors only in V0.
- [ ] Is a grouped endpoint (`GET /failures?group_by=reason`) enough for V0 without a UI?
