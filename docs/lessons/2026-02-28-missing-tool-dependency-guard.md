# Lesson: Missing Tool Dependency Guard Silently Disables Safety-Critical Features

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** command -v, which, dependency guard, bc, tool check, silent disable, budget enforcement, safety feature, bash
**Files:** scripts/lib/cost-tracking.sh

---

## Observation (What Happened)

`cost-tracking.sh` implemented budget enforcement using `bc -l` for floating-point comparison. The call used `bc -l 2>/dev/null || echo 0` as a fallback. When `bc` is not installed (common on minimal containers, CI images, macOS without Homebrew), the fallback silently returns `"0"` — meaning the budget check ALWAYS passes regardless of actual spend. Budget enforcement becomes a silent no-op with zero operator visibility (#40).

## Analysis (Root Cause — 5 Whys)

**Why #1:** `bc` is not universally available; the fallback was added to prevent script crashes.
**Why #2:** The fallback value `"0"` (under-budget) was chosen to avoid false positives, but this inverts the safety contract — it produces false negatives instead.
**Why #3:** Safety features should fail closed (deny), not open (permit). A missing tool should block the operation, not silently allow it.
**Why #4:** No `command -v bc` check was added at script initialization to detect the missing dependency early and loudly.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Add `command -v bc >/dev/null 2>&1 \|\| { echo "ERROR: bc not found — budget enforcement disabled" >&2; return 1; }` at the top of `check_budget` | proposed | Justin | issue #40 |
| 2 | General rule: when a tool is required for a safety/security/budget feature, check it with `command -v` at the function or script entry point and fail loudly on absence | proposed | Justin | — |
| 3 | Alternative: replace `bc` with awk arithmetic (`awk "BEGIN {exit !(${total} > ${max})}"`) after validating inputs are numeric — removes the external dependency | proposed | Justin | issue #40, #69 |

## Key Takeaway

Safety-critical features that depend on external tools must check for tool availability with `command -v` and fail closed on absence — a silent `|| echo 0` fallback that permits all requests is worse than crashing.
