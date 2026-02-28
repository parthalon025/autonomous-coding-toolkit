---
id: 90
title: "No rollback plan for a failed batch leaves codebase in partial state"
severity: should-fix
languages: [all]
scope: [universal]
category: planning-control-flow
pattern:
  type: semantic
  description: "A batch fails mid-execution after creating some files and modifying others. The plan has no recovery path — no instructions for what the agent should do if a batch fails, and no clean checkpoint to return to. The codebase is in a partial state: some batch work is done, some is not."
fix: "Before executing any batch, ensure all prior work is committed. On batch failure, instruct the agent to revert all changes from the failed batch: `git checkout -- .` or create a revert commit. Define the retry strategy in the plan."
positive_alternative: "Each batch starts from a clean git state. If a batch fails, the recovery path is: revert to last clean commit, diagnose, fix the plan, retry. Write the recovery path into the plan before executing."
example:
  bad: |
    # Batch 3 fails after creating 4 files, modifying 2
    # State: partial implementation, tests failing
    # Plan: no recovery path defined
    # --resume: retries from batch 3 start, encounters partially-created files
    # Retry fails differently than original attempt
  good: |
    # Batch 3 fails
    # Recovery: git stash or git checkout -- . to clean state
    # Diagnose: read quality gate output, identify root cause
    # Fix: update plan with corrected batch 3
    # Retry: clean start, no partial state to navigate
---

## Observation

A batch modifying a database schema failed after running the migration but before updating the ORM models. The `--resume` flag re-ran the batch from the start. The migration ran again and failed (already applied). The ORM models were partially updated from the previous attempt. The partial state made each retry fail differently, making root cause diagnosis much harder than if the batch had been cleanly reverted.

## Insight

Autonomous batch execution needs the same discipline as database transactions: either the full batch completes (commit) or nothing changes (rollback). Without a defined rollback path, failed batches leave the codebase in a state that is harder to diagnose than either the before-state or after-state — partial implementations fail in unexpected ways.

## Lesson

Every plan must define its recovery path for batch failure. The simplest policy: every batch starts from a clean git commit (git-clean gate enforced before each batch). On failure, `git checkout -- .` returns to the clean state. The batch is re-planned, not just re-run. Partial state is the enemy — revert completely rather than trying to resume from a half-completed batch.
