# Lesson Template

Copy this file to `docs/lessons/NNNN-<slug>.md` where NNNN is the next sequential ID.

```yaml
---
id: <next sequential number>
title: "<Short descriptive title — what the anti-pattern IS>"
severity: <blocker|should-fix|nice-to-have>
languages: [<python|javascript|typescript|shell|all>]
scope: [<universal|language:X|framework:X|domain:X|project:X>]  # optional, defaults to universal
category: <async-traps|resource-lifecycle|silent-failures|integration-boundaries|test-anti-patterns|performance>
pattern:
  type: <syntactic|semantic>
  regex: "<grep -P pattern>"       # Required for syntactic, omit for semantic
  description: "<what to look for>"
fix: "<one-line description of the correct approach>"
example:
  bad: |
    <2-5 lines showing the anti-pattern>
  good: |
    <2-5 lines showing the correct code>
---

## Observation
<What happened — the bug, the symptom, the impact. Be factual and specific.>

## Insight
<Why it happened — the root cause, the mechanism that makes this dangerous.>

## Lesson
<The rule to follow. One paragraph, actionable, testable.>
```

## Field Guide

### Severity
- **blocker** — Data loss, crashes, silent corruption. Must fix before merge.
- **should-fix** — Subtle bugs, degraded behavior, tech debt. Fix in this sprint.
- **nice-to-have** — Code smells, future risk. Fix when touching the file.

### Pattern Type
- **syntactic** — Detectable by grep. Requires a `regex` field. Used by `lesson-check.sh` for instant enforcement (<2s). Aim for near-zero false positives.
- **semantic** — Needs context to detect. Requires a `description` field. Used by the `lesson-scanner` agent during verification. Can have higher false positive tolerance since AI reviews context.

### Categories
| Category | What it covers |
|----------|---------------|
| `async-traps` | Forgotten awaits, concurrent modification, coroutine misuse |
| `resource-lifecycle` | Leaked connections, missing cleanup, subscription without unsubscribe |
| `silent-failures` | Bare exceptions, swallowed errors, lost stack traces |
| `integration-boundaries` | Cross-module bugs, path issues, API contract mismatches |
| `test-anti-patterns` | Brittle assertions, mocking the wrong thing, false confidence |
| `performance` | Missing filters, unnecessary work, resource waste |

### Scope (Project-Level Filtering)
Scope controls which projects a lesson applies to. Language filtering (`languages:`) picks files; scope filtering picks projects. Both are orthogonal.

| Tag Format | Example | Matches |
|------------|---------|---------|
| `universal` | `[universal]` | All projects (default) |
| `language:<lang>` | `[language:python]` | Projects with that language |
| `framework:<name>` | `[framework:pytest]` | Projects using that framework |
| `domain:<name>` | `[domain:ha-aria]` | Domain-specific projects |
| `project:<name>` | `[project:autonomous-coding-toolkit]` | Exact project match |

Default when omitted: `[universal]` — backward compatible.

### Writing Good Regex Patterns
- Test with `grep -P "<pattern>" <your_file>` before submitting
- Escape special characters: `\\.` for literal dot, `\\(` for literal paren
- Use `\\b` for word boundaries to reduce false positives
- Use `\\s` for any whitespace
- Prefer patterns that match the *structure* of the anti-pattern, not specific variable names

## Examples

See existing lessons in this directory for reference:
- `0001-bare-exception-swallowing.md` — syntactic, blocker
- `0002-async-def-without-await.md` — semantic, blocker
- `0003-create-task-without-callback.md` — semantic, should-fix
