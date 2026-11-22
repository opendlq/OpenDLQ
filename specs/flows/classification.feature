Feature: Classification and routing
  The Policy Engine classifies every ready message as transient or permanent,
  then routes it. It checks five signals in order and stops at the first that answers.
  It is the only place where a message changes path.

  Background:
    Given a consumer "orders"
    And a message in ready

  # Signals

  @transition:ready->awaiting_operator @default
  Scenario: The consumer header answers first
    Given the message has x-failure-kind permanent
    And a rule would classify its error as transient
    When the Policy Engine classifies it
    Then it is permanent, classified_by header

  @transition:ready->retrying @default
  Scenario: A default rule answers when there is no header
    Given the message has no x-failure-kind
    And x-failure-reason is "HTTP 503"
    When the Policy Engine classifies it
    Then it is transient, classified_by rule

  @transition:ready->awaiting_operator @default
  Scenario: A rule reads a field extracted from the logs
    Given a classifier rule "enrichment.error_class == 'SkuFormatException'" with kind permanent
    And the enrichment extracted error_class "SkuFormatException"
    When the Policy Engine classifies it
    Then it is permanent, classified_by rule

  @default
  Scenario: Group memory reuses an earlier decision
    Given the message has no header and no rule matches
    And group_key "x:payments" was classified permanent by an operator 2 hours ago
    When the Policy Engine classifies it
    Then it is permanent, classified_by group

  @default
  Scenario: Group memory expires
    Given group_key "x:payments" was classified permanent 25 hours ago
    And nothing else answers
    When the Policy Engine classifies it
    Then group memory does not answer

  @default
  Scenario: The exception class in the logs answers
    Given no header, rule or group memory answers
    And the enrichment carries exception class "JsonParseException"
    When the Policy Engine classifies it
    Then it is permanent, classified_by logs

  @default
  Scenario: A rule overrides the built-in exception table
    Given a classifier rule maps "JsonParseException" to transient
    And the enrichment carries exception class "JsonParseException"
    When the Policy Engine classifies it
    Then it is transient, classified_by rule

  @transition:ready->retrying @default
  Scenario: Nothing answers, so the message starts as transient
    Given no signal answers
    When the Policy Engine classifies it
    Then it is transient, classified_by inference

  @transition:ready->awaiting_operator @default
  Scenario: The same message fails the same way 3 times
    Given the message was inferred transient
    And it failed 3 times with the same error
    When the Policy Engine classifies it again
    Then it is permanent, classified_by inference

  @transition:ready->awaiting_operator @default @failure
  Scenario: Logs are unavailable, classification continues without them
    Given enrichment_status is unavailable
    When the Policy Engine classifies it
    Then the exception class and the log fields in rules do not answer
    And the other signals are checked as usual

  @config:classifier=plugin
  Scenario: A team replaces the classifier
    Given the consumer declares a classifier plugin "orders-classifier"
    When the Policy Engine classifies it
    Then the plugin receives the message, headers, error, enrichment and history
    And returns kind, dependency and group_key
    And classified_by is plugin

  # Routing

  @transition:ready->runbook_matched @default
  Scenario: A runbook match comes before the transient path
    Given the message is transient
    And a runbook matches it
    When the Policy Engine routes it
    Then the state is runbook_matched

  @transition:ready->held @default
  Scenario: Transient with the dependency circuit open
    Given the message is transient with dependency "payments"
    And the circuit for "payments" is open
    When the Policy Engine routes it
    Then the state is held

  @transition:ready->awaiting_operator @default
  Scenario: Attempts are exhausted
    Given the message has 5 failed attempts and retry.max is 5
    When the Policy Engine routes it
    Then the state is awaiting_operator
    And the reason is "retries exhausted"

  @transition:ready->awaiting_operator @default
  Scenario: Permanent with no runbook
    Given the message is permanent
    And no runbook matches
    When the Policy Engine routes it
    Then the state is awaiting_operator

  @default
  Scenario: A path that already failed is skipped
    Given the runbook "legacy-sku" failed for this message
    And "legacy-sku" still matches
    When the Policy Engine routes it
    Then it does not send the message to "legacy-sku" again
    And it routes by the next rule in precedence

  @default
  Scenario: Every decision is recorded with its signal
    When the Policy Engine routes the message
    Then the transition records kind, classified_by, the route and the version of the policy
