# Marketplace Restructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure the repo as a marketplace-ready Claude Code plugin with a dynamic community lesson system.

**Architecture:** Merge ralph-loop into top level, move commands to top level, add plugin/marketplace manifests, rewrite lesson-check.sh and lesson-scanner to read lesson files dynamically, create starter lesson files from hardcoded checks, add /submit-lesson command and CONTRIBUTING.md.

**Tech Stack:** Bash, Markdown (YAML frontmatter), jq, grep, awk

---

## Batch 1: Plugin Manifests & Directory Restructure

### Task 1: Create plugin.json manifest

**Files:**
- Create: `.claude-plugin/plugin.json`

**Step 1: Create the file**

```json
{
  "name": "autonomous-coding-toolkit",
  "description": "Complete autonomous coding pipeline: skills for every stage from brainstorming through verification, quality gates between batches, headless execution, and a lessons-learned feedback loop that compounds with every user",
  "version": "1.0.0",
  "author": {
    "name": "Justin McFarland",
    "email": "parthalon025@gmail.com"
  },
  "homepage": "https://github.com/parthalon025/autonomous-coding-toolkit",
  "repository": "https://github.com/parthalon025/autonomous-coding-toolkit",
  "license": "MIT",
  "keywords": ["autonomous", "tdd", "quality-gates", "headless", "skills", "pipeline", "lessons-learned"]
}
```

**Step 2: Commit**

```bash
git add .claude-plugin/plugin.json
git commit -m "feat: add plugin.json manifest for marketplace discovery"
```

### Task 2: Create marketplace.json

**Files:**
- Create: `.claude-plugin/marketplace.json`

**Step 1: Create the file**

```json
{
  "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
  "name": "autonomous-coding-toolkit",
  "description": "Autonomous coding pipeline with quality gates, fresh-context execution, and community lessons",
  "owner": {
    "name": "Justin McFarland",
    "email": "parthalon025@gmail.com"
  },
  "plugins": [
    {
      "name": "autonomous-coding-toolkit",
      "description": "Complete autonomous coding pipeline with skills, agents, scripts, and a community lesson system",
      "version": "1.0.0",
      "source": "./",
      "author": {
        "name": "Justin McFarland",
        "email": "parthalon025@gmail.com"
      },
      "category": "development"
    }
  ]
}
```

**Step 2: Commit**

```bash
git add .claude-plugin/marketplace.json
git commit -m "feat: add marketplace.json for self-hosted marketplace distribution"
```

### Task 3: Move commands to top level

**Files:**
- Move: `.claude/commands/code-factory.md` → `commands/code-factory.md`
- Move: `.claude/commands/create-prd.md` → `commands/create-prd.md`
- Move: `.claude/commands/run-plan.md` → `commands/run-plan.md`
- Move: `plugins/ralph-loop/commands/ralph-loop.md` → `commands/ralph-loop.md`
- Move: `plugins/ralph-loop/commands/cancel-ralph.md` → `commands/cancel-ralph.md`
- Delete: `.claude/commands/` directory
- Delete: `plugins/ralph-loop/commands/` directory

**Step 1: Create top-level commands/ and move files**

```bash
mkdir -p commands
mv .claude/commands/code-factory.md commands/
mv .claude/commands/create-prd.md commands/
mv .claude/commands/run-plan.md commands/
mv plugins/ralph-loop/commands/ralph-loop.md commands/
mv plugins/ralph-loop/commands/cancel-ralph.md commands/
rmdir .claude/commands
rmdir plugins/ralph-loop/commands
```

**Step 2: Update ralph-loop.md — change CLAUDE_PLUGIN_ROOT script path**

In `commands/ralph-loop.md`, the setup script path references `${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh`. After merge, the setup script will be at `scripts/setup-ralph-loop.sh` (same relative position from plugin root), so the path remains valid.

Verify `allowed-tools` in frontmatter still references the correct path pattern.

**Step 3: Commit**

```bash
git add commands/ .claude/commands/ plugins/ralph-loop/commands/
git commit -m "refactor: move commands to top-level for marketplace discovery"
```

### Task 4: Move ralph-loop hooks and scripts to top level

**Files:**
- Move: `plugins/ralph-loop/hooks/hooks.json` → `hooks/hooks.json`
- Move: `plugins/ralph-loop/hooks/stop-hook.sh` → `hooks/stop-hook.sh`
- Move: `plugins/ralph-loop/scripts/setup-ralph-loop.sh` → `scripts/setup-ralph-loop.sh`
- Delete: `plugins/ralph-loop/.claude-plugin/plugin.json`
- Delete: `plugins/` directory entirely

