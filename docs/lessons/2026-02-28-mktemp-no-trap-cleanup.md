# Lesson: mktemp Without trap Leaks Temp Files on Early Exit

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** mktemp, temp file, temp dir, trap, EXIT, RETURN, cleanup, resource leak, set -e
**Files:** scripts/lib/cost-tracking.sh, scripts/lib/run-plan-context.sh, scripts/tests/test-progress-writer.sh

---

## Observation (What Happened)

Three separate scripts created temp files or directories via `mktemp`/`mktemp -d` with no `trap` registered to clean them up. Under `set -euo pipefail`, any command failure between the `mktemp` call and the inline `rm` exits the script immediately, leaving the temp resource on disk permanently. In production loops that run per-batch, this accumulates indefinitely.

Specific instances:
- `cost-tracking.sh:70-77` — `record_batch_cost` creates `$tmp` with `mktemp`, no trap; jq failure leaves it on disk (#37)
- `run-plan-context.sh:154,161` — `record_failure_pattern` creates `$tmp` with `mktemp`, no trap; called in production loops (#58)
- `test-progress-writer.sh:78,91` — creates `WORK2` and `WORK3` with `mktemp -d`, only cleaned inline; assertion failure under `set -e` leaks both dirs (#59)

## Analysis (Root Cause — 5 Whys)

**Why #1:** Temp files leak because the script exits via `set -e` before reaching the inline `rm -f "$tmp"`.
**Why #2:** The developer placed cleanup inline (after the use) rather than in a `trap`, assuming normal flow would always reach it.
**Why #3:** `set -e` turns ANY non-zero exit into an immediate abort, making "clean up at the end" a broken pattern — the end is never reached on failure.
**Why #4:** There is no project convention requiring `trap` for every `mktemp`, so each script author independently chose inline cleanup.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | After every `mktemp`, immediately register `trap 'rm -f "$tmp"' RETURN` (function scope) or `trap 'rm -rf "$TMPDIR"' EXIT` (script scope) before any other command | proposed | Justin | issues #37, #58, #59 |
| 2 | For multiple temps in one script, accumulate them: `CLEANUP=(); trap 'rm -rf "${CLEANUP[@]}"' EXIT` and `CLEANUP+=("$tmp")` after each `mktemp` | proposed | Justin | issue #59 (WORK2/WORK3) |
| 3 | Add to project lint rules: flag any `mktemp` not immediately followed by a `trap` | proposed | Justin | — |

## Key Takeaway

Every `mktemp` must be paired with a `trap ... RETURN` or `trap ... EXIT` on the very next line — inline cleanup is silently skipped by `set -e` on any upstream failure.
