Feature: Re-entry
  A replayed message that fails again comes back to the DLQ with the same x-dlq-id.
  It keeps its identity and goes through enrichment and classification again.

  @transition:replaying->received @default @failure
  Scenario: A replay fails and comes back
    Given a message "m-1" in replaying with x-dlq-attempt 2
    When the consumer publishes it to the DLQ with x-dlq-id "m-1"
    Then the Collector attaches the new failure to attempt 2 of "m-1"
    And no new message is created
    And the state is received

  @default
  Scenario: A re-entry is enriched again
    Given "m-1" came back to received
    When the Enricher processes it
    Then it queries the logs of the new failure, unless the group result can be reused

  @edge
  Scenario: A Publisher copy fails again
    Given the Publisher crashed after publishing attempt 2 of "m-1" and published it again
    And the first copy came back, so "m-1" is in received
    When the second copy also comes back with x-dlq-id "m-1"
    Then one more failure is recorded on attempt 2
    And the state does not change

  @edge
  Scenario: A re-entry of a closed message
    Given "m-1" is recovered
    When a message arrives with x-dlq-id "m-1"
    Then "m-1" stays recovered
    And a new message is stored, linked to "m-1"
