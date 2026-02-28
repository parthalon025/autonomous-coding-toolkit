# Lesson: Unquoted Bash String Comparison — [[  $var != true  ]] Misbehaves on Unset Variables

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** bash, string comparison, unquoted, [[ ]], set -u, unbound variable, quoting, boolean flag, env var
**Files:** scripts/lib/run-plan-headless.sh

---

## Observation (What Happened)

`run-plan-headless.sh` contained:

```bash
if [[ $SKIP_ECHO_BACK != true ]]; then
```

The rest of the codebase quotes both operands: `[[ "$var" != "value" ]]`. The unquoted form works for simple values when the variable is set, but under `set -u`, an unset `$SKIP_ECHO_BACK` triggers "unbound variable" rather than treating it as empty. Additionally, the unquoted pattern is visually inconsistent and a source of diff noise when editors auto-fix it (#65 in issues).

## Analysis (Root Cause — 5 Whys)

**Why #1:** The developer omitted quotes on the variable reference in a `[[ ]]` comparison.
**Why #2:** `[[ ]]` does not perform word-splitting on unquoted variables (unlike `[ ]`), so it "works" for simple cases — this masks the inconsistency.
**Why #3:** Under `set -u`, an unset variable causes an unbound variable error regardless of the `[[ ]]` quoting rules.
**Why #4:** There is no enforced linting rule (shellcheck fires on this, but the file had a shellcheck disable block nearby).

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Always quote both sides of string comparisons: `[[ "$SKIP_ECHO_BACK" != "true" ]]` | proposed | Justin | issue #65 |
| 2 | Use `${VAR:-}` default for optional boolean flags to avoid `set -u` unbound variable errors: `[[ "${SKIP_ECHO_BACK:-}" != "true" ]]` | proposed | Justin | — |
| 3 | Run shellcheck without disables on any file modified; fix SC2086/SC2090 warnings rather than suppressing them | proposed | Justin | — |

## Key Takeaway

Always quote both operands in bash `[[ ]]` string comparisons — the unquoted form silently works until the variable is unset, at which point `set -u` turns it into a fatal error instead of a predictable empty-string comparison.
