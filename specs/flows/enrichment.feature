Feature: Enrichment
  The Enricher fetches logs before classification.
  enrichment_status says what it found. The state only says the message is ready.

  Background:
    Given a consumer "orders" with a log source "loki"
    And a message in received with correlation id "abc" and group_key "timeout:payments"

  @transition:received->ready @default
  Scenario: Logs found
    Given "loki" has logs for "abc"
    When the Enricher processes the message
    Then an enrichments row stores the extract and a link
    And enrichment_status is enriched
    And the state is ready, in the same transaction

  @transition:received->ready @default
  Scenario: Same group enriched recently
    Given a message with group_key "timeout:payments" was enriched 2 minutes ago
    When the Enricher processes the message
    Then it links to that result
    And enrichment_status is reused
    And "loki" is not queried

  @transition:received->ready @default
  Scenario: Same group, but the result is older than the reuse window
    Given a message with group_key "timeout:payments" was enriched 15 minutes ago
    When the Enricher processes the message
    Then "loki" is queried

  @transition:received->ready @default
  Scenario: No logs match
    Given "loki" has no logs for "abc"
    When the Enricher processes the message
    Then enrichment_status is not_found
    And the state is ready

  @transition:received->ready @default
  Scenario: No source configured
    Given the consumer has no log source
    When the Enricher processes the message
    Then enrichment_status is skipped
    And the state is ready without any query

  @transition:received->ready @default
  Scenario: No correlation id to query with
    Given the message has no correlation id
    When the Enricher processes the message
    Then enrichment_status is skipped

  @transition:received->ready @default
  Scenario: Source without API access still gives a link
    Given "loki" has a link_template and no API access
    When the Enricher processes the message
    Then enrichment_status is skipped
    And the message carries a link built from the template

  @transition:received->ready @default @failure
  Scenario: Source down, default mode
    Given "loki" times out on every attempt
    When the Enricher processes the message
    Then it tries 3 times, with timeout 3s and backoff 1s
    And enrichment_status is unavailable
    And the state is ready within about 11s

  @config:on_unavailable=wait @failure
  Scenario: Source down, wait mode, source recovers in time
    Given the consumer sets on_unavailable to wait and max_wait to 15m
    And "loki" is down
    When the Enricher processes the message
    Then the state is still received
    And enrichment_status is pending
    And next_enrich_at is set with backoff
    When "loki" recovers after 5 minutes
    Then enrichment_status is enriched
    And the state is ready

  @transition:received->ready @config:on_unavailable=wait @config:after_max_wait=continue @failure
  Scenario: Source down, wait mode, gives up and continues
    Given the consumer sets on_unavailable to wait, max_wait to 15m and after_max_wait to continue
    And "loki" is down for 1 hour
    When 15 minutes pass
    Then enrichment_status is unavailable
    And the state is ready

  @transition:received->awaiting_operator @config:on_unavailable=wait @config:after_max_wait=operator @failure
  Scenario: Source down, wait mode, gives up and sends to an operator
    Given the consumer sets on_unavailable to wait, max_wait to 15m and after_max_wait to operator
    And "loki" is down for 1 hour
    When 15 minutes pass
    Then enrichment_status is unavailable
    And the state is awaiting_operator

  @default
  Scenario: A message waiting for an operator without logs is enriched again in the background
    Given a message in awaiting_operator with enrichment_status unavailable
    When "loki" is available again
    Then the Enricher queries "loki" for the message
    And enrichment_status is enriched
    And the state is still awaiting_operator

  @default
  Scenario: An operator asks for enrichment again
    Given a message in awaiting_operator with enrichment_status not_found
    When the operator asks to enrich it again
    Then the new result replaces the reference
    And the request is recorded in the audit log
    And the state does not change
