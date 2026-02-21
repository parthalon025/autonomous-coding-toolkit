---
description: "Execute an implementation plan batch-by-batch with quality gates between each batch"
argument-hint: "<plan-file> [--start-batch N] [--end-batch N] [--mode headless|team|competitive]"
---

# Run Plan

Execute the implementation plan: $ARGUMENTS

## How This Works

You are orchestrating batch-by-batch execution of a markdown plan file. Each batch contains tasks that you implement sequentially using TDD, then a quality gate runs before proceeding to the next batch.

## Step 1: Parse the Plan

Read the plan file specified in the arguments. Extract:
- All batches (lines matching `## Batch N: Title`)
- Tasks within each batch (lines matching `### Task M: Name`)
- Any metadata header (test baseline, quality gate command, tech stack)

Report what you found:
```
Plan: <filename>
Batches: N total
Batch 1: <title> (M tasks)
Batch 2: <title> (M tasks)
...
```

If `--start-batch` or `--end-batch` were specified, note the execution range.

## Step 2: Initialize State

Create or read `.run-plan-state.json` in the current working directory:
```json
{
  "plan_file": "<plan-file>",
  "mode": "<mode>",
  "current_batch": 1,
  "completed_batches": [],
  "test_counts": {},
  "started_at": "<ISO timestamp>",
  "last_quality_gate": null
}
```

If the state file already exists and `--resume` was not specified, ask the user whether to resume or start fresh.

## Step 3: Execute Batches

For each batch in the execution range:

### Mode: headless (default)
Execute each task in the batch yourself using TDD:
1. **Write a failing test** for the task
2. **Run the test** — confirm it fails
3. **Implement** the minimum code to pass
4. **Run the test** — confirm it passes
5. **Commit** the task with a descriptive message

### Mode: team
For each batch, spawn two agents:
1. **Implementer** (general-purpose agent via Task tool) — receives the full batch text, implements using TDD
2. **Reviewer** (code-reviewer agent via Task tool) — reviews the implementer's git diff against the batch spec

If the reviewer finds issues, send fixes back to the implementer. Then run the quality gate.

### Mode: competitive
For critical batches (marked `⚠ CRITICAL` in the plan or specified via `--competitive-batches`):
1. Create two git worktrees: `.worktrees/competitor-a` and `.worktrees/competitor-b`
2. Spawn two implementer agents, one per worktree, with different strategies
3. After both finish, spawn a judge agent to compare:
   - Tests passing (binary gate)
   - Spec compliance (weight: 0.4)
   - Code quality (weight: 0.3)
   - Test coverage (weight: 0.3)
4. Cherry-pick the winner's commits into the main worktree
5. Clean up both competitor worktrees

Non-critical batches fall back to team mode.

## Step 4: Quality Gate (after every batch)

Run the quality gate between every batch. Default: `scripts/quality-gate.sh --project-root .`

The quality gate checks:
1. **Lesson check** — scan changed files for known anti-patterns
2. **Test suite** — auto-detected (pytest / npm test / make test)
3. **Memory check** — warn if < 4GB available

Additionally check:
- **Test count regression** — the number of passing tests must be >= the previous batch's count
- **Git clean** — all changes must be committed

If the quality gate fails:
- Report what failed and why
- Ask the user how to proceed (fix, skip, or abort)

Update the state file after each batch completes.

## Step 5: Summary

After all batches complete, report:
```
Plan: <filename>
Batches completed: N of M
Test progression: 0 → 25 → 58 → 112
Duration: <total time>
Quality gates: all passed
```

## Rules

- **TDD is mandatory.** Every task gets a failing test before implementation.
- **Quality gates are mandatory.** Never skip to the next batch without passing.
- **Test counts only go up.** If tests decrease, something broke — fix it.
- **Commit after every task.** Small, atomic commits with descriptive messages.
- **Update progress.txt** after each batch with a summary of what was done.
- **Fresh context matters.** If you're past batch 5 and context feels degraded, suggest the user run `scripts/run-plan.sh --resume` headlessly for remaining batches.
