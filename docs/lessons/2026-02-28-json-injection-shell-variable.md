# Lesson: JSON Injection via Direct Shell Variable Interpolation in jq Strings

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** security
**Keywords:** jq, json injection, variable interpolation, --arg, --argjson, session_id, shell injection, bash
**Files:** scripts/lib/cost-tracking.sh

---

## Observation (What Happened)

`cost-tracking.sh` interpolated `$session_id` directly into a JSON string literal passed to `jq`:

```bash
jq -cn "{\"session_id\": \"$session_id\", \"cost\": $cost}"
```

If `$session_id` contains a double-quote or backslash (e.g., from a corrupted session name), the string produces invalid JSON. `jq --argjson` then fails and silently drops the cost record. Because the failure is swallowed with `2>/dev/null`, the cost is lost and budget enforcement never sees it (#36).

Beyond data loss, a session_id containing `", "injected": "value` would produce valid but malformed JSON with injected fields.

## Analysis (Root Cause — 5 Whys)

**Why #1:** Shell variable interpolation into JSON string literals bypasses JSON escaping rules.
**Why #2:** jq has dedicated `--arg` and `--argjson` flags specifically to prevent this — they handle escaping correctly — but the developer used string interpolation for brevity.
**Why #3:** The error is silent because `2>/dev/null` suppresses jq parse failures, and the caller treats the missing output as a non-event.
**Why #4:** The same pattern (interpolation + error suppression) appears in multiple places in the file, indicating a copy-paste convention, not a one-off mistake.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Use `jq -cn --arg sid "$session_id" --argjson cost "$cost" '{"session_id": $sid, "cost": $cost}'` — never interpolate shell variables into jq's JSON body | proposed | Justin | issue #36 |
| 2 | The same rule applies to awk: `awk -v val="$var" '{print val}'` instead of `awk "BEGIN {print $var}"` | proposed | Justin | issue #69 |
| 3 | Remove `2>/dev/null` from jq calls that write financial/safety data — errors must surface | proposed | Justin | issue #36, #63 |

## Key Takeaway

Never interpolate shell variables directly into jq's JSON body — use `--arg` (string) and `--argjson` (typed value) which handle all escaping correctly; direct interpolation produces injection-vulnerable, silently-broken JSON.
