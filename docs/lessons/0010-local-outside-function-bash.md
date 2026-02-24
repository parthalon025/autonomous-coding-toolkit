---
id: 10
title: "`local` outside function silently misbehaves in bash"
severity: blocker
languages: [shell]
scope: [language:bash]
category: silent-failures
pattern:
  type: syntactic
  regex: "^local "
  description: "`local` keyword used at script top-level, outside any function"
fix: "Never use `local` outside a function; use plain variable assignment at script scope"
example:
  bad: |
    #!/bin/bash
    local result="value"
    echo "Result: $result"
    # Works on some shells, fails/ignored on others
  good: |
    #!/bin/bash
    result="value"
    echo "Result: $result"
    # Works consistently across all shells
---

## Observation
A bash script uses the `local` keyword at script top-level, outside any function. The script works on one machine but fails on another, or silently produces empty values on a third. The `local` keyword is not portable when used outside function scope.

## Insight
In bash, `local` is only defined for use within functions — it declares a variable in the local function scope. At script scope, `local` is undefined behavior. Some shells silently accept and ignore it (variable remains undefined), others error. Creating scripts that work on one machine but fail on another due to shell differences.

## Lesson
Never use `local` outside a function. At script scope, use plain variable assignment (`var=value`). Functions use `local var=value` for local scope. Script scope has no `local` keyword — all variables are global by default. Grep patterns checking for `^local ` are syntactic checks to catch this at write time.
