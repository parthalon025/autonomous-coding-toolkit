---
id: 53
title: "Missing jq -c flag causes string comparison failures in tests"
severity: should-fix
languages: [shell]
scope: [project:autonomous-coding-toolkit]
category: test-anti-patterns
pattern:
  type: syntactic
  regex: "assert_eq.*\\$\\(.*jq [^-]"
  description: "Using jq without -c flag in a string comparison assertion — pretty-printed output won't match compact expected values"
fix: "Always use jq -c (compact) when the output will be compared as a string. Or compare with jq equality instead of string equality."
example:
  bad: |
    result=$(echo "$json" | jq '.[0] | sort')
    assert_eq "group is [1]" '[1]' "$result"
    # FAIL: expected [1], got [\n  1\n]
  good: |
    result=$(echo "$json" | jq -c '.[0] | sort')
    assert_eq "group is [1]" '[1]' "$result"
    # PASS: both are [1]
---

## Observation
In `test-run-plan-team.sh`, three assertions failed because one `jq` call used `jq '.[2] | sort'` (pretty-printed) while the test expected compact JSON `[4]`. The other two calls on adjacent lines correctly used `jq -c`. The inconsistency was introduced when the test was generated — two of three similar lines got the `-c` flag, one didn't.

## Insight
jq defaults to pretty-printing (multi-line, indented). When output is stored in a variable and compared with `assert_eq`, the multi-line string `[\n  4\n]` never matches the compact string `[4]`. This is invisible until the test runs because the pattern looks correct at a glance. The failure message shows the actual as multi-line, making the `-c` omission obvious only in hindsight.

## Lesson
In shell test scripts, always use `jq -c` when the result will be compared as a string. Better yet, use `jq -e` for boolean checks or compare with `jq --argjson expected '[4]' '. == $expected'` to avoid format sensitivity entirely.
