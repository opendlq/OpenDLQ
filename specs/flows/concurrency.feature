Feature: Concurrency
  Controllers and events can act on the same message at the same time.
  Claims prevent duplicate work. Optimistic locking decides every race.

  @default
  Scenario: Two instances of a controller never get the same message
    Given two Policy Engine instances
    And one message in ready
    When both claim messages in ready
    Then only one of them gets it

  @default
  Scenario: An operator discards while a retry comes due
    Given a message in retrying, version 7
    When the Transient Runner reads it at version 7
    And the operator discards it, so it is at version 8
    And the Transient Runner writes replaying where version is 7
    Then the write of the Transient Runner fails
    And the state is discarded
    And no outbox row exists

  @default
  Scenario: The Purger expires a message while it is being decided
    Given a message in ready, version 3
    When the Policy Engine reads it at version 3
    And the Purger expires it, so it is at version 4
    Then the decision of the Policy Engine fails
    And the state is expired

  @default
  Scenario: An ack and an ack timeout race
    Given a message in replaying
    When the ack and the timeout are processed at the same time
    Then exactly one transition is applied
    And the state is recovered or ready, never both

  @default @failure
  Scenario: A controller crashes in the middle of a transition
    Given the Transient Runner crashes after writing the outbox row, before commit
    Then neither the outbox row nor the state change exist
    And another instance claims the message again

  @default @failure
  Scenario: The Publisher crashes after publishing, before marking the row
    Given the Publisher published an outbox row for attempt 2
    And it crashed before marking it sent
    When another Publisher instance claims the row
    Then it publishes again with the same x-dlq-id and x-dlq-attempt
    And the consumer can skip the copy
