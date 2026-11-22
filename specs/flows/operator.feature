Feature: Operator actions
  An operator decides permanent failures. Every action is an event,
  goes through optimistic locking and is recorded with who made it.

  Background:
    Given a message "m-1" in awaiting_operator, permanent, group_key "missing:sku"

  @transition:awaiting_operator->replaying @default
  Scenario: Replay without changes
    When the operator replays "m-1"
    Then an outbox row is written to the original topic, with the original partition key
    And the state is replaying
    And the audit records the operator

  @transition:awaiting_operator->replaying @default
  Scenario: Edit and replay
    When the operator edits the payload of "m-1" and replays it
    Then the original payload is kept in the history
    And the outbox row carries the edited payload
    And the state is replaying

  @transition:awaiting_operator->ready @default
  Scenario: Reclassify as transient
    When the operator reclassifies "m-1" as transient
    Then classified_by is operator
    And the state is ready
    And the Policy Engine routes it to the transient path

  @default
  Scenario: Reclassifying a group becomes group memory
    When the operator reclassifies group "missing:sku" as transient
    Then every message of the group in awaiting_operator goes to ready
    And new messages of the group are classified transient by group memory for 24h

  @transition:awaiting_operator->discarded @default
  Scenario: Discard with a reason
    When the operator discards "m-1" with reason "obsolete order"
    Then the state is discarded
    And the reason is recorded

  @default
  Scenario: A discard needs a reason
    When the operator discards "m-1" with no reason
    Then the action is refused

  @default
  Scenario: Batch replay
    Given 300 messages in awaiting_operator with group_key "missing:sku"
    When the operator replays the group at 20 msg/s
    Then the messages move to replaying at 20 msg/s
    And messages with the same partition key keep their order

  @default
  Scenario: Every interface does the same thing
    When the same replay is made through the CLI, the API and MCP
    Then each one writes the same transitions
    And each one records its actor: person or agent
