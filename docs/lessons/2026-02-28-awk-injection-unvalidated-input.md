# Lesson: awk Code Injection via Unvalidated Numeric Variable Interpolation

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** security
**Keywords:** awk, injection, unvalidated input, numeric, BEGIN, bash, shell injection, security, budget
**Files:** scripts/lib/cost-tracking.sh

---

## Observation (What Happened)

`cost-tracking.sh` passed `$total` and `$max_budget` directly into an awk expression:

```bash
if awk "BEGIN {exit !(${total} > ${max_budget})}" 2>/dev/null; then
```

If `$total` is read from a state file that has been corrupted or tampered with, it could contain awk code instead of a number (e.g., `0); system("rm -rf /");//`). The `2>/dev/null` means awk parse failures also silently bypass budget enforcement. A non-numeric value in `$total` produces either code execution or a silent "under budget" pass (#69).

## Analysis (Root Cause — 5 Whys)

**Why #1:** Shell variables are interpolated into awk's program string without validation.
**Why #2:** awk's `BEGIN { ... }` block executes arbitrary awk code — any string injected into the expression is interpreted as code, not data.
**Why #3:** The `2>/dev/null` suppresses the awk parse error that would otherwise signal an injection attempt.
**Why #4:** The values come from a file (`$state_file`) that could be corrupted by disk errors, partial writes, or previous bugs — treating them as trusted is a false assumption.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Validate that `$total` and `$max_budget` are numeric before passing to awk: `[[ "$total" =~ ^[0-9]+(\.[0-9]+)?$ ]] \|\| { echo "ERROR: non-numeric total" >&2; return 1; }` | proposed | Justin | issue #69 |
| 2 | Use awk's `-v` flag to pass values as data, not code: `awk -v t="$total" -v m="$max_budget" 'BEGIN {exit !(t > m)}'` — `-v` prevents code injection | proposed | Justin | issue #69 |
| 3 | Remove `2>/dev/null` so awk parse errors surface as visible failures | proposed | Justin | issue #69 |
| 4 | General rule: never interpolate shell variables into awk program strings; always use `-v varname="$shell_var"` | proposed | Justin | — |

## Key Takeaway

Shell variable interpolation into awk program strings enables code injection — always use `awk -v varname="$val"` to pass values as data, and validate numeric inputs before arithmetic operations in safety-critical paths.
