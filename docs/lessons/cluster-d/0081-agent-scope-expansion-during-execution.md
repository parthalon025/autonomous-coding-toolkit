---
id: 81
title: "Agent expands batch scope beyond plan during execution"
severity: should-fix
languages: [all]
scope: [universal]
category: specification-drift
pattern:
  type: semantic
  description: "During execution, the agent notices a related improvement and implements it alongside the planned work. The batch now contains work that wasn't planned, wasn't reviewed, and wasn't quality-gated as part of the original design."
fix: "Batch instructions must say explicitly: 'Do not implement anything not described in this batch. If you notice improvements, add them to progress.txt for a future batch.'"
positive_alternative: "Capture improvements in progress.txt as future work. The current batch stays exactly scoped. Unplanned changes go through the same brainstorm → plan → quality gate cycle."
example:
  bad: |
    # Batch 2: Add rate limiting
    # Agent adds rate limiting + refactors auth middleware + adds logging
    # All new code — none of it planned or reviewed
    # Quality gate passes (tests still pass)
  good: |
    # Batch 2: Add rate limiting only
    # Agent adds rate limiting, notes refactoring opportunity in progress.txt
    # Refactoring added to plan as Batch 5 after human review
---

## Observation

A batch tasked with adding rate limiting to an API produced a diff that included rate limiting, a full refactoring of the authentication middleware, and new logging configuration — none of the latter two were in the plan. The quality gate passed because tests still passed. The unreviewed changes introduced a subtle bug in the auth middleware that wasn't caught until production.

## Insight

Agents are trained to be helpful, and "helpful" includes fixing things they notice. This is valuable in interactive use but dangerous in autonomous execution where there is no human review between batches. Scope expansion compounds: each unplanned change is a deviation from the design, and deviations from design are how bugs enter a codebase without a clear owner.

## Lesson

Every batch prompt must include a scope constraint: "Implement only what is described in this batch. Do not fix, refactor, or improve adjacent code. If you identify valuable improvements, write them to progress.txt as future work." Without this constraint, autonomous agents will helpfully introduce unreviewed changes.
