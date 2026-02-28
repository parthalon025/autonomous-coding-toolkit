---
id: 89
title: "Batch too large for one context window — later tasks execute with degraded attention"
severity: should-fix
languages: [all]
scope: [universal]
category: planning-control-flow
pattern:
  type: semantic
  description: "A single batch contains 6+ tasks or touches 10+ files. By the time the agent reaches the last tasks, it has consumed significant context with earlier tasks. The last tasks are executed with degraded attention and lower accuracy."
fix: "Keep batches to 1-5 tasks and under 100 lines of estimated implementation. If a batch grows beyond this, split it — create a second batch for the overflow tasks."
positive_alternative: "Score each batch by task count and estimated line change. 1-3 tasks = ideal. 4-5 tasks = acceptable. 6+ tasks = split required. Use the plan quality scorecard before executing."
example:
  bad: |
    # Batch 3: Add user management (8 tasks)
    # Task 1-3: model, migration, repository (agent sharp)
    # Task 4-6: service layer, validation, error handling (agent degrading)
    # Task 7-8: API endpoints, tests (agent at 60% attention)
    # Tasks 7-8 have subtle bugs — missed by degraded agent
  good: |
    # Batch 3: User model, migration, repository (3 tasks)
    # Batch 4: Service layer, validation, error handling (3 tasks)
    # Batch 5: API endpoints and integration tests (2 tasks)
    # Each batch executes with full attention
---

## Observation

A batch labeled "Add user management" contained 8 tasks. Tests for the first 5 tasks passed. Tests for tasks 6, 7, and 8 had subtle errors: missing validation in the error handler, an off-by-one in pagination, and a missing assertion in the integration test. These were the last tasks the agent executed. The errors correlated exactly with the agent's position in the context window.

## Insight

Each task the agent completes consumes context. By the time it reaches task 7 of an 8-task batch, it has also processed: the batch description, 6 prior task implementations, 6 sets of test output, any corrections, and all the context injected at batch start. The agent's effective attention for task 7 is significantly lower than for task 1 — this is measurable and consistent.

## Lesson

Keep batches to 1-5 tasks. Estimate line changes before planning: 50 lines per task is a reasonable average for new implementation. If a batch exceeds 250 estimated lines, split it. The split point should be at a natural module boundary, not arbitrary. Each sub-batch should be independently testable. Smaller batches produce higher-quality output per unit of plan effort.
