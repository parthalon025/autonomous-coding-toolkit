---
id: 50
title: "Editing files sourced by a running process breaks function signatures"
severity: blocker
languages: [shell]
category: integration-boundaries
pattern:
  type: semantic
  description: "Modifying function signatures in files that are actively sourced by a running bash process (e.g., editing run-plan-notify.sh while run-plan.sh is executing)"
fix: "Never edit library files while they're being sourced by a running process. Wait for the run to complete, or commit changes that only new runs will pick up."
example:
  bad: |
    # While run-plan.sh is running (sources run-plan-notify.sh at startup):
    # Edit run-plan-notify.sh to change format_success_message from 6 to 9 params
    # -> Next batch call crashes with wrong argument count
  good: |
    # Wait for run-plan.sh to finish, then edit
    # Or: make changes backward-compatible (add params with defaults)
    format_success_message() {
        local plan="$1" batch="$2" total="${3:-?}" title="${4:-}"
        # ... rest uses defaults for missing params
    }
---

## Observation
During Phase 4 execution, `run-plan-notify.sh` was edited to add `total_batches` and `batch_title` parameters to `format_success_message` (6 → 9 params). The running `run-plan.sh` process had already sourced the original file at startup. When the next batch called `notify_success` with the old 6-parameter signature, the quality gate detected uncommitted changes and failed.

## Insight
Bash sources files once at startup — there's no hot-reload. But the *file on disk* is what `git diff` sees. So editing a sourced file creates a two-way failure: (1) the running process uses stale function signatures, and (2) the quality gate sees uncommitted changes. The fix had to be committed to unblock the gate, but that commit changed signatures the running process was still calling with old argument counts.

## Lesson
Treat sourced library files as immutable during execution. If you must change them: (a) make changes backward-compatible with default parameter values, (b) commit immediately so the quality gate stays clean, and (c) accept that the current run uses the old behavior. Never change function arity in a file that a running process has already sourced.
