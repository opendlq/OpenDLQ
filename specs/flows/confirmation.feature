Feature: Confirmation
  A replay is not a recovery until the consumer confirms it.
  The Transient Runner owns replaying for every path: retry, runbook and operator.

  Background:
    Given a message in replaying with x-dlq-id "m-1" and x-dlq-attempt 2

  @transition:replaying->recovered @default
  Scenario: Ack mode, the consumer acks the current attempt
    Given recovery mode ack with timeout 10s
    When the consumer publishes to "opendlq.ack" x-dlq-id "m-1" and x-dlq-attempt 2
    Then the state is recovered

  @transition:replaying->ready @default @failure
  Scenario: Ack mode, no ack before the timeout
    Given recovery mode ack with timeout 10s
    When 10s pass with no ack
    Then attempt 2 is recorded as failed
    And the state is ready

  @edge
  Scenario: An ack for an older attempt is ignored
    When the consumer acks x-dlq-id "m-1" with x-dlq-attempt 1
    Then the ack is ignored and recorded
    And the state is still replaying

  @edge
  Scenario: A duplicate ack counts once
    Given the consumer acked attempt 2
    When the same ack arrives again
    Then it is ignored and recorded

  @edge
  Scenario: An ack outside replaying is ignored
    Given the message is already recovered
    When an ack for x-dlq-id "m-1" arrives
    Then it is ignored and recorded

  @transition:replaying->held @default @failure
  Scenario: A canary that is not acked returns to held
    Given "m-1" is the canary for the open circuit "payments"
    When 10s pass with no ack
    Then the state is held
    And the attempt does not count

  @transition:replaying->recovered @config:recovery.mode=silence
  Scenario: Silence mode, the message does not come back
    Given recovery mode silence with window 5m
    When 5m pass and "m-1" has not come back to the DLQ
    Then the state is recovered

  @transition:replaying->received @config:recovery.mode=silence @failure
  Scenario: Silence mode, the message comes back
    Given recovery mode silence with window 5m
    When "m-1" comes back to the DLQ after 2m
    Then the Collector moves it to received

  @config:recovery.mode=silence @edge
  Scenario: Silence mode, a slow failure counts as a success
    Given recovery mode silence with window 5m
    When "m-1" comes back to the DLQ after 6m
    Then "m-1" stays recovered, because terminal states never change
    And a new message is stored, linked to "m-1"
    And the analytics count "m-1" as a false recovery
