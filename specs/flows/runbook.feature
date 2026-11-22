Feature: Runbook path
  A runbook is a decision an operator made in advance, with limits.
  The Policy Engine matches it. The Runbook Runner executes it.

  Background:
    Given a runbook "legacy-sku" for consumer "orders" matching group_key "sku-format-v1"
    And action transform "./transforms/sku-v1-to-v2.jsonata" and replay original
    And guardrails max_per_hour 500, approval_required_first 3, expires 2027-03-01

  @transition:ready->runbook_matched @default
  Scenario: A message matches the runbook
    Given a message in ready with group_key "sku-format-v1"
    When the Policy Engine routes it
    Then the state is runbook_matched
    And runbook is "legacy-sku" with its version

  @transition:runbook_matched->awaiting_approval @default
  Scenario: The first runs wait for approval
    Given "legacy-sku" has 1 approved run
    When the Runbook Runner claims a matched message
    Then the state is awaiting_approval

  @transition:awaiting_approval->runbook_matched @default
  Scenario: The operator approves a supervised run
    Given a message in awaiting_approval for "legacy-sku"
    When the operator approves it
    Then the state is runbook_matched
    And the run counts toward approval_required_first

  @transition:awaiting_approval->ready @default
  Scenario: The operator rejects a supervised run
    Given a message in awaiting_approval for "legacy-sku"
    When the operator rejects it
    Then "legacy-sku" is recorded as a failed path for the message
    And the state is ready

  @transition:runbook_matched->replaying @default
  Scenario: Transform and replay
    Given "legacy-sku" has 3 approved runs
    When the Runbook Runner claims a matched message
    Then the payload is transformed
    And an outbox row is written with the new payload
    And each step is recorded as a runbook_step transition
    And the state is replaying

  @transition:runbook_matched->routed
  Scenario: Route to another destination
    Given a runbook with action route to "orders.manual-review"
    When the Runbook Runner claims a matched message
    Then an outbox row is written for "orders.manual-review"
    And the state is routed

  @transition:runbook_matched->discarded
  Scenario: Discard a known and accepted cause
    Given a runbook with action discard and reason "test traffic"
    When the Runbook Runner claims a matched message
    Then the state is discarded with reason "test traffic"

  @transition:runbook_matched->awaiting_operator
  Scenario: Quiet keeps the message for an operator without notifications
    Given a runbook with action quiet
    When the Runbook Runner claims a matched message
    Then the state is awaiting_operator
    And no alert is sent for it

  @transition:runbook_matched->awaiting_operator
  Scenario: Notify sends context and leaves the message for an operator
    Given a runbook with action notify to "team-slack"
    When the Runbook Runner claims a matched message
    Then the state is awaiting_operator
    And the Alerts Watcher notifies "team-slack" with the runbook's context

  @transition:runbook_matched->ready @default @failure
  Scenario: The transform fails
    Given the transform raises an error for the message
    When the Runbook Runner claims it
    Then the error is recorded
    And "legacy-sku" is recorded as a failed path
    And the state is ready
    And the Policy Engine does not send it to "legacy-sku" again

  @default
  Scenario: The rate limit is reached
    Given "legacy-sku" acted on 500 messages in the last hour
    When another message is matched
    Then it stays in runbook_matched
    And the Runbook Runner claims it when the hourly budget frees up

  @default
  Scenario: A runbook without an expiry date is rejected
    When an operator applies a runbook with no expires field
    Then opendlq apply refuses it

  @transition:runbook_matched->ready @default
  Scenario: The runbook expires
    Given today is after 2027-03-01
    And a message in runbook_matched for "legacy-sku"
    When the Runbook Runner claims it
    Then "legacy-sku" is recorded as a failed path, reason "expired"
    And the state is ready
    And new messages for "sku-format-v1" are no longer matched

  @default
  Scenario: A runbook is suggested after repeated operator actions
    Given an operator applied the same transform and replay to group "sku-format-v1" 3 times
    Then OpenDLQ suggests a runbook with that match and action

  @default
  Scenario: Dry run
    When the operator dry-runs "legacy-sku"
    Then it reports what it would have done on the message history
    And no state changes
