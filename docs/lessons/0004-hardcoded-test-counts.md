---
id: 4
title: "Hardcoded count assertions break when datasets grow"
severity: should-fix
languages: [python, javascript, typescript]
category: test-anti-patterns
pattern:
  type: syntactic
  regex: "assert.*==\\s*\\d+|expect\\(.*\\)\\.toBe\\(\\d+\\)|assert_equal.*\\d+"
  description: "test assertion comparing count to a hardcoded number"
fix: "Use >= for extensible collections, or assert against a computed expected value rather than a magic number"
example:
  bad: |
    assert len(collectors) == 15  # Breaks when a 16th collector is added
  good: |
    assert len(collectors) >= 15  # Passes as collection grows
    # Or better: assert expected_collector in collectors
---

## Observation
Tests that assert exact counts (e.g., `assert len(items) == 15`) break every time a new item is added to an extensible collection. This creates friction where adding a feature requires updating unrelated test files.

## Insight
Exact count assertions conflate "the collection is not empty and has the expected items" with "the collection has exactly N items." The former is what you usually want to test; the latter creates brittle coupling.

## Lesson
For extensible collections, use `>=` assertions or check for specific members. Reserve exact count assertions for fixed-size structures where the count is genuinely part of the contract.
