---
id: 68
title: "Agent builds the wrong thing correctly"
severity: blocker
languages: [all]
scope: [universal]
category: specification-drift
pattern:
  type: semantic
  description: "Agent misinterprets requirements — code passes tests but doesn't match the actual spec. Tests were written against the agent's interpretation, not the user's intent."
fix: "Before implementation, echo back the spec in your own words and get explicit user confirmation. Write acceptance criteria from the spec, not from your interpretation."
example:
  bad: |
    # User asks for "retry with backoff"
    # Agent implements retry with fixed 1s delay
    # Test checks retry happens — passes
    # But spec meant exponential backoff
  good: |
    # Echo back: "I'll implement retry with exponential backoff: 1s, 2s, 4s, 8s, max 30s"
    # User confirms or corrects
    # Write test that verifies exponential timing
---

## Observation
An agent received a feature request, implemented it with full test coverage, and all tests passed. But the implementation didn't match what the user actually wanted — the agent's interpretation of the requirements diverged from the user's intent. The bug was only discovered during manual review.

## Insight
When an agent writes both the implementation AND the tests, the tests validate the agent's understanding, not the user's requirements. This creates a closed loop where wrong code passes wrong tests. The spec is the only external anchor — but agents often skip the echo-back step that would catch misinterpretation.

## Lesson
Always echo back requirements before implementing. The echo-back gate catches the 60%+ of failures that come from spec misunderstanding (not from coding errors). Write acceptance criteria from the original spec text, not from your paraphrase of it.
