---
id: 51
title: "Infrastructure fixes in a plan cannot benefit the run executing that plan"
severity: should-fix
languages: [shell]
scope: [project:autonomous-coding-toolkit]
category: integration-boundaries
pattern:
  type: semantic
  description: "A plan includes tasks that fix the execution infrastructure (e.g., empty batch detection, parser improvements) but the current run-plan.sh process loaded the old code at startup"
fix: "Place infrastructure fixes in a separate pre-flight plan, or accept that the current run uses old behavior and the fix only helps future runs."
example:
  bad: |
    # Plan Batch 1: Fix empty batch detection in run-plan-headless.sh
    # -> Fix is committed, but the running bash process already loaded old code
    # -> Batches 6-19 still spawn claude for empty batches (43s each)
  good: |
    # Option A: Separate pre-flight plan for infra fixes, then main plan
    # Option B: Accept the cost — document that infra fixes are forward-looking
    # Option C: Use --start-batch to re-run from where infra fix takes effect
---

## Observation
The Phase 4 plan included Task 1: "Fix empty batch detection in run-plan-headless.sh." The fix was committed during Batch 1. However, the `run-plan.sh` bash process had already loaded `run-plan-headless.sh` at startup. Batches 6-19 (parser artifacts) still spawned a `claude -p` process for each empty batch (~30-50s each), wasting ~7 minutes and API calls.

## Insight
Bash reads `source` files once. The running process keeps the in-memory version of all sourced functions. Committing a fix to disk doesn't update the running process — only a new invocation reads the new code. This is fundamentally different from interpreted languages with hot-reload (Python's importlib, Node's require cache invalidation).

## Lesson
Infrastructure fixes (parser, quality gate, notification format) cannot benefit the execution that implements them. Either: (1) run infra fixes as a separate pre-flight step before the main plan, (2) accept the waste and document it as known, or (3) after the infra batch, stop and re-run with `--resume` so a fresh process loads the fixed code.
