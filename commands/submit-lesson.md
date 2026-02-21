---
description: "Submit a lesson learned from a bug you encountered — contributes back to the community"
argument-hint: "[description of the bug or anti-pattern]"
---

# Submit Lesson

Help the user capture a lesson learned and generate a PR against the autonomous-coding-toolkit repo.

## Process

### 1. Understand the Bug

Ask the user what happened. If `$ARGUMENTS` is provided, use that as the starting description. Clarify:
- What was the expected behavior?
- What actually happened?
- What code was involved? (file paths, snippets)
- How long did it take to find the bug?

### 2. Identify the Pattern

Determine:
- **Category:** async-traps | resource-lifecycle | silent-failures | integration-boundaries | test-anti-patterns | performance
- **Severity:** blocker (data loss, crashes, silent corruption) | should-fix (subtle bugs, degraded behavior) | nice-to-have (code smell, future risk)
- **Languages:** which languages this applies to (python, javascript, typescript, shell, all)

### 3. Determine Check Type

Is this pattern detectable by grep (syntactic) or does it need AI context (semantic)?

**Syntactic** (grep-detectable, near-zero false positives):
- Generate a `grep -P` regex that catches the anti-pattern
- Test the regex against the user's actual code to verify it works
- Verify it doesn't produce false positives on nearby code

**Semantic** (needs context, AI-detectable):
- Write a clear description of what to look for
- Include a concrete bad/good example
- The lesson-scanner agent will use this for contextual analysis

### 4. Generate the Lesson File

Auto-assign the next available ID:
```bash
# Find the highest existing ID
max_id=$(ls docs/lessons/[0-9]*.md 2>/dev/null | sed 's/.*\///' | sed 's/-.*//' | sort -n | tail -1)
next_id=$(printf "%04d" $((10#${max_id:-0} + 1)))
```

Generate slug from title (lowercase, hyphens, no special chars).

Write the lesson file using this schema:

```yaml
---
id: <next_id>
title: "<concise title>"
severity: <blocker|should-fix|nice-to-have>
languages: [<list>]
category: <category>
pattern:
  type: <syntactic|semantic>
  regex: "<grep -P pattern>"     # Only for syntactic
  description: "<what to look for>"
fix: "<how to fix it>"
example:
  bad: |
    <code that demonstrates the anti-pattern>
  good: |
    <code that demonstrates the fix>
---

## Observation
<What happened — factual description>

## Insight
<Why it happened — root cause>

## Lesson
<The rule to follow going forward>
```

### 5. Save and Offer Contribution

Save to `docs/lessons/<next_id>-<slug>.md`.

Show the user the generated file and ask:

**Option A: Save locally only**
- File is saved in the current project's `docs/lessons/` directory
- Available to their local lesson-check.sh and lesson-scanner

**Option B: Submit as PR to the toolkit repo**
- Fork the toolkit repo if needed: `gh repo fork parthalon025/autonomous-coding-toolkit --clone=false`
- Create a branch: `lesson/<id>-<slug>`
- Commit the lesson file
- Open a PR:
  ```bash
  gh pr create --repo parthalon025/autonomous-coding-toolkit \
    --title "lesson: <title>" \
    --body "## New Lesson

  **Category:** <category>
  **Severity:** <severity>
  **Pattern type:** <syntactic|semantic>

  ## What this catches
  <description>

  ## How it was discovered
  <user's bug description>
  "
  ```

## Quality Bar

Before submitting, verify:
- [ ] The regex (if syntactic) catches the bad example
- [ ] The regex does NOT match the good example
- [ ] The description is clear enough for the lesson-scanner to use
- [ ] The fix is actionable (not just "be careful")
- [ ] The example is realistic (from real code, anonymized)
