---
id: 88
title: "Batch N depends on code created by Batch N+2 — forward dependency in plan"
severity: blocker
languages: [all]
scope: [universal]
category: planning-control-flow
pattern:
  type: semantic
  description: "A plan orders batches such that an early batch imports, calls, or depends on code that a later batch creates. When the early batch executes, the dependency doesn't exist yet. The batch fails at runtime, not at planning time."
fix: "Before executing any plan, verify the dependency graph: for each import/call in batch N, confirm the target exists in batches 1 through N-1. Dependencies must always flow forward."
positive_alternative: "Draw the dependency graph explicitly in the plan frontmatter. Mark each batch with what it produces and what it consumes. Verify consumers come after producers."
example:
  bad: |
    # Batch 1: create src/cli.py — imports from src/pipeline.py (doesn't exist yet)
    # Batch 2: create src/parser.py
    # Batch 3: create src/pipeline.py ← cli.py needed this in Batch 1
    # Batch 1 fails at import time
  good: |
    # Batch 1: create src/parser.py (no deps)
    # Batch 2: create src/pipeline.py (imports parser — exists)
    # Batch 3: create src/cli.py (imports pipeline — exists)
    # Linear dependency flow, each batch can execute immediately
---

## Observation

A plan was written top-down (from user-facing to infrastructure) without reordering for execution. The CLI batch came first because that's how the user thinks about the feature. But the CLI imported a pipeline module that was created in Batch 3. Batch 1 failed immediately with `ModuleNotFoundError`. The plan was valid as documentation; it was invalid as an execution sequence.

## Insight

Plans are often written in the order that makes sense to the author (top-down: UI → backend → data) but must be executed in the order that satisfies dependencies (bottom-up: data → backend → UI). This inversion is easy to catch during planning and catastrophic to discover during execution — because by the time Batch 1 fails, the agent has consumed a full context window.

## Lesson

After writing a plan, validate the execution order against the dependency graph. For each batch, list what it produces and what it imports. If a batch imports something produced by a later batch, swap them. A 5-minute dependency audit prevents a guaranteed Batch 1 failure. The rule is simple: producers before consumers, always.
