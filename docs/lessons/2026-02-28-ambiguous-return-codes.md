# Lesson: Ambiguous Return Codes — Same Exit Status for Multiple Distinct States

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** return code, exit status, ambiguous, empty string, distinguishable states, bash, function contract, silent fallback
**Files:** scripts/lib/progress-writer.sh, scripts/lib/run-plan-context.sh

---

## Observation (What Happened)

`read_batch_progress` in `progress-writer.sh` returned empty string + exit 0 for three completely different states: (1) the state file doesn't exist, (2) the file exists but the requested batch key is absent, (3) the batch exists but was recorded with empty content. The calling code in `run-plan-context.sh` couldn't distinguish these and fell back to `tail -10` on all three — injecting the last 10 lines of any batch as context, regardless of which batch was requested (#56).

## Analysis (Root Cause — 5 Whys)

**Why #1:** The function returns the same signal (empty + exit 0) for three semantically different outcomes.
**Why #2:** The author treated all three as "no data available" without considering that callers need to distinguish "nothing exists yet" from "data was corrupted/wrong key."
**Why #3:** Bash functions have only one exit code channel (0-255) and one stdout channel — using both to encode state is necessary when multiple outcomes matter.
**Why #4:** The fallback logic in the caller (`tail -10`) was designed for the "file missing" case but silently activated for all three cases, injecting wrong-batch data into the agent context.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Use distinct exit codes: 0 = found and non-empty, 1 = file missing, 2 = batch key not found, 3 = batch exists but empty | proposed | Justin | issue #56 |
| 2 | When exit codes aren't enough, use stderr diagnostics per case: `echo "state:file_missing" >&2` — callers can capture stderr separately | proposed | Justin | — |
| 3 | Document the exit code contract in a comment above the function; add a test for each distinct return case | proposed | Justin | — |
| 4 | Callers must check the specific exit code before applying fallback logic — `if [[ $? -eq 1 ]]; then fallback` not `if [[ -z "$result" ]]; then fallback` | proposed | Justin | issue #54 |

## Key Takeaway

When a function can return multiple distinct states, it must use distinct exit codes (or stderr markers) for each — collapsing all empty-result cases to `exit 0` forces callers to guess, which produces silent wrong-data injection.
