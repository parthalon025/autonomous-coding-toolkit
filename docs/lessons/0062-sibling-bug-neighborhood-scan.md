---
id: 62
title: "Sibling bugs hide next to the fix"
severity: should-fix
languages: [all]
category: integration-boundaries
pattern:
  type: semantic
  description: "When fixing a bug in a function, scan adjacent functions in the same file for the same root cause pattern"
fix: "After fixing a function, grep the same file for the same anti-pattern in sibling functions"
example:
  bad: |
    # Fix complete_batch's --argjson crash, ship it
    # (set_quality_gate has the same crash 30 lines below)
  good: |
    # Fix complete_batch's --argjson crash
    # Scan file: grep -n 'argjson' run-plan-state.sh
    # Found same pattern in set_quality_gate — fix both
---

## Observation
In Phase 1 bug fixes, 2 of 8 tasks had code quality reviewers find the exact same bug in a sibling function within the same file. `set_quality_gate` had the same `--argjson` crash as `complete_batch`. The API curl lacked `--connect-timeout` just like the health check curl 6 lines above it.

## Insight
Implementers fix what the ticket says. The same root cause often exists in nearby code written at the same time with the same assumptions. Fresh-context subagents don't carry knowledge of what was just fixed, so they can't pattern-match on "I just fixed this — is there another one?"

## Lesson
After fixing a bug, grep the entire file for the same anti-pattern before committing. If the root cause is a bad API usage (like `--argjson` with strings), search for all call sites of that API in the file. Code review should always check: "does this same bug exist anywhere else in this file?"
