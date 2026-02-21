---
id: 13
title: "`export` prefix in env files breaks naive parsing"
severity: should-fix
languages: [shell]
category: silent-failures
pattern:
  type: syntactic
  regex: "cut -d= -f2"
  description: "Env file parser using cut without stripping export prefix"
fix: "Strip `export ` prefix before parsing: sed 's/^export //'"
example:
  bad: |
    # .env file with export prefix
    # export API_KEY=secret123
    # Read without stripping export
    value=$(grep "API_KEY" .env | cut -d= -f2)
    # Works for KEY=value but fails for export KEY=value
  good: |
    # Strip export prefix before parsing
    value=$(grep "API_KEY" .env | sed 's/^export //' | cut -d= -f2)
    # Works for both KEY=value and export KEY=value
---

## Observation
`.env` files commonly use `export VAR=value` syntax (for shell-source-ability). A parser uses `grep VAR= file | cut -d= -f2` to extract values. For lines like `KEY=value` it works fine. For lines with `export KEY=value`, the `cut` command returns the correct value, but if the parsing step checks for the line format first (e.g., expecting no `export` prefix), it silently skips those lines.

## Insight
The root cause is assuming `.env` format is always `KEY=value` without the `export` keyword. Many `.env` files use `export` for shell-sourcing (so they can be sourced with `source .env`). Parsers that don't account for this prefix will silently skip or misparse those lines.

## Lesson
`.env` file parsers should strip the `export` prefix before parsing. Use `sed 's/^export //'` to normalize lines, then parse. This handles both `KEY=value` and `export KEY=value` consistently. Never assume the format — always normalize first.
