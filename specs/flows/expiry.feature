Feature: Expiry and retention
  Open messages expire at their TTL. Payloads and the audit log follow their retention.

  Background:
    Given a policy with ttl 72h

  @transition:open->expired @default
  Scenario Outline: A message expires from any open state
    Given a message in <state> with expires_at in the past
    When the Purger runs
    Then the state is expired

    Examples:
      | state             |
      | received          |
      | ready             |
      | retrying          |
      | held              |
      | runbook_matched   |
      | awaiting_approval |
      | awaiting_operator |
      | replaying         |

  @edge
  Scenario: An ack after expiry is ignored
    Given a message expired while in replaying
    When its ack arrives
    Then the ack is ignored and recorded
    And the state is still expired

  @default
  Scenario: No TTL by default
    Given a policy with no ttl
    Then open messages never expire

  @default
  Scenario: Payloads are archived, then deleted
    Given retention.payload 30d and retention.archive "s3-archive"
    And a message closed 31 days ago
    When the Purger runs
    Then the payload is archived to "s3-archive"
    And then deleted from the State Store

  @default
  Scenario: Audit history of closed messages follows audit retention
    Given audit.retention 400d
    And a message closed 401 days ago
    When the Purger runs
    Then its transitions are archived, then deleted
    And the removal is recorded with period, row count and archive reference

  @default
  Scenario: Audit history of an open message is never removed
    Given audit.retention 400d
    And a message open for 401 days
    When the Purger runs
    Then its transitions stay

  @default
  Scenario: A retention shorter than a reader is refused
    Given the detectors read a lookback of 30d
    When an operator sets audit.retention to 7d
    Then opendlq diff refuses it and names the lookback
