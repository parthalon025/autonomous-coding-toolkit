---
id: 66
title: "local keyword used outside function scope"
severity: should-fix
languages: [shell]
category: silent-failures
pattern:
  type: semantic
  description: "bash `local` keyword outside a function body — undefined behavior, works in bash but fails in dash/sh and is technically a bug"
fix: "Only use `local` inside function bodies. At script top-level, just assign the variable directly."
positive_alternative: "Remove `local` from top-level variable assignments; use plain assignment instead"
example:
  bad: |
    # At script top-level (not inside a function)
    if [[ "$JSON_OUTPUT" == true ]]; then
        local escaped_plan
        escaped_plan=$(printf '%s' "$PLAN_FILE" | jq -Rs '.')
    fi
  good: |
    # At script top-level — no local keyword
    if [[ "$JSON_OUTPUT" == true ]]; then
        escaped_plan=$(printf '%s' "$PLAN_FILE" | jq -Rs '.')
    fi
---

## Observation

In `validate-plan-quality.sh`, the JSON output block at the script's top level used `local escaped_plan` to declare a variable. This worked in bash but is technically undefined behavior — `local` is only valid inside functions.

## Insight

Bash tolerates `local` outside functions (it just creates a regular variable), but this is a portability landmine. If the script is ever sourced by another script or run with `dash`/`sh`, it fails. It also misleads readers into thinking the code is inside a function when it isn't.

## Lesson

Reserve `local` for function bodies exclusively. At script top-level, use plain variable assignment. This is especially important in scripts that use `source` chains, where the boundary between "inside a function" and "top-level" blurs across files.
