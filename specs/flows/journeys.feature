Feature: Message journeys
  The whole life of a message, from the DLQ to a terminal state.
  One scenario per path. Each step names the component that acts.

  Background:
    Given a consumer "orders" reading the DLQ "orders.dlq" and replaying to "orders"
    And a log source "loki" for "orders"

  @default
  Scenario: A timeout recovers on the first retry
    Given the consumer publishes a message to "orders.dlq" with x-failure-reason "timeout calling payments"
    When the Collector stores it
    Then the state is received
    When the Enricher finds its logs in "loki"
    Then enrichment_status is enriched
    And the state is ready
    When the Policy Engine classifies it
    Then it is transient, classified_by rule
    And the state is retrying with next_retry_at in 30s
    When 30s pass
    Then the Transient Runner writes an outbox row with x-dlq-attempt 1
    And the state is replaying
    When the Publisher publishes it to "orders"
    And the consumer processes it and acks x-dlq-attempt 1
    Then the state is recovered

  @default
  Scenario: A dependency outage holds the backlog, then drains it
    Given the dependency "payments" is down
    When 500 messages arrive in "orders.dlq" with x-failure-dependency "payments" within 60s
    Then the circuit for "payments" opens at the 20th distinct transient failure
    And the next messages go from ready to held
    And messages already in retrying move to held
    When the Transient Runner sends the oldest held message as a canary every 30s
    And "payments" comes back
    Then the canary is acked
    And the circuit closes
    And the held messages drain to replaying at 50 msg/s, oldest first
    And every message is recovered

  @default
  Scenario: A permanent failure waits for an operator, who fixes and replays it
    Given the consumer publishes a message with x-failure-kind permanent and x-failure-reason "missing field: sku"
    When the Collector stores it and the Enricher enriches it
    And the Policy Engine classifies it as permanent, classified_by header
    And no runbook matches
    Then the state is awaiting_operator
    When the Poison Runner groups it under "missing field: sku" with its logs
    And an Alert is declared for new poisoned groups
Then the Alerts Watcher notifies the team once for the group
    When the operator edits the payload and replays it
    Then an outbox row is written
    And the state is replaying
    When the consumer acks it
    Then the state is recovered

  @default
  Scenario: A known permanent failure is fixed by a runbook
    Given a runbook "legacy-sku" that matches group_key "sku-format-v1" with transform and replay
    And the runbook has already completed its supervised runs
    When a message with group_key "sku-format-v1" arrives and is enriched
    Then the Policy Engine sends it to runbook_matched
    When the Runbook Runner transforms the payload and writes an outbox row
    Then the state is replaying
    When the consumer acks it
    Then the state is recovered

  @default @failure
  Scenario: A transient failure runs out of attempts
    Given the dependency "payments" fails every request for this message only
    When the message goes through 5 replays without an ack
    Then each failed replay returns it to ready
    And after the 5th the Policy Engine sends it to awaiting_operator
    And the alert says "retries exhausted"

  @default @failure
  Scenario: A replay fails again and comes back to the DLQ
    Given a message in replaying with x-dlq-id "m-1" and x-dlq-attempt 2
    When the consumer fails again and publishes it to "orders.dlq" with x-dlq-id "m-1"
    Then the Collector attaches attempt 2 to the existing message
    And the state is received
    And the message goes through enrichment and classification again

  @default
  Scenario: Nobody acts on a permanent failure before its TTL
    Given a policy with ttl 72h
    And a message in awaiting_operator since 72h
    When the Purger runs
    Then the state is expired
    And the payload is archived, then deleted after retention.payload
