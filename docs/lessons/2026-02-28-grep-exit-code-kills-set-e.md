# Lesson: grep Exits 1 on No-Match, Killing the Parent Process Under set -e

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** grep, exit code, set -e, pipefail, no-match, 1, bash, shell, silent kill, JSONL
**Files:** scripts/lib/cost-tracking.sh

---

## Observation (What Happened)

`cost-tracking.sh` used bare `grep '"type":"summary"' "$jsonl_path"` inside a function sourced into `run-plan.sh`, which runs under `set -euo pipefail`. When the JSONL file contains no summary line — the legitimate "session not yet complete" case — `grep` returns exit code `1`, and `set -e` kills the entire run-plan process silently. The abort is indistinguishable from a crash (#35).

## Analysis (Root Cause — 5 Whys)

**Why #1:** `grep` exit code 1 means "no match" (not an error), but `set -e` treats any non-zero exit as fatal.
**Why #2:** The developer used `grep` for a lookup inside a `set -e` context without accounting for the no-match case.
**Why #3:** No-match is the expected case for in-progress sessions; the code was written assuming the file always has a summary line.
**Why #4:** The bash standard distinguishes exit 1 (no match) from exit 2+ (error) for `grep`, but `set -e` does not — it kills on any non-zero.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Append `|| true` ONLY to grep calls where no-match is a legitimate empty result: `summary=$(grep '"type":"summary"' "$jsonl_path" \| tail -1 \|\| true)` | proposed | Justin | issue #35 |
| 2 | To distinguish no-match from error: `grep ... "$file" \|\| { [[ $? -eq 1 ]] \|\| exit 1; }` — propagates exit 2+ (file not found, permission denied) but absorbs exit 1 | proposed | Justin | — |
| 3 | Audit all bare `grep` calls inside functions that are sourced into `set -e` scripts; add `|| true` or `|| [[ $? -eq 1 ]]` selectively | proposed | Justin | — |

## Key Takeaway

`grep` exit 1 means "no match" — in a `set -e` script, every bare `grep` that might legitimately find nothing is a silent process-killer; use `grep ... || true` for lookup patterns where empty results are valid.
