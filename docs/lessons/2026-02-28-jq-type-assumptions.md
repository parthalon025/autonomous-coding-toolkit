# Lesson: jq Type Assumptions — tonumber Crashes Non-Numeric Input; add Returns null on Empty

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** jq, tonumber, null, empty array, add, type error, sort_by, bash, shell, json
**Files:** scripts/pipeline-status.sh, scripts/lib/cost-tracking.sh

---

## Observation (What Happened)

Two separate jq bugs were introduced by assuming input types without guarding:

1. `pipeline-status.sh` used `sort_by(.key | tonumber)` on a cost map that could contain the non-numeric key `"final"`. `tonumber` on a string that isn't numeric crashes jq, silently falling back to `0` via `// 0` masking — total cost always displayed as `0` or `/bin/bash` (#42, #70).

2. `cost-tracking.sh` computed `[.costs[].estimated_cost_usd] | add` on an empty `costs` object. `jq .add` on an empty array returns `null`, writing `null` to `total_cost_usd`. Downstream budget enforcement reads this as `0` and passes the budget check (#41).

## Analysis (Root Cause — 5 Whys)

**Why #1 (tonumber):** `sort_by(.key | tonumber)` assumes all keys are numeric. The "final" batch key is a string sentinel, not a number.
**Why #2 (tonumber):** Error was hidden by `2>/dev/null || true` at the call site, turning a crash into a silent zero.
**Why #3 (add on empty):** `[...] | add` is documented to return `null` for empty input — the developer expected `0`.
**Why #4:** Both patterns are common jq idioms that work for the happy path and fail silently for edge cases, making them hard to detect through manual inspection or basic testing.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Use `sort_by(.key)` (lexicographic) instead of `sort_by(.key \| tonumber)` unless ALL keys are guaranteed numeric; or filter with `select(.key \| test("^[0-9]+$"))` first | proposed | Justin | issue #42, #70 |
| 2 | Always use `([...] \| add) // 0` or `([...values \| . // 0] \| add // 0)` to handle empty-array null from `add` | proposed | Justin | issue #41 |
| 3 | Remove `2>/dev/null` from jq calls where the output feeds a budget/safety check — allow jq errors to surface | proposed | Justin | issue #42, #63 |
| 4 | When jq processes heterogeneous key sets, validate or normalize before type-specific operations | proposed | Justin | — |

## Key Takeaway

`jq .add` returns null on empty input and `tonumber` crashes on non-numeric strings — both silently corrupt downstream numeric checks; always apply `// 0` to `add` and guard `tonumber` with `select` or `test`.
