# Contributing Lessons

The autonomous-coding-toolkit improves with every user's production failures. When you encounter a bug caused by an anti-pattern, you can submit it as a lesson that becomes an automated check for every user.

## How Lessons Become Checks

```
You encounter a bug
  → Run /submit-lesson to capture it
  → PR is opened against this repo
  → Maintainer reviews and merges
  → Lesson file lands in docs/lessons/
  → lesson-check.sh picks up syntactic patterns automatically
  → lesson-scanner agent picks up semantic patterns automatically
  → Every user's next scan catches that anti-pattern
```

**Two tiers of enforcement:**

| Tier | Type | Speed | How it works |
|------|------|-------|-------------|
| Fast | Syntactic (grep-detectable) | <2 seconds | `lesson-check.sh` reads the lesson's `regex` field and runs `grep -P` |
| Deep | Semantic (needs context) | Minutes | `lesson-scanner` agent reads the lesson's `description` and `example` fields |

Adding a lesson file is all it takes — no code changes to the scanner or check script.

## Submitting a Lesson

### Option 1: Use the `/submit-lesson` command (recommended)

Inside a Claude Code session with this toolkit installed:

```
/submit-lesson "bare except clauses hide failures in production"
```

The command walks you through:
1. Describing the bug
2. Classifying severity and category
3. Generating a grep pattern (if syntactic)
4. Writing the lesson file
5. Opening a PR

### Option 2: Manual PR

1. Copy `docs/lessons/TEMPLATE.md` to `docs/lessons/NNNN-<slug>.md`
2. Fill in the YAML frontmatter and body sections
3. Open a PR with title: `lesson: <short description>`

## Lesson File Format

Every lesson file has YAML frontmatter that the tools parse:

```yaml
---
id: 7                              # Auto-assigned sequential ID
title: "Short descriptive title"
severity: blocker                  # blocker | should-fix | nice-to-have
languages: [python]                # python | javascript | typescript | shell | all
category: silent-failures          # See categories below
pattern:
  type: syntactic                  # syntactic | semantic
  regex: "^\\s*except\\s*:"       # grep -P pattern (syntactic only)
  description: "what to look for"
fix: "how to fix it"
example:
  bad: |
    <anti-pattern code>
  good: |
    <correct code>
---

## Observation
[What happened — the bug, the symptom]

## Insight
[Why it happened — the root cause]

## Lesson
[The rule to follow going forward]
```

## Categories

| Category | What it covers |
|----------|---------------|
| `async-traps` | Forgotten awaits, concurrent modification, coroutine misuse |
| `resource-lifecycle` | Leaked connections, missing cleanup, subscription without unsubscribe |
| `silent-failures` | Bare exceptions, swallowed errors, lost stack traces |
| `integration-boundaries` | Cross-module bugs, path issues, API contract mismatches |
| `test-anti-patterns` | Brittle assertions, mocking the wrong thing, false confidence |
| `performance` | Missing filters, unnecessary work, resource waste |

## Severity Guide

| Severity | When to use | Examples |
|----------|------------|---------|
| `blocker` | Data loss, crashes, silent corruption | Bare except swallowing errors, async def returning coroutine instead of result |
| `should-fix` | Subtle bugs, degraded behavior, tech debt | Leaked connections, hardcoded test counts, missing callbacks |
| `nice-to-have` | Code smells, future risks, style | Naming issues, missing type hints, suboptimal patterns |

## Quality Bar

Before submitting, verify:

1. **Real bug** — The lesson comes from a bug you actually encountered, not a hypothetical
2. **Regex accuracy** (syntactic only) — The regex catches the bad example and does NOT match the good example
3. **Clear description** — Someone unfamiliar with your codebase can understand the anti-pattern
4. **Actionable fix** — The fix section tells you what to do, not just "be careful"
5. **Realistic example** — The bad/good examples are from real code (anonymized if needed)

## Review Process

1. **Automated checks** — PR CI verifies the YAML frontmatter parses correctly and required fields are present
2. **Regex testing** — Maintainer tests the regex against real codebases for false positive rate
3. **Category review** — Maintainer verifies severity and category are appropriate
4. **Merge** — Once approved, the lesson is immediately available to all users on next toolkit update

## What Makes a Great Lesson

The best lessons:
- Come from bugs that took >30 minutes to debug
- Have a syntactic pattern (grep-detectable = instant enforcement for everyone)
- Apply across multiple projects (not just your specific codebase)
- Include the "why" — understanding the mechanism prevents the entire class of bug, not just this instance
