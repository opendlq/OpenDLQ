# Use cases

The core is the same in every case. What changes is the mix of transient and permanent failures, and so which half of OpenDLQ does most of the work.

| Case | Estimated mix | What fails | What matters most |
| --- | --- | --- | --- |
| Third-party webhooks | Mostly transient | Timeout, 503, rate limit at the destination | Circuit breaker per destination, probe, long retry |
| Notifications (push, email, SMS) | Mostly transient | Unstable provider, quota | Retry with TTL: after X hours the message no longer makes sense and expires |
| E-commerce events | Mixed | Inventory service down (transient); unknown SKU (permanent) | Both paths; grouping by cause separates them |
| Data ingestion / ETL | Mostly permanent | Malformed record, schema change | Grouping, batch payload edits, replay with transformation |
| System migration | Permanent, temporary | The new system does not recognize the event yet | A `quiet` runbook holds messages without alerts; the operator releases the batch later |
| Batch financial processing | Mixed; idempotency critical | A duplicate is worse than a delay | Ack-based recovery detection, low drain rate, audit log |

The mixes are estimates, not measurements.
