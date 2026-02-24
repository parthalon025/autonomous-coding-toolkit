---
id: 0043
title: "Exact count assertions on extensible collections break on addition"
severity: should-fix
languages: [python, javascript, all]
scope: [universal]
category: test-anti-patterns
pattern:
  type: syntactic
  regex: "assert.*len\\(.*==\\s*\\d+"
  description: "Test asserts exact collection length that breaks when collection grows"
fix: "Use >= for extensible collections, or assert specific items exist rather than total count"
example:
  bad: |
    def test_users():
        users = get_users()
        assert len(users) == 3  # Breaks when a 4th user is added
  good: |
    def test_users():
        users = get_users()
        assert len(users) >= 3  # Allows growth
        assert "alice" in [u.name for u in users]
---

## Observation
Tests assert that a collection has an exact count (`assert len(items) == 5`). When the feature grows and items are added to the collection, the test fails even though the new behavior is correct. Tests become brittle and must be updated constantly.

## Insight
Exact counts are too restrictive for evolving features. The test really cares about specific items being present, not the total count. Switching to exact assertions makes tests fragile to future additions.

## Lesson
Use `>=` for collection length assertions in tests of extensible collections. Instead of asserting total count, assert that specific items exist: `assert "item" in collection` or `assert any(x.id == 5 for x in items)`. This makes tests resilient to future growth. Only use exact counts for fixed-size collections (e.g., tuple return values).
