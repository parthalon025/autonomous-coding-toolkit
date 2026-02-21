# Hardening Pass Audit Findings

> Generated: 2026-02-21 | Batches 1-2 of hardening pass

---

## Shellcheck Findings

### Notes (SC1091 — source not followed)

These are informational — shellcheck can't follow relative `source` paths without `-x` flag. Not actionable.

| File | Line | Code | Description | Disposition |
|------|------|------|-------------|-------------|
| `scripts/run-plan.sh` | 17 | SC1091 | Not following: `./lib/run-plan-parser.sh` | SUPPRESS — relative source, use `-x` flag |
| `scripts/run-plan.sh` | 18 | SC1091 | Not following: `./lib/run-plan-state.sh` | SUPPRESS — same |
| `scripts/run-plan.sh` | 19 | SC1091 | Not following: `./lib/run-plan-quality-gate.sh` | SUPPRESS — same |
| `scripts/run-plan.sh` | 20 | SC1091 | Not following: `./lib/run-plan-notify.sh` | SUPPRESS — same |
| `scripts/run-plan.sh` | 21 | SC1091 | Not following: `./lib/run-plan-prompt.sh` | SUPPRESS — same |

### Warnings

| File | Line | Code | Description | Disposition |
|------|------|------|-------------|-------------|
| `scripts/run-plan.sh` | 111 | SC2034 | `COMPETITIVE_BATCHES` appears unused | SUPPRESS — used by sourced lib modules |
| `scripts/run-plan.sh` | 123 | SC2034 | `MAX_BUDGET` appears unused | SUPPRESS — used by sourced lib modules |
| `scripts/run-plan.sh` | 305 | SC1007 | Remove space after `=` in `CLAUDECODE= claude` | SUPPRESS — intentional: unsetting env var for subcommand |
| `scripts/lesson-check.sh` | 20 | SC2034 | `lesson_severity` appears unused | FIX — either use it or remove from parse output |
| `scripts/entropy-audit.sh` | 28 | SC2034 | `FIX_MODE` appears unused | FIX — parsed but never checked; add `--fix` implementation or remove |
| `scripts/lib/run-plan-quality-gate.sh` | 65 | SC2034 | `passed` appears unused | FIX — declared but never read |

### Info/Style

| File | Line | Code | Description | Disposition |
|------|------|------|-------------|-------------|
| `scripts/setup-ralph-loop.sh` | 112 | SC2086 | Double quote to prevent globbing/word splitting: `$MAX_ITERATIONS` | FIX — quote variable |
| `scripts/auto-compound.sh` | 73 | SC2012 | Use `find` instead of `ls` for non-alphanumeric filenames | FIX — replace `ls -t` with `find`+`sort` |
| `scripts/entropy-audit.sh` | 73 | SC2016 | Expressions don't expand in single quotes | SUPPRESS — intentional: regex pattern uses literal `$` |
| `scripts/entropy-audit.sh` | 201 | SC2016 | Expressions don't expand in single quotes | SUPPRESS — same, grep pattern with literal backticks |
| `scripts/entropy-audit.sh` | 214 | SC2012 | Use `find` instead of `ls` | FIX — replace `ls` with `find` |
| `scripts/lib/run-plan-parser.sh` | 32 | SC2295 | Expansions inside `${..}` need separate quoting | FIX — quote inner expansion |
| `hooks/stop-hook.sh` | 78 | SC2181 | Check exit code directly instead of `$?` | FIX — restructure to `if ! cmd; then` |

---

## Summary

| Severity | Total | FIX | SUPPRESS |
|----------|-------|-----|----------|
| Note (SC1091 source) | 5 | 0 | 5 |
| Warning | 6 | 3 | 3 |
| Info/Style | 7 | 5 | 2 |
| **Total** | **18** | **8** | **10** |

---

## Lesson Scanner Results

### lesson-check.sh against shell scripts

```
Target: scripts/*.sh, scripts/lib/*.sh, hooks/stop-hook.sh (15 files)
Result: lesson-check: clean
Exit code: 0
```

All shell scripts pass — expected since lessons target Python/JS patterns.

### lesson-check.sh against Python/JS/TS files

```
Target: find . -name "*.py" -o -name "*.js" -o -name "*.ts"
Result: No matching files found
```

This is a pure bash toolkit — no Python/JS/TS source files exist. Lesson scanner has no applicable targets.

### Conclusion

No lesson violations found. The toolkit's bash-only codebase is not covered by the current syntactic lesson set (which targets Python/JS). Future work: add bash-specific lessons (e.g., unquoted variables, missing `set -euo pipefail`).

---

## Lesson File Schema Validation (Batch 2)

### Method

Validated all 6 lesson files (`docs/lessons/0001-*.md` through `0006-*.md`) against the schema defined in `docs/lessons/TEMPLATE.md`.

