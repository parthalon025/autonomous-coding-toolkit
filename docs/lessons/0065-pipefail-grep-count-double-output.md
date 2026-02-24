---
id: 65
title: "pipefail + grep -c + fallback produces double output"
severity: should-fix
languages: [shell]
scope: [language:bash]
category: silent-failures
pattern:
  type: syntactic
  regex: "grep\\s+-c.*\\|\\|\\s*echo\\s+0"
  description: "grep -c piped with || echo 0 under set -o pipefail produces '0\\n0' — grep writes 0, then fallback also writes 0"
fix: "Wrap grep -c in a helper function that captures the exit code internally, or use || true inside a subshell"
positive_alternative: "Use a _count_matches helper: result=$(grep -c ... || true); echo \"${result:-0}\""
example:
  bad: |
    set -euo pipefail
    count=$(echo "$text" | grep -c "pattern" || echo 0)
    # Produces "0\n0" when no match — grep outputs 0, then fallback also outputs 0
  good: |
    set -euo pipefail
    _count_matches() {
        local result exit_code=0
        result=$(grep -ciE "$1" 2>&1) || exit_code=$?
        [[ $exit_code -le 1 ]] && echo "${result:-0}" || echo "0"
    }
    count=$(echo "$text" | _count_matches "pattern")
---

## Observation

In `validate-plan-quality.sh`, scoring functions used `grep -ciE "pattern" || echo 0` to count matches safely. Under `set -euo pipefail`, when grep found zero matches (exit 1), both grep's output ("0") AND the fallback ("0") were written to stdout, producing "0\n0" instead of "0".

## Insight

`set -o pipefail` propagates the non-zero exit from grep through the pipe, causing the `|| echo 0` fallback to execute. But grep already wrote "0" to stdout before exiting. The fallback then appends another "0". This is invisible in most tests because `[[ "0\n0" -gt 0 ]]` still works in bash (it reads the first line), but it corrupts any downstream parsing.

## Lesson

Never use `command || echo default` for commands that write output before failing. Instead, capture the exit code in a wrapper function and handle it explicitly. The `_count_matches` pattern works: run grep inside the function, capture exit code, distinguish "no matches" (exit 1, normal) from "grep error" (exit 2+, unexpected).