**Step 1: Move hooks**

```bash
mkdir -p hooks
mv plugins/ralph-loop/hooks/hooks.json hooks/
mv plugins/ralph-loop/hooks/stop-hook.sh hooks/
```

**Step 2: Move setup script**

```bash
mv plugins/ralph-loop/scripts/setup-ralph-loop.sh scripts/
```

**Step 3: Clean up plugins directory**

```bash
rm plugins/ralph-loop/.claude-plugin/plugin.json
rmdir plugins/ralph-loop/.claude-plugin
rmdir plugins/ralph-loop/scripts
rmdir plugins/ralph-loop/hooks
rmdir plugins/ralph-loop
rmdir plugins
```

**Step 4: Commit**

```bash
git add hooks/ scripts/setup-ralph-loop.sh plugins/
git commit -m "refactor: merge ralph-loop hooks and scripts into top level"
```

## Batch 2: Starter Lesson Files

### Task 5: Create starter lesson — bare exception swallowing

**Files:**
- Create: `docs/lessons/0001-bare-exception-swallowing.md`

**Step 1: Write lesson file with structured YAML frontmatter**

```yaml
---
id: 1
title: "Bare exception swallowing hides failures"
severity: blocker
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "^\\s*except\\s*:"
  description: "bare except clause without logging"
fix: "Always log the exception before returning a fallback: except Exception as e: logger.error(..., exc_info=True)"
example:
  bad: |
    try:
        result = api_call()
    except:
        return default_value
  good: |
    try:
        result = api_call()
    except Exception as e:
        logger.error("API call failed", exc_info=True)
        return default_value
---

## Observation
Bare `except:` clauses silently swallow all exceptions including KeyboardInterrupt, SystemExit, and MemoryError. When the fallback value is returned, there's no log trail to indicate a failure occurred, making debugging impossible.

## Insight
The root cause is a habit of writing "safe" exception handling that catches everything. The Python exception hierarchy means `except:` catches far more than intended. Combined with no logging, failures become invisible.

## Lesson
Never use bare `except:` — always catch a specific exception class and log before returning a fallback. The 3-line rule: within 3 lines of an except clause, there must be a logging call.
```

**Step 2: Commit**

```bash
git add docs/lessons/0001-bare-exception-swallowing.md
git commit -m "feat: add starter lesson 0001 — bare exception swallowing"
```

### Task 6: Create starter lesson — async def without await

**Files:**
- Create: `docs/lessons/0002-async-def-without-await.md`

**Step 1: Write lesson file**

```yaml
---
id: 2
title: "async def without await returns truthy coroutine"
severity: blocker
languages: [python]
category: async-traps
pattern:
  type: syntactic
  regex: "async\\s+def\\s+"
  description: "async def that may be missing await — requires multi-line analysis to confirm no await in function body"
  multi_line: true
fix: "Either add await for async I/O operations, or remove the async keyword if the function does no async work"
example:
  bad: |
    async def get_data():
        return database.query("SELECT *")  # Returns coroutine, not result
  good: |
    async def get_data():
        return await database.query("SELECT *")
---

## Observation
An `async def` function that never uses `await`, `async for`, or `async with` returns a coroutine object instead of its result. Since coroutine objects are truthy, code like `if await get_data():` silently succeeds with a truthy coroutine even when the actual data would be falsy.

## Insight
This is insidious because the function appears to work — it returns something truthy, no exceptions are raised, no warnings are logged. The bug only surfaces when the return value is used for its actual content rather than truthiness.

## Lesson
Every `async def` must contain at least one `await`, `async for`, or `async with`. If it doesn't need any, remove the `async` keyword. This check requires multi-line analysis (scanning the full function body), so it's a semantic check in the lesson-scanner rather than a simple grep.
```

**Step 2: Commit**

```bash
git add docs/lessons/0002-async-def-without-await.md
git commit -m "feat: add starter lesson 0002 — async def without await"
```

### Task 7: Create starter lesson — create_task without callback

**Files:**
- Create: `docs/lessons/0003-create-task-without-callback.md`

**Step 1: Write lesson file**

