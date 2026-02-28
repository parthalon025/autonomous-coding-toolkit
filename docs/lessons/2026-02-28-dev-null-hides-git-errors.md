# Lesson: 2>/dev/null on git Operations Silently Caches Bad Content

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** 2>/dev/null, git, stderr, error suppression, git stash pop, git branch, bad content, cache, bash
**Files:** scripts/lib/run-plan-headless.sh, scripts/lib/run-plan-prompt.sh

---

## Observation (What Happened)

Two patterns of `2>/dev/null` on git operations caused distinct failures:

1. `run-plan-prompt.sh` used `git branch ... 2>/dev/null` in `build_stable_prefix`. If `git branch` fails, empty or wrong branch info is written to the prefix cache file. All subsequent batches (which reuse this cached file) operate with corrupted branch context. The bad content persists across context resets (#46).

2. `run-plan-headless.sh` used `git stash pop 2>/dev/null` to suppress error messages. If stash pop fails due to merge conflicts, the worktree is left in an inconsistent state — the pop failure is invisible and the batch continues on corrupted state (#32).

## Analysis (Root Cause — 5 Whys)

**Why #1:** `2>/dev/null` was added to suppress "normal" warning output from git (e.g., "Nothing to pop"), but it also suppresses real error messages.
**Why #2:** The developer didn't distinguish between git's informational stderr (safe to suppress) and git's error stderr (dangerous to suppress).
**Why #3:** git writes both informational messages and errors to stderr, making blanket suppression always lossy.
**Why #4:** The output of the suppressed commands feeds a write operation — when git fails silently, the write creates bad content that is then cached and reused.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Never use `2>/dev/null` on git operations whose output is written to a file that will be reused — let errors surface; catch known-benign outputs by checking exit code | proposed | Justin | issue #46 |
| 2 | For `git stash pop`: check exit code explicitly: `git stash pop \|\| { echo "ERROR: stash pop failed" >&2; exit 1; }` | proposed | Justin | issue #32 |
| 3 | Validate the output of any git command before caching it: `[[ -n "$branch_info" ]] \|\| { echo "ERROR: empty git output" >&2; exit 1; }` | proposed | Justin | issue #46 |
| 4 | When suppressing git informational noise is genuinely needed, redirect to a debug log rather than /dev/null | proposed | Justin | — |

## Key Takeaway

`2>/dev/null` on any git operation whose output feeds a cache or file write is a data-corruption risk — git errors go to stderr, so suppressing stderr means a failed command silently writes empty or wrong data that persists across restarts.
