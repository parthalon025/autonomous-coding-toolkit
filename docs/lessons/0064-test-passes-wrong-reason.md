---
id: 64
title: "Tests that pass for the wrong reason provide false confidence"
severity: should-fix
languages: [all]
category: test-anti-patterns
pattern:
  type: semantic
  description: "A test that reaches the expected outcome through a different code path than intended — usually because the test setup has unintended side effects that mask the real behavior"
fix: "Verify the test fails when the fix is reverted. Ensure test setup affects only the variable under test, not its dependencies."
example:
  bad: |
    # Test: free is missing → exit 2
    PATH="/fake/bin"  # removes awk too!
    check_memory_available 4  # exits 2 because awk is missing, not free
  good: |
    # Test: free is missing → exit 2
    PATH="/fake/bin:$PATH"  # fake free, real awk
    check_memory_available 4  # exits 2 because free outputs nothing
---

## Observation
A test to verify `check_memory_available` returns exit 2 when `free` is unavailable set `PATH="/fake/bin"` (replacing entire PATH). This also removed `awk`, so the function returned exit 2 because awk failed — not because free was missing. The test passed, but it wasn't testing what it claimed.

## Insight
Tests that replace environment state (PATH, env vars, config files) can have blast radius beyond the intended target. The test author thinks they're isolating one variable, but they're changing a system-wide setting that affects multiple tools in the pipeline.

## Lesson
When mocking system commands, prepend to PATH (`PATH="$fake:$PATH"`) rather than replacing it. After writing a test, revert the fix and verify the test fails — if it still passes, it's testing the wrong thing. Name tests to describe the code path they exercise, not just the expected outcome.
