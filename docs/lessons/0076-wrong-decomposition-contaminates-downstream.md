---
id: 76
title: "Wrong decomposition contaminates all downstream batches"
severity: blocker
languages: [all]
scope: [universal]
category: planning-control-flow
pattern:
  type: semantic
  description: "A plan decomposes work into batches where an early batch has the wrong boundary — wrong files, wrong order, or wrong grouping. All subsequent batches inherit the wrong foundation and compound the error."
fix: "Validate decomposition before execution: check that batch boundaries align with module boundaries, dependencies flow forward (never backward), and each batch is independently testable."
example:
  bad: |
    # Batch 1: Create API + frontend (too broad, untestable)
    # Batch 2: Add tests (tests written after, not with)
    # Batch 3: Integration (discovers Batch 1 was wrong)
  good: |
    # Batch 1: Create API with tests (independently verifiable)
    # Batch 2: Create frontend with tests (independently verifiable)
    # Batch 3: Integration wiring with e2e test
---

## Observation
A plan decomposed a feature into 5 batches. Batch 1 grouped files incorrectly — putting the data model and the API handler in the same batch when they had different dependencies. Every subsequent batch built on batch 1's incorrect structure. By batch 4, the agent was fighting the architecture instead of building on it.

## Insight
Decomposition errors are the most expensive kind of plan bug because they compound. Each batch that builds on a wrong foundation adds more code that depends on the wrong structure. The cost to fix grows quadratically with the number of affected batches.

## Lesson
Validate plan decomposition before executing. Check: Does each batch align with a natural module boundary? Do dependencies flow strictly forward (batch N never depends on batch N+1)? Is each batch independently testable? A 10-minute decomposition review prevents multi-hour rework.
