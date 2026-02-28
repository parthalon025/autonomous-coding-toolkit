# Full-Coverage Hardening Pass Design

**Date:** 2026-02-21
**Status:** Approved
**Approach:** Audit-Then-Test with A/B competitive agents on critical batches

## Goal

Verify all code in the autonomous-coding-toolkit is correct, well-tested, and production-ready after the marketplace restructure. Close all test coverage gaps identified in the gap analysis.

## Current State

- 109 tests pass across 7 test files (all for run-plan.sh and its lib modules)
- 933 LOC of tests covering ~3,000 LOC of code
- Critical gaps: lesson-check.sh parser, stop-hook.sh, lesson file validation, quality-gate.sh orchestration
- Medium gaps: setup-ralph-loop.sh, batch-test.sh, entropy-audit.sh
- Low gaps: command files, skill frontmatters, plugin manifests

## Architecture

Two phases — Audit (discover issues) then Test + Fix (prove correctness). 8 batches. Competitive A/B agents on batches 5 and 6.

## Phase 1: Audit (Batches 1-3)

### Batch 1: Static Analysis
- Run shellcheck against all .sh scripts (9 main + 5 lib + stop-hook.sh)
- Run lesson-scanner agent against the toolkit's own codebase
- Catalog findings into audit-findings.md

### Batch 2: Schema Validation
- Validate 6 lesson files: required YAML fields, regex validity (grep -P compatible), severity/category enums, language list format
- Validate plugin.json (name, version, author, keywords)
- Validate marketplace.json ($schema, plugins array)
- Validate hooks.json structure
- Validate 15 skill YAML frontmatters (name, description, version)
- Validate 6 command files (frontmatter, required sections)

### Batch 3: Integration Smoke Tests
- Create test fixtures with known anti-patterns, run lesson-check.sh, verify detection
- Run quality-gate.sh against mock project directory
- Run setup-ralph-loop.sh with various args, verify state file
- Test stop-hook.sh with mock state files, verify JSON output

## Phase 2: Fix (Batch 4)

### Batch 4: Fix All Audit Findings
- Fix shellcheck issues (or add justified suppressions)
- Fix schema issues in lesson files, manifests, skill frontmatters
- Fix bugs discovered during smoke tests

## Phase 3: Tests (Batches 5-8)

### Batch 5: lesson-check.sh Tests (A/B Competitive)
- test-lesson-check.sh:
  - parse_lesson() unit tests (valid YAML, malformed, missing fields, empty regex, semantic vs syntactic)
  - Regex matching tests (each lesson's regex against known good/bad fixtures)
  - Language filter tests (Python-only lessons skip .sh files)
  - Exit code tests (clean=0, violations=1)
  - --help output validation
  - Edge cases: empty file list, nonexistent files, stdin pipe mode

### Batch 6: stop-hook.sh + setup-ralph-loop.sh Tests (A/B Competitive)
- test-stop-hook.sh:
  - State file parsing (valid YAML, malformed, missing fields)
  - Completion promise detection (present, absent, partial match)
  - Iteration increment (1→2, at max)
  - Max iteration enforcement
  - JSON output format validation
- test-setup-ralph-loop.sh:
  - State file generation (YAML frontmatter format)
  - Argument parsing (--max-iterations, --completion-promise, prompt parts)
  - Error cases (no prompt, invalid --max-iterations)

### Batch 7: quality-gate.sh + Utility Script Tests
- test-quality-gate.sh (orchestration):
  - Test runner auto-detection (Makefile, package.json, pytest.ini)
  - Lesson check integration
  - Memory advisory (mock free output)
  - Exit code propagation
- test-batch-test.sh:
  - Memory fallback logic

### Batch 8: Low-Risk Validation Tests
- test-lesson-schema.sh: All lesson files match schema (reusable for CI)
- test-skill-frontmatter.sh: All 15 skills have valid frontmatter
- test-command-structure.sh: All 6 commands have required frontmatter
- test-plugin-manifests.sh: plugin.json + marketplace.json valid

## Competitive Batch Strategy

Batches 5 and 6: Mode B (Competitive Dual-Track)
- Two agents write tests independently in separate worktrees
- Judge compares: test count, edge case coverage, readability
- Winner's tests cherry-picked into main

All other batches: Mode C (headless) or Mode A (team)

## Success Criteria

| Metric | Target |
|--------|--------|
| Shellcheck | 0 errors/warnings (or justified suppressions) |
| Existing tests | 109/109 still pass |
| New tests | 60+ (target 170+ total) |
| lesson-check.sh | Dedicated test file, 15+ assertions |
| stop-hook.sh | Dedicated test file, 12+ assertions |
| Lesson schema | All 6 validate, reusable validator |
| Plugin manifests | Valid JSON with required fields |
