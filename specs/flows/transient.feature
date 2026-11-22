Feature: Transient path
  The Transient Runner retries transient failures with backoff.
  It never decides that a message is exhausted. A failed replay returns to ready.

  Background:
    Given a consumer "orders" with retry max 5, base 30s, factor 2, cap 30m

  @transition:ready->retrying @default
  Scenario: The first retry is scheduled
    Given a transient message in ready with no attempts
    When the Policy Engine routes it
    Then the state is retrying
    And next_retry_at is 30s from now

  @default
  Scenario Outline: Backoff grows with each attempt
    Given a transient message with <failed> failed attempts
    When it is scheduled again
    Then next_retry_at is <delay> from now

    Examples:
      | failed | delay |
      | 0      | 30s   |
      | 1      | 60s   |
      | 2      | 120s  |
      | 3      | 240s  |
      | 4      | 480s  |

  @config:retry.cap=2m
  Scenario: The cap limits the delay
    Given retry cap 2m
    And a transient message with 4 failed attempts
    When it is scheduled again
    Then next_retry_at is 2m from now

  @transition:retrying->replaying @default
  Scenario: A retry comes due
    Given a message in retrying with next_retry_at now
    When the Transient Runner claims it
    Then an outbox row is written with x-dlq-attempt incremented
    And the state is replaying, in the same transaction

  @default
  Scenario: A runner never publishes
    When the Transient Runner sends a message to replaying
    Then it writes an outbox row
    And only the Publisher publishes it

  @transition:ready->awaiting_operator @default @failure
  Scenario: The last attempt fails
    Given a message with 4 failed attempts
    When its 5th replay is not acked before the timeout
    Then the Transient Runner returns it to ready
    And the Policy Engine sends it to awaiting_operator, reason "retries exhausted"

  @default
  Scenario: Time held does not count as an attempt
    Given a message with 2 failed attempts goes to held for 1 hour
    When the circuit closes and it is scheduled again
    Then it still has 2 failed attempts
