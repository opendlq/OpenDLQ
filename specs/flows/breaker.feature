Feature: Circuit breaker, probe and drain
  When many different messages fail on one dependency, the dependency is the problem.
  The circuit opens, messages are held, a probe checks the dependency, and the backlog drains.

  Background:
    Given a consumer "orders" with breaker window 60s and threshold 20
    And probe canary every 30s, cap 5m
    And drain rate 50 msg/s

  @default
  Scenario: The circuit opens at the threshold
    When 20 distinct messages fail with x-failure-dependency "payments" within 60s
    Then the circuit for "payments" opens

  @default
  Scenario: Below the threshold, the circuit stays closed
    When 19 distinct messages fail on "payments" within 60s
    Then the circuit for "payments" stays closed

  @default
  Scenario: Only transient failures count
    When 30 messages fail on "payments" with the permanent error "validation: sku" within 60s
    Then the circuit for "payments" stays closed

  @default
  Scenario: Without a dependency header, the key is the consumer
    When 20 distinct transient messages without x-failure-dependency fail within 60s
    Then the circuit for "orders" opens

  @transition:retrying->held @default
  Scenario: Scheduled messages are held when the circuit opens
    Given messages in retrying for "payments"
    When the circuit for "payments" opens
    Then they move to held
    And no retry is published for "payments"

  @transition:ready->held @default
  Scenario: New messages for an open circuit go straight to held
    Given the circuit for "payments" is open
    When a transient message for "payments" is routed
    Then the state is held

  @transition:held->replaying @default
  Scenario: The oldest held message is the canary
    Given the circuit for "payments" is open with 500 held messages
    When 30s pass
    Then the oldest held message is sent as a canary
    And its state is replaying

  @default @failure
  Scenario: The canary fails, so the interval doubles
    Given the canary is not acked
    Then the canary returns to held
    And the next canary is sent after 60s, then 120s, then 240s, then 300s
    And the canary's failures do not count as attempts

  @config:probe.type=health_check
  Scenario: Health check instead of a canary
    Given the probe is a health check on "http://payments/health"
    When the endpoint answers 200
    Then the circuit closes
    And no message is used as a probe

  @transition:held->retrying @default
  Scenario: The probe passes and the backlog drains oldest first
    Given the circuit for "payments" is open with 500 held messages
    When the canary is acked
    Then the circuit closes
    And held messages move to retrying at 50 msg/s, oldest first

  @default @failure
  Scenario: The dependency fails again during the drain
    Given the backlog is draining
    When 20 distinct drained messages fail within 60s
    Then the circuit opens again
    And the messages not yet drained stay held