```yaml
---
id: 3
title: "asyncio.create_task without done_callback swallows exceptions"
severity: should-fix
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "create_task\\("
  description: "create_task() without add_done_callback within 5 lines — untracked task may swallow exceptions"
  multi_line: true
fix: "Add a done_callback that logs exceptions: task.add_done_callback(lambda t: t.exception() and logger.error(...))"
example:
  bad: |
    task = asyncio.create_task(process_event(data))
    # No callback — if process_event raises, you'll never know
  good: |
    task = asyncio.create_task(process_event(data))
    task.add_done_callback(lambda t: t.exception() and logger.error("Task failed", exc_info=t.exception()))
---

## Observation
`asyncio.create_task()` launches a coroutine as a background task. If the task raises an exception and nobody awaits it or checks its result, Python logs a "Task exception was never retrieved" warning at garbage collection time — which may be much later or not at all.

## Insight
Fire-and-forget tasks are a common pattern but they create invisible failure paths. The exception is silently stored in the task object and only surfaces (maybe) when the task is garbage collected.

## Lesson
Every `create_task()` call should be followed within 5 lines by `add_done_callback()` that handles exceptions. Alternatively, store the task and await it later.
```

**Step 2: Commit**

```bash
git add docs/lessons/0003-create-task-without-callback.md
git commit -m "feat: add starter lesson 0003 — create_task without callback"
```

### Task 8: Create starter lesson — hardcoded test counts

**Files:**
- Create: `docs/lessons/0004-hardcoded-test-counts.md`

**Step 1: Write lesson file**

```yaml
---
id: 4
title: "Hardcoded count assertions break when datasets grow"
severity: should-fix
languages: [python, javascript, typescript]
category: test-anti-patterns
pattern:
  type: syntactic
  regex: "assert.*==\\s*\\d+|expect\\(.*\\)\\.toBe\\(\\d+\\)|assert_equal.*\\d+"
  description: "test assertion comparing count to a hardcoded number"
fix: "Use >= for extensible collections, or assert against a computed expected value rather than a magic number"
example:
  bad: |
    assert len(collectors) == 15  # Breaks when a 16th collector is added
  good: |
    assert len(collectors) >= 15  # Passes as collection grows
    # Or better: assert expected_collector in collectors
---

## Observation
Tests that assert exact counts (e.g., `assert len(items) == 15`) break every time a new item is added to an extensible collection. This creates friction where adding a feature requires updating unrelated test files.

## Insight
Exact count assertions conflate "the collection is not empty and has the expected items" with "the collection has exactly N items." The former is what you usually want to test; the latter creates brittle coupling.

## Lesson
For extensible collections, use `>=` assertions or check for specific members. Reserve exact count assertions for fixed-size structures where the count is genuinely part of the contract.
```

**Step 2: Commit**

```bash
git add docs/lessons/0004-hardcoded-test-counts.md
git commit -m "feat: add starter lesson 0004 — hardcoded test counts"
```

### Task 9: Create starter lesson — sqlite without closing

**Files:**
- Create: `docs/lessons/0005-sqlite-without-closing.md`

**Step 1: Write lesson file**

```yaml
---
id: 5
title: "sqlite3 connections leak without closing() context manager"
severity: should-fix
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "sqlite3\\.connect\\("
  description: "sqlite3.connect() call — verify closing() context manager is used (with conn: manages transactions, not connections)"
fix: "Use contextlib.closing(): with closing(sqlite3.connect(db_path)) as conn:"
example:
  bad: |
    conn = sqlite3.connect("data.db")
    with conn:
        conn.execute("INSERT ...")
    # Connection never explicitly closed — relies on GC
  good: |
    from contextlib import closing
    with closing(sqlite3.connect("data.db")) as conn:
        with conn:
            conn.execute("INSERT ...")
---

## Observation
`with conn:` in sqlite3 manages transactions (auto-commit/rollback), NOT the connection lifecycle. The connection remains open until garbage collected. Under load or in long-running processes, this leaks file descriptors.

## Insight
Python's sqlite3 `with` statement is misleading — it looks like a resource manager but only manages transactions. The actual connection close requires either `conn.close()` or `contextlib.closing()`.

## Lesson
Always wrap `sqlite3.connect()` in `contextlib.closing()` for reliable cleanup. The pattern is: `with closing(connect(...)) as conn: with conn: ...` — outer for lifecycle, inner for transactions.
```

**Step 2: Commit**

```bash
git add docs/lessons/0005-sqlite-without-closing.md
git commit -m "feat: add starter lesson 0005 — sqlite without closing"
```

### Task 10: Create starter lesson — venv pip path

**Files:**
- Create: `docs/lessons/0006-venv-pip-path.md`

