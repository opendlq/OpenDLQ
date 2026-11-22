Feature: Ingestion
  The Collector reads failed messages from the DLQ and stores them.
  It is the only way a message enters OpenDLQ.

  Background:
    Given a consumer "orders" reading the DLQ "orders.dlq"

  @transition:new->received @default
  Scenario: A new message is stored before its offset is committed
    When a message arrives at "orders.dlq" partition 0 offset 42
    Then a message is stored with state received
    And a transition new -> received is recorded
    And only then is offset 42 committed

  @default
  Scenario: Headers and correlation are extracted from the message itself
    When a message arrives with x-failure-reason "timeout", x-failure-dependency "payments" and traceparent "00-abc-def-01"
    Then failure_reason is "timeout"
    And failure_dependency is "payments"
    And correlation holds the trace id "abc"
    And group_key is computed by the consumer's group_key expression

  @default @failure
  Scenario: The Collector crashes after storing, before committing the offset
    Given a message from partition 0 offset 42 is stored
    And the Collector crashes before committing offset 42
    When the source delivers offset 42 again
    Then the unique key (topic, partition, offset) rejects the copy
    And there is still exactly one message
    And offset 42 is committed

  @default @failure
  Scenario: The payload cannot be decoded
    Given the consumer's serde is "protobuf"
    When a message arrives whose payload is not valid protobuf
    Then the message is stored with the raw bytes
    And failure_reason is "undecodable"
    And it is never dropped

  @default @failure
  Scenario: The State Store is unavailable
    Given the State Store is down
    When messages arrive at "orders.dlq"
    Then the Collector stops consuming
    And no offset is committed
    And the messages stay in "orders.dlq"
    When the State Store comes back
    Then the Collector resumes from the last committed offset

  @edge
  Scenario: A message carries x-dlq-id with no matching record
    When a message arrives with x-dlq-id "unknown-id"
    Then it is stored as a new message
    And the header is kept for audit
