# Validator Suite Design

**Date:** 2026-02-21
**Status:** Approved
**Goal:** Self-validate all toolkit artifacts — lessons, skills, commands, plans, PRDs, plugin metadata, and hooks — with CI and Makefile integration.

## Problem

The toolkit enforces quality gates on consumer projects but has none on its own artifacts. Broken YAML frontmatter in lesson files silently drops checks (0056/0057 bug). Skill/command files with bad frontmatter won't load in Claude Code. No CI runs the existing 27 bash tests.

## Architecture

**Approach:** Modular validators + orchestrator. Individual `validate-*.sh` scripts per artifact type, plus `validate-all.sh` that runs them all. Mirrors existing pattern where `quality-gate.sh` orchestrates `lesson-check.sh` + tests.

## Validator Contract

Every validator follows the same interface:

- **Exit 0** = clean, **exit 1** = violations found
- `--warn` flag: print violations but exit 0
- `--help` for usage
- Output format: `validate-X: PASS` or `validate-X: FAIL (N issues)`
- Individual issues: `file:line: description` (same as `lesson-check.sh`)
- Sources `lib/common.sh` for shared utilities

## Validators

### validate-lessons.sh

Checks all `docs/lessons/[0-9]*.md` files:
- First line is `---` (not wrapped in code blocks)
- Required fields present: `id`, `title`, `severity`, `languages`, `pattern.type`
- Syntactic lessons (`pattern.type: syntactic`) have `regex` field
- IDs are sequential with no gaps or duplicates
- Severity is one of: `blocker`, `should-fix`, `nice-to-have`
- Languages are valid: `python`, `javascript`, `typescript`, `shell`, `all`

### validate-skills.sh

Checks all `skills/*/SKILL.md` files:
- YAML frontmatter has `name` and `description`
- `name` field matches the parent directory name
- Any `.md` files referenced in SKILL.md content exist in the same directory

### validate-commands.sh

Checks all `commands/*.md` files:
- YAML frontmatter has `description`
- Frontmatter delimiters (`---`) present

### validate-plans.sh

Validates plan markdown files (passed as argument or `docs/plans/*.md`):
- At least one `## Batch N:` header
- Each batch has at least one `### Task` header
- Batch numbers are sequential starting from 1
- No empty batches (header with no tasks)

### validate-prd.sh

Validates PRD JSON files (passed as argument or `tasks/prd.json`):
- Valid JSON array
- Each task has `id`, `title`, `acceptance_criteria`
- `acceptance_criteria` is a non-empty array of strings
- `blocked_by` references only valid task IDs within the file
- No circular dependencies in `blocked_by` graph

### validate-plugin.sh

Checks `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`:
- Both files are valid JSON
- `name` field matches between them
- `version` field matches between them
- `source` path in marketplace.json exists

### validate-hooks.sh

Checks `hooks/hooks.json`:
- Valid JSON
- Referenced command scripts exist
- Referenced scripts are executable

### validate-all.sh

Orchestrator that runs all validators:
- Runs each validator, captures exit code
- Aggregates results into summary table
- Exits 1 if any validator failed
- Supports `--warn` (passes through to each validator)

## Makefile

```makefile
.PHONY: test validate ci

test:
	bash scripts/tests/run-all-tests.sh

validate:
	bash scripts/validate-all.sh

ci: validate test
```

## GitHub Actions CI

`.github/workflows/ci.yml`:
- Triggers: push to main, pull requests
- Runner: ubuntu-latest
- Dependencies: jq (apt-get)
- Steps: checkout, install jq, `make ci`
- No claude CLI needed — existing tests mock external commands

## Integration with quality-gate.sh

Add `validate-all.sh` as step 0 in quality-gate.sh, before lesson-check and tests. This means toolkit development gets self-validation on every quality gate run.

## Test Files

Each validator gets a `scripts/tests/test-validate-*.sh` following existing patterns:
- `assert_eq`/`assert_exit` helpers (from test-common.sh pattern)
- Temp directory fixtures with `trap cleanup EXIT`
- Test both valid and invalid inputs
- No external dependencies

## File Summary

New files:
- `scripts/validate-lessons.sh`
- `scripts/validate-skills.sh`
- `scripts/validate-commands.sh`
- `scripts/validate-plans.sh`
- `scripts/validate-prd.sh`
- `scripts/validate-plugin.sh`
- `scripts/validate-hooks.sh`
- `scripts/validate-all.sh`
- `scripts/tests/test-validate-lessons.sh`
- `scripts/tests/test-validate-skills.sh`
- `scripts/tests/test-validate-commands.sh`
- `scripts/tests/test-validate-plans.sh`
- `scripts/tests/test-validate-prd.sh`
- `scripts/tests/test-validate-plugin.sh`
- `scripts/tests/test-validate-hooks.sh`
- `Makefile`
- `.github/workflows/ci.yml`

Modified files:
- `scripts/quality-gate.sh` — add validate-all.sh step
