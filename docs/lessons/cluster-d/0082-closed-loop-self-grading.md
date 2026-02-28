---
id: 82
title: "Agent grades its own homework — tests validate interpretation, not spec"
severity: blocker
languages: [all]
scope: [universal]
category: specification-drift
pattern:
  type: semantic
  description: "The agent writes both the implementation and the tests for that implementation. When the implementation is based on a misunderstanding, the tests are also based on the misunderstanding — so they pass. The spec is the only external check, and the agent skipped comparing against it."
fix: "Derive tests directly from the spec text, not from the implementation. Write tests before implementing. Use the spec's exact wording in test descriptions so reviewers can trace test to requirement."
positive_alternative: "Write test descriptions that quote the spec: `test 'spec says: retry with exponential backoff — 1s, 2s, 4s'`. If you cannot find the spec text the test validates, the test is not grounded."
example:
  bad: |
    # Spec: "cache results for repeated queries"
    # Agent interprets: in-memory dict per request
    # Test: second call returns same result — passes
    # Reality: spec meant persistent cache across requests
  good: |
    # Before implementing: write test from spec literal text
    # test: 'spec: cache persists across process restart'
    # assert: result after restart matches result before restart
    # Now implementation must satisfy the external constraint
---

## Observation

A spec required "cache results for repeated queries." The agent implemented an in-memory dict that returned cached results within a single request lifecycle. Tests checked that calling the function twice returned the same result — which passed. The spec meant a persistent cross-request cache (Redis). Three batches were built on the wrong foundation before a code review caught the misunderstanding.

## Insight

When an agent writes both implementation and tests, the test suite validates the agent's internal consistency, not the external specification. This is a closed loop — the agent grades its own homework. The only way to break the loop is to anchor tests to the spec text before implementation begins. TDD is not just a quality technique; it is the mechanism that keeps the feedback loop open to external requirements.

## Lesson

Write tests from the spec before writing implementation. Test descriptions must quote or paraphrase the spec requirement they validate — not describe what the implementation does. An agent that writes tests after implementation is grading its own homework. The spec is the external anchor; always trace tests back to spec text.