**Required fields checked:**
- `id` (integer), `title` (non-empty), `severity` (blocker|should-fix|nice-to-have)
- `languages` (array or `all`), `category` (enum of 6 values)
- `pattern.type` (syntactic|semantic), `pattern.regex` (required if syntactic), `pattern.description`
- `fix` (non-empty), `example.bad` (non-empty), `example.good` (non-empty)

### Schema Results

| File | id | severity | category | pattern.type | regex | All fields | Status |
|------|----|----------|----------|-------------|-------|------------|--------|
| `0001-bare-exception-swallowing.md` | 1 | blocker | silent-failures | syntactic | `^\s*except\s*:` | ✓ | PASS |
| `0002-async-def-without-await.md` | 2 | blocker | async-traps | semantic | N/A | ✓ | PASS |
| `0003-create-task-without-callback.md` | 3 | should-fix | silent-failures | semantic | N/A | ✓ | PASS |
| `0004-hardcoded-test-counts.md` | 4 | should-fix | test-anti-patterns | syntactic | `assert.*==\s*\d+\|...` | ✓ | PASS |
| `0005-sqlite-without-closing.md` | 5 | should-fix | silent-failures | syntactic | `sqlite3\.connect\(` | ✓ | PASS |
| `0006-venv-pip-path.md` | 6 | should-fix | integration-boundaries | syntactic | `\.venv/bin/pip\b` | ✓ | PASS |

**6/6 lesson files pass schema validation.** All required fields present, all enum values valid.

### Regex Compilation Results

Tested all 4 syntactic lesson regex patterns with `grep -P`:

| Lesson | Regex | Compiles | Status |
|--------|-------|----------|--------|
| 0001 | `^\s*except\s*:` | ✓ | PASS |
| 0004 | `assert.*==\s*\d+\|expect\(.*\)\.toBe\(\d+\)\|assert_equal.*\d+` | ✓ | PASS |
| 0005 | `sqlite3\.connect\(` | ✓ | PASS |
| 0006 | `\.venv/bin/pip\b` | ✓ | PASS |

**4/4 syntactic regex patterns compile successfully** (grep -P exit code 0 or 1).

### Observations

- All lessons use valid enum values for `severity` and `category`
- Semantic lessons (0002, 0003) correctly omit `regex` field
- ID sequence is contiguous (1-6) with no gaps
- No issues found — lesson schema is clean

---

## Manifest & Frontmatter Validation (Batch 2)

### JSON Manifest Validation

| File | Valid JSON | Required Fields | Status |
|------|-----------|----------------|--------|
| `.claude-plugin/plugin.json` | ✓ | name, description, version, author | PASS |
| `.claude-plugin/marketplace.json` | ✓ | N/A (list format) | PASS |
| `hooks/hooks.json` | ✓ | N/A (event-keyed) | PASS |

**3/3 JSON files pass validation.**

### Skill Frontmatter Validation

Checked all 15 skills for required fields: `name`, `description`, `version`.

| Skill | name | description | version | Status |
|-------|------|-------------|---------|--------|
| `brainstorming` | ✓ | ✓ | 1.0.0 | PASS |
| `dispatching-parallel-agents` | ✓ | ✓ | 1.0.0 | PASS |
| `executing-plans` | ✓ | ✓ | 1.0.0 | PASS |
| `finishing-a-development-branch` | ✓ | ✓ | 1.0.0 | PASS |
| `receiving-code-review` | ✓ | ✓ | 1.0.0 | PASS |
| `requesting-code-review` | ✓ | ✓ | 1.0.0 | PASS |
| `subagent-driven-development` | ✓ | ✓ | 1.0.0 | PASS |
| `systematic-debugging` | ✓ | ✓ | 1.0.0 | PASS |
| `test-driven-development` | ✓ | ✓ | 1.0.0 | PASS |
| `using-git-worktrees` | ✓ | ✓ | 1.0.0 | PASS |
| `using-superpowers` | ✓ | ✓ | 1.0.0 | PASS |
| `verification-before-completion` | ✓ | ✓ | 1.0.0 | PASS |
| `verify` | ✓ | ✓ | 1.0.0 | PASS |
| `writing-plans` | ✓ | ✓ | 1.0.0 | PASS |
| `writing-skills` | ✓ | ✓ | 1.0.0 | PASS |

**15/15 skills pass frontmatter validation.**

### Command Frontmatter Validation

Checked all 6 commands for YAML frontmatter with `description` field (command name derives from filename).

| Command | Frontmatter | description | Status |
|---------|-------------|-------------|--------|
| `cancel-ralph.md` | ✓ | ✓ | PASS |
| `code-factory.md` | ✓ | ✓ | PASS |
| `create-prd.md` | ✓ | ✓ | PASS |
| `ralph-loop.md` | ✓ | ✓ | PASS |
| `run-plan.md` | ✓ | ✓ | PASS |
| `submit-lesson.md` | ✓ | ✓ | PASS |

**6/6 commands pass frontmatter validation.**

### Observations

- All skills at version 1.0.0 — consistent versioning
- Command files use `description` (not `name`) in frontmatter — name comes from filename per Claude Code convention
- No missing or malformed frontmatter found across any file type