**Step 1: Write lesson file**

```yaml
---
id: 6
title: ".venv/bin/pip installs to wrong site-packages"
severity: should-fix
languages: [python, shell]
category: integration-boundaries
pattern:
  type: syntactic
  regex: "\\.venv/bin/pip\\b"
  description: ".venv/bin/pip instead of .venv/bin/python -m pip — pip shebang may point to wrong Python"
fix: "Use .venv/bin/python -m pip to ensure packages install into the correct virtual environment"
example:
  bad: |
    .venv/bin/pip install requests
  good: |
    .venv/bin/python -m pip install requests
---

## Observation
When multiple Python versions exist on the system (e.g., system Python + Homebrew Python), `.venv/bin/pip` may resolve to the wrong Python interpreter via its shebang line. Packages install into the wrong site-packages directory, making them invisible to the venv's Python.

## Insight
The pip executable's shebang (`#!/path/to/python`) is set at venv creation time. If PATH changes or another Python is installed later, the shebang becomes stale. Using `python -m pip` always uses the Python that's running it.

## Lesson
Never call `.venv/bin/pip` directly. Always use `.venv/bin/python -m pip` to guarantee the correct interpreter and site-packages directory.
```

**Step 2: Commit**

```bash
git add docs/lessons/0006-venv-pip-path.md
git commit -m "feat: add starter lesson 0006 — venv pip path"
```

## Batch 3: Dynamic Lesson System

### Task 11: Rewrite lesson-check.sh to read lesson files dynamically

**Files:**
- Modify: `scripts/lesson-check.sh`

**Step 1: Rewrite the script**

Replace the entire script with a dynamic version that:

1. Finds all lesson files in `docs/lessons/` matching `[0-9]*.md`
2. Parses YAML frontmatter to extract `pattern.type`, `pattern.regex`, `severity`, `title`, `id`, `languages`
3. For each lesson with `pattern.type: syntactic` and a non-empty `regex`:
   - Filter target files by language (`.py` for python, `.js`/`.ts` for javascript/typescript, all files for `shell`/`all`)
   - Run `grep -Pn "$regex"` against matching files
   - Report violations in `file:line: [lesson-N] title` format
4. Preserve: file gathering logic (args, stdin, git diff fallback), help text, exit codes
5. Remove: all 6 hardcoded checks (they're now in lesson files)
6. Handle `multi_line: true` lessons by noting them as "requires lesson-scanner" in help text

The script should find lessons relative to its own location (`SCRIPT_DIR`), not the current working directory, so it works when called from any project.

Key functions needed:
- `parse_frontmatter()` — extract YAML fields from a lesson file (awk-based, no external deps)
- `matches_language()` — check if a file matches a lesson's language filter
- Main loop that reads lessons and runs grep per lesson

**Step 2: Run existing tests to verify**

```bash
bash scripts/tests/run-all-tests.sh
```

The existing tests may need updating since checks are now dynamic. If tests reference specific lesson numbers, update them to match the new lesson file IDs.

**Step 3: Commit**

```bash
git add scripts/lesson-check.sh
git commit -m "feat: rewrite lesson-check.sh to read patterns from lesson files dynamically"
```

### Task 12: Rewrite lesson-scanner agent to be dynamic

**Files:**
- Modify: `agents/lesson-scanner.md`

**Step 1: Rewrite the agent**

Replace hardcoded scan groups with dynamic lesson loading:

```markdown
---
name: lesson-scanner
description: Scans codebase for anti-patterns from community lessons learned. Reads lesson files dynamically — adding a lesson file adds a check. Reports violations with file:line references.
tools: Read, Grep, Glob, Bash
---

You are a codebase auditor. Your checks come from lesson files, not hardcoded rules.

## Input

Project root directory (default: current working directory).

## Step 1: Load Lessons

