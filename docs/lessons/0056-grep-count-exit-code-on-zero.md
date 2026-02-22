---
id: 56
title: "grep -c exits 1 on zero matches, breaking || fallback arithmetic"
severity: should-fix
languages: [shell]
category: silent-failures
pattern:
  type: syntactic
  regex: "grep\\s+-c.*\\|\\|\\s*echo\\s+[\"']?0[\"']?"
  description: "grep -c with || echo 0 fallback — produces multiline output on zero matches"
fix: "Use || true with ${var:-0} default instead of || echo 0"
example:
  bad: |
    count=$(echo "$text" | grep -c "pattern" || echo "0")
    result=$((count + 1))  # breaks: count="0\n0" from both outputs
  good: |
    count=$(echo "$text" | grep -c "pattern" || true)
    count=${count:-0}
    result=$((count + 1))
---

## Observation

`grep -c` returns both the count AND exit code 1 when count is 0.
With `|| echo "0"`, the fallback fires AND grep's "0" output is kept,
producing `"0\n0"`. Bash arithmetic `$((0\n0 + 1))` fails with
"syntax error in expression".

## Insight

`grep -c` violates the common assumption that exit code 1 means "error."
In grep, exit 1 means "no matches found" — a valid result, not a failure.
The `|| echo "0"` pattern double-counts because the subshell captures
grep's stdout ("0") AND the fallback echo ("0") on separate lines.

## Lesson

Never use `grep -c ... || echo "0"` for count fallback. Use
`grep -c ... || true` to suppress the exit code, then `${var:-0}` as
the numeric default. This pattern is safe because `|| true` doesn't
add to stdout — it only prevents `set -e` from aborting the script.
