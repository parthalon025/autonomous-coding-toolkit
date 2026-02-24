---
id: 63
title: "One boolean flag serving two lifetimes is a conflation bug"
severity: should-fix
languages: [shell, python, javascript]
scope: [universal]
category: silent-failures
pattern:
  type: semantic
  description: "A boolean flag that is set in one lifecycle (e.g., per-iteration) but read in another (e.g., post-loop) — the flag's meaning changes depending on when you read it"
fix: "Split into separate variables with explicit lifecycle names (e.g., _baseline_stash_created vs _winner_stash_created)"
example:
  bad: |
    _stash_created=false
    # Set during per-candidate loop (baseline purpose)
    # Read after loop ends (winner purpose)
    # Same flag, different meanings at different times
  good: |
    _baseline_stash_created=false
    _winner_stash_created=false
    # Each flag has one meaning throughout its entire lifetime
---

## Observation
In the sampling stash fix (#27), `_stash_created` tracked both "was the baseline stashed?" (per-candidate lifecycle) and "was the winner stashed?" (post-loop lifecycle). When candidate 0 passed and its winner state was stashed, the next candidate's restore code popped the winner stash thinking it was the baseline.

## Insight
A boolean with two meanings at different points in time is a state machine with implicit transitions. The transitions are invisible because the variable name doesn't change — only the programmer's mental model of what it represents changes. This is especially dangerous in loops where the flag is set in one iteration and read in a different context.

## Lesson
When a flag variable is set in one code block and read in a different block with a different purpose, split it into named variables that encode their purpose. The variable name should make its lifecycle explicit. If you can't describe when the flag is "active" in one sentence, it needs to be split.