Read all lesson files from the toolkit's `docs/lessons/` directory:
- Glob: `docs/lessons/[0-9]*.md`
- Parse YAML frontmatter from each file
- Group by category for organized scanning
- Filter by language (match target project's file types)

## Step 2: Run Syntactic Checks

For lessons with `pattern.type: syntactic`:
- Run `grep -Pn` with the lesson's `regex` against matching files
- For `multi_line: true` lessons, use multi-line grep or awk as needed
- Record: file, line, lesson ID, title, severity

## Step 3: Run Semantic Checks

For lessons with `pattern.type: semantic`:
- Use the lesson's `description` and `example` to guide analysis
- Read candidate files and look for the described anti-pattern in context
- Only report confirmed matches — do not hallucinate findings

## Step 4: Report

[Same report format as before — BLOCKERS/SHOULD-FIX/NICE-TO-HAVE tables]

## Execution Notes

- Run ALL lessons even if earlier ones find blockers
- Skip node_modules/, .venv/, dist/, build/, __pycache__/
- If no files match a lesson's language filter, skip it and note in summary
- Do not hallucinate findings. Only report what grep + read confirms.
- Report how many lesson files were loaded and how many were applicable
```

**Step 2: Commit**

```bash
git add agents/lesson-scanner.md
git commit -m "feat: rewrite lesson-scanner to read lessons dynamically"
```

### Task 13: Update lesson TEMPLATE.md to match new schema

**Files:**
- Modify: `docs/lessons/TEMPLATE.md`

**Step 1: Replace with new structured template**

Replace entire content with the structured YAML schema from the design doc. Include both the frontmatter section (id, title, severity, languages, category, pattern, fix, example) and the body sections (Observation, Insight, Lesson).

Keep it simpler than the current template — remove the PMI-heavy fields (sustain plan, ripple effects, corrective action table) that add friction for community contributors. Those belong in the FRAMEWORK.md for internal use, not in the community submission template.

**Step 2: Commit**

```bash
git add docs/lessons/TEMPLATE.md
git commit -m "refactor: simplify lesson template to structured YAML schema for community use"
```

## Batch 4: Submit-Lesson Command & Contributing Guide

### Task 14: Create /submit-lesson command

**Files:**
- Create: `commands/submit-lesson.md`

**Step 1: Write the command**

```markdown
---
description: "Submit a lesson learned from a bug you encountered — contributes back to the community"
argument-hint: "[description of the bug or anti-pattern]"
---

# Submit Lesson

Help the user capture a lesson learned and generate a PR against the toolkit repo.

## Process

1. **Understand the bug** — Ask what happened, what the expected behavior was, and what code was involved. If $ARGUMENTS is provided, use that as the starting description.

2. **Identify the pattern** — Determine:
   - Category: async-traps, resource-lifecycle, silent-failures, integration-boundaries, test-anti-patterns, performance
   - Severity: blocker (causes data loss/crashes), should-fix (causes subtle bugs), nice-to-have (code smell)
   - Languages: which languages this applies to

3. **Determine check type** — Is this pattern detectable by grep (syntactic) or does it need AI context (semantic)?
   - If syntactic: generate a grep -P regex and test it against the user's code to verify it catches the pattern
   - If semantic: write a clear description and example for the lesson-scanner agent

4. **Generate the lesson file** — Use the structured YAML frontmatter schema:
   - Auto-assign the next available ID (read existing lessons, find max ID, add 1)
   - Generate slug from title
   - Fill all frontmatter fields
   - Write Observation, Insight, and Lesson sections

5. **Save locally** — Write to `docs/lessons/NNNN-<slug>.md`

6. **Generate PR** — If the user wants to contribute back:
   - Fork the toolkit repo if needed
   - Create a branch: `lesson/NNNN-<slug>`
   - Commit the lesson file
   - Open a PR with title: `lesson: <title>` and body describing the anti-pattern

## Output

Show the user the generated lesson file and ask if they want to:
- Save locally only (for personal use)
- Submit as a PR to the toolkit repo (for community benefit)
```

**Step 2: Commit**

```bash
git add commands/submit-lesson.md
git commit -m "feat: add /submit-lesson command for community lesson contributions"
```

### Task 15: Create CONTRIBUTING.md

**Files:**
- Create: `docs/CONTRIBUTING.md`

**Step 1: Write contributing guide**

Cover:
- How to submit a lesson (use `/submit-lesson` command or manual PR)
- Lesson file format (link to TEMPLATE.md)
- Quality bar (must include a real example, regex must not produce false positives)
- Review process (maintainer tests the regex, verifies the anti-pattern is real)
- Categories and severity definitions
- How lessons become automated checks (syntactic → lesson-check.sh, semantic → lesson-scanner)

**Step 2: Commit**

```bash
git add docs/CONTRIBUTING.md
git commit -m "docs: add contributing guide for community lesson submissions"
```

## Batch 5: Cleanup & Documentation

### Task 16: Strip personal references from skills

**Files:**
- Scan and modify: all files in `skills/`

**Step 1: Search for personal references**

```bash
grep -rn 'ha-aria\|hub\.cache\|lesson #\|lesson-[0-9]\|~/\.\|/home/\|ARIA\|Preact' skills/
```

**Step 2: Replace or remove**

The grep results from the earlier scan show very few personal references in skills — mostly generic CLAUDE.md references which are fine (every project has a CLAUDE.md). If any ha-aria or project-specific references are found, replace with generic equivalents.

**Step 3: Add `version: 1.0.0` to all skill frontmatter**

For each SKILL.md, add `version: 1.0.0` to the YAML frontmatter if not already present.

**Step 4: Commit**

```bash
git add skills/
git commit -m "refactor: strip personal references from skills, add version to frontmatter"
```

### Task 17: Update CLAUDE.md for new structure

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update directory layout**

Replace the directory layout section to reflect:
- `.claude-plugin/` at root (new)
- `commands/` at root (moved from `.claude/commands/` + ralph-loop)
- `hooks/` at root (moved from `plugins/ralph-loop/hooks/`)
- `plugins/` removed
- `docs/lessons/` now contains numbered lesson files

**Step 2: Add community lesson section**

Add a section explaining the dynamic lesson system and `/submit-lesson` command.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for marketplace structure and community lessons"
```

### Task 18: Update README.md

**Files:**
- Modify: `README.md`

**Step 1: Update installation section**

Add marketplace installation:
```bash
# Self-hosted marketplace
/plugin marketplace add parthalon025/autonomous-coding-toolkit
/plugin install autonomous-coding-toolkit@autonomous-coding-toolkit

# Or clone directly
git clone https://github.com/parthalon025/autonomous-coding-toolkit.git ~/.claude/plugins/autonomous-coding-toolkit
```

**Step 2: Add community lessons section**

New section explaining:
- The toolkit improves with every user's lessons
- How to submit a lesson (`/submit-lesson` or manual PR)
- How lessons become automated checks
- Link to CONTRIBUTING.md

**Step 3: Add attribution**

Add acknowledgment section crediting superpowers plugin as the foundation for the core skill chain.

**Step 4: Update directory structure diagram**

Reflect the new top-level layout.

**Step 5: Commit**

```bash
git add README.md
git commit -m "docs: update README with marketplace install, community lessons, and attribution"
```

### Task 19: Update ARCHITECTURE.md

**Files:**
- Modify: `docs/ARCHITECTURE.md`

**Step 1: Add community lesson loop diagram**

Add a new section to the Feedback Loops area showing the community flow:
```
User hits bug → /submit-lesson → PR → merge →
  → lesson file in docs/lessons/
  → lesson-check.sh picks up syntactic pattern
  → lesson-scanner picks up semantic pattern
  → all users benefit on next scan
```

**Step 2: Update directory references**

Update any references to `.claude/commands/` or `plugins/ralph-loop/` to reflect new top-level locations.

**Step 3: Commit**

```bash
git add docs/ARCHITECTURE.md
git commit -m "docs: update architecture with community lesson loop and new directory layout"
```

## Batch 6: Integration Wiring & Verification

### Task 20: Verify all paths are consistent

**Step 1: Search for stale paths**

```bash
grep -rn '\.claude/commands\|plugins/ralph-loop' --include='*.md' --include='*.sh' --include='*.json' .
```

Any results are stale references that need updating.

**Step 2: Verify hooks.json path works from plugin root**

Read `hooks/hooks.json` and verify the stop-hook.sh path resolves correctly when the plugin root is the repo root.

**Step 3: Verify lesson-check.sh finds lessons**

```bash
scripts/lesson-check.sh --help
```

Should list dynamically loaded lessons instead of hardcoded checks.

**Step 4: Run test suite**

```bash
bash scripts/tests/run-all-tests.sh
```

Fix any failures.

**Step 5: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve stale path references after restructure"
```

### Task 21: Final push

**Step 1: Push all commits**

```bash
git push origin main
```

## Quality Gates

Between each batch, verify:
1. `git status` — working tree clean
2. `git log --oneline -5` — commits look right
3. No stale references to old paths

## Summary

| Batch | Tasks | What it does |
|-------|-------|-------------|
| 1 | 1-4 | Plugin manifests + directory restructure |
| 2 | 5-10 | Create 6 starter lesson files |
| 3 | 11-13 | Dynamic lesson-check.sh + lesson-scanner + template |
| 4 | 14-15 | /submit-lesson command + CONTRIBUTING.md |
| 5 | 16-19 | Strip personal refs, update all docs |
| 6 | 20-21 | Integration wiring, verify paths, push |
