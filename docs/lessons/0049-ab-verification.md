---
id: 0049
title: "A/B verification finds zero-overlap bug classes"
severity: should-fix
languages: [all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Using only bottom-up or only top-down review misses entire classes of bugs"
fix: "Run both bottom-up (code-level) and top-down (architecture-level) review after 3+ batch implementations"
example:
  bad: |
    # Bottom-up only: review each component's code
    # Result: logic errors caught, but coupling issues missed
    # Reviewer doesn't see: API expects array, client sends object

    # Top-down only: review architecture diagrams
    # Result: structure looks good, but off-by-one in retry logic missed
    # Reviewer doesn't see: code-level bugs
  good: |
    # Bottom-up: Review code implementation
    - Are loops correct? Error handling present? State managed correctly?

    # Top-down: Review architecture
    - Do components couple correctly? Is data flow end-to-end?

    # Both perspectives together catch more bugs than either alone
---

## Observation
Code reviews conducted only from the bottom-up (code-level logic) miss architectural coupling issues. Reviews conducted only from the top-down (architecture diagrams) miss implementation bugs. Different bugs are visible from different angles.

## Insight
Bugs fall into different categories based on visibility:
- **Bottom-up visible:** off-by-one errors, null checks, state management, loop logic
- **Top-down visible:** coupling between components, interface mismatches, data flow breaks, missing error propagation
- **Requires both:** race conditions, distributed state consistency, integration deadlocks

## Lesson
Run both bottom-up and top-down review after implementing 3+ batches. Bottom-up: inspect code for logic errors, edge cases, resource cleanup. Top-down: trace data flow end-to-end, verify component interfaces match, check for coupling leaks. Document findings from each perspective. Bugs caught only in top-down review indicate architectural issues; bugs caught only in bottom-up indicate implementation issues. Fix both before declaring done.
