# Validator Suite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build self-validation runners for all toolkit artifacts (lessons, skills, commands, plans, PRDs, plugin metadata, hooks), wire them into CI and a Makefile.

**Architecture:** Modular bash validators following the same contract (exit 0/1, `--warn`, `--help`), orchestrated by `validate-all.sh`, integrated into `quality-gate.sh` and GitHub Actions.

**Tech Stack:** Bash, jq, sed. No external dependencies beyond what the toolkit already uses.

**Design:** `docs/plans/2026-02-21-validator-suite-design.md`

## Quality Gates

Between each batch, run:
```bash
bash scripts/tests/run-all-tests.sh
```

---

## Batch 1: Test Helpers and validate-lessons.sh

### Task 1: Create shared test helpers

**Files:**
- Create: `scripts/tests/test-helpers.sh`

Create a sourceable helper file with `assert_eq`, `assert_exit`, `assert_contains` (extracted from the pattern in test-quality-gate.sh). Every new test file will source this instead of duplicating the helpers.

```bash
#!/usr/bin/env bash
# test-helpers.sh — Shared test assertions for validator tests
# Source this file, don't execute it directly.

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_exit() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    "$@" >/dev/null 2>&1 || actual_exit=$?
    TESTS=$((TESTS + 1))
    if [[ "$expected_exit" != "$actual_exit" ]]; then
        echo "FAIL: $desc"
        echo "  expected exit: $expected_exit"
        echo "  actual exit:   $actual_exit"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if echo "$haystack" | grep -qF "$needle"; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  in: $(echo "$haystack" | head -5)"
        FAILURES=$((FAILURES + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if echo "$haystack" | grep -qF "$needle"; then
        echo "FAIL: $desc"
        echo "  should NOT contain: $needle"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

# Call at end of test file
report_results() {
    echo ""
    echo "Results: $((TESTS - FAILURES))/$TESTS passed"
    if [[ $FAILURES -gt 0 ]]; then
        echo "FAILURES: $FAILURES"
        exit 1
    fi
    echo "ALL PASSED"
}
```

### Task 2: Write validate-lessons.sh

**Files:**
- Create: `scripts/validate-lessons.sh`

```bash
#!/usr/bin/env bash
# validate-lessons.sh — Validate lesson file format and frontmatter
# Exit 0 if clean, exit 1 if violations found. Use --warn to print but exit 0.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LESSONS_DIR="$SCRIPT_DIR/../docs/lessons"
WARN_ONLY=false
violations=0

usage() {
    echo "Usage: validate-lessons.sh [--warn] [--help]"
    echo "  Validates all lesson files in docs/lessons/"
    echo "  --warn   Print violations but exit 0"
    exit 0
}

report_violation() {
    local file="$1" line="$2" msg="$3"
    echo "${file}:${line}: ${msg}"
    ((violations++)) || true
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && usage
[[ "${1:-}" == "--warn" ]] && WARN_ONLY=true

if [[ ! -d "$LESSONS_DIR" ]]; then
    echo "validate-lessons: lessons directory not found: $LESSONS_DIR" >&2
    exit 1
fi

seen_ids=()

for lesson in "$LESSONS_DIR"/[0-9]*.md; do
    [[ -f "$lesson" ]] || continue
    fname="$(basename "$lesson")"

    # Check 1: First line must be ---
    first_line=$(head -1 "$lesson")
    if [[ "$first_line" != "---" ]]; then
        report_violation "$fname" 1 "First line must be '---', got '$first_line' (code block wrapping?)"
        continue  # Can't parse frontmatter if start is wrong
    fi

    # Extract frontmatter (between first two --- lines)
    frontmatter=$(sed -n '2,/^---$/{ /^---$/d; p; }' "$lesson")

    # Check 2: Required fields
    for field in id title severity languages; do
        if ! echo "$frontmatter" | grep -q "^${field}:"; then
            report_violation "$fname" 0 "Missing required field: $field"
        fi
    done

    # Check 3: pattern.type must exist
    if ! echo "$frontmatter" | grep -q "type:"; then
        report_violation "$fname" 0 "Missing pattern.type field"
    fi

    # Check 4: Extract and validate ID
    lesson_id=$(echo "$frontmatter" | sed -n 's/^id:[[:space:]]*\(.*\)/\1/p' | tr -d ' "'"'"'')
    if [[ -n "$lesson_id" ]]; then
        # Check for duplicate IDs
        for seen in "${seen_ids[@]+"${seen_ids[@]}"}"; do
            if [[ "$seen" == "$lesson_id" ]]; then
                report_violation "$fname" 0 "Duplicate lesson ID: $lesson_id"
            fi
        done
        seen_ids+=("$lesson_id")
    fi

    # Check 5: Severity must be valid
    severity=$(echo "$frontmatter" | sed -n 's/^severity:[[:space:]]*\(.*\)/\1/p' | tr -d ' ')
    if [[ -n "$severity" ]]; then
        case "$severity" in
            blocker|should-fix|nice-to-have) ;;
            *) report_violation "$fname" 0 "Invalid severity '$severity' (must be blocker|should-fix|nice-to-have)" ;;
        esac
    fi

    # Check 6: Syntactic lessons must have regex
    pattern_type=$(echo "$frontmatter" | grep "type:" | tail -1 | sed 's/.*type:[[:space:]]*//' | tr -d ' ')
    if [[ "$pattern_type" == "syntactic" ]]; then
        if ! echo "$frontmatter" | grep -q "regex:"; then
            report_violation "$fname" 0 "Syntactic lesson missing regex field"
        fi
    fi
done

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "validate-lessons: FAIL ($violations issues)"
    [[ "$WARN_ONLY" == true ]] && exit 0
    exit 1
else
    echo "validate-lessons: PASS"
    exit 0
fi
```

Make executable: `chmod +x scripts/validate-lessons.sh`

### Task 3: Write test-validate-lessons.sh

**Files:**
- Create: `scripts/tests/test-validate-lessons.sh`

Test with fixture lesson files in a temp directory. Override `LESSONS_DIR` approach: the validator uses `$SCRIPT_DIR/../docs/lessons` so we'll test by creating a temp toolkit structure. Tests:
- Valid lesson passes
- Missing `---` start line fails
- Missing required field fails
- Duplicate IDs fail
- Invalid severity fails
- Syntactic without regex fails
- `--warn` exits 0 even with violations
- `--help` exits 0

The test should create a minimal temp directory mimicking the toolkit structure, symlink the validator script, and set up fixture lesson files.

### Task 4: Run tests, commit Batch 1

Run: `bash scripts/tests/test-validate-lessons.sh`
Expected: ALL PASSED

Commit:
```bash
git add scripts/validate-lessons.sh scripts/tests/test-helpers.sh scripts/tests/test-validate-lessons.sh
git commit -m "feat: add validate-lessons.sh with test helpers and tests"
```

---

## Batch 2: validate-skills.sh and validate-commands.sh

### Task 5: Write validate-skills.sh

**Files:**
- Create: `scripts/validate-skills.sh`

Check all `skills/*/SKILL.md` files:
- Frontmatter starts with `---`
- Has `name` and `description` fields
- `name` field matches directory name
- Any `.md` files referenced in SKILL.md body exist in same directory (use grep for `[filename].md` patterns)

Same contract: exit 0/1, `--warn`, `--help`. Make executable.

### Task 6: Write validate-commands.sh

**Files:**
- Create: `scripts/validate-commands.sh`

Check all `commands/*.md` files:
- Frontmatter starts with `---`
- Has `description` field
- Second `---` delimiter exists (frontmatter is closed)

Same contract. Make executable.

### Task 7: Write test-validate-skills.sh

**Files:**
- Create: `scripts/tests/test-validate-skills.sh`

Source `test-helpers.sh`. Create temp skill directories with valid/invalid SKILL.md files. Test:
- Valid skill passes
- Missing name fails
- Name mismatch with directory fails
- `--warn` exits 0

### Task 8: Write test-validate-commands.sh

**Files:**
- Create: `scripts/tests/test-validate-commands.sh`

Source `test-helpers.sh`. Create temp command files. Test:
- Valid command passes
- Missing description fails
- Missing frontmatter fails
- `--warn` exits 0

### Task 9: Run tests, commit Batch 2

Run: `bash scripts/tests/test-validate-skills.sh && bash scripts/tests/test-validate-commands.sh`
Expected: ALL PASSED

Commit:
```bash
git add scripts/validate-skills.sh scripts/validate-commands.sh scripts/tests/test-validate-skills.sh scripts/tests/test-validate-commands.sh
git commit -m "feat: add validate-skills.sh and validate-commands.sh with tests"
```

---

## Batch 3: validate-plans.sh and validate-prd.sh

### Task 10: Write validate-plans.sh

**Files:**
- Create: `scripts/validate-plans.sh`

Accepts plan file as argument or defaults to `docs/plans/*.md` (skip design docs — only validate files with `## Batch` headers).

Checks:
- At least one `## Batch N:` header found
- Each batch has at least one `### Task` header
- Batch numbers are sequential starting from 1

Same contract. Make executable.

### Task 11: Write validate-prd.sh

**Files:**
- Create: `scripts/validate-prd.sh`

Accepts PRD JSON file as argument or defaults to `tasks/prd.json`. Requires `jq`.

Checks:
- Valid JSON (jq parses without error)
- Is a JSON array
- Each element has `id` (number), `title` (string), `acceptance_criteria` (non-empty array)
- `blocked_by` references only IDs that exist in the file
- No circular dependencies (simple: check if any task blocks itself)

Same contract. Make executable.

### Task 12: Write test-validate-plans.sh and test-validate-prd.sh

**Files:**
- Create: `scripts/tests/test-validate-plans.sh`
- Create: `scripts/tests/test-validate-prd.sh`

Plan tests: valid plan passes, no batches fails, empty batch fails, non-sequential fails.
PRD tests: valid PRD passes, invalid JSON fails, missing fields fail, bad blocked_by fails.

### Task 13: Run tests, commit Batch 3

Run: `bash scripts/tests/test-validate-plans.sh && bash scripts/tests/test-validate-prd.sh`
Expected: ALL PASSED

Commit:
```bash
git add scripts/validate-plans.sh scripts/validate-prd.sh scripts/tests/test-validate-plans.sh scripts/tests/test-validate-prd.sh
git commit -m "feat: add validate-plans.sh and validate-prd.sh with tests"
```

---

## Batch 4: validate-plugin.sh, validate-hooks.sh, and validate-all.sh

### Task 14: Write validate-plugin.sh

**Files:**
- Create: `scripts/validate-plugin.sh`

Checks `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`:
- Both files exist and are valid JSON
- `name` field matches between them
- `version` field matches between them

Same contract. Make executable.

### Task 15: Write validate-hooks.sh

**Files:**
- Create: `scripts/validate-hooks.sh`

Checks `hooks/hooks.json`:
- Valid JSON
- Each referenced command script path exists (resolve `${CLAUDE_PLUGIN_ROOT}` to toolkit root)
- Referenced scripts are executable

Same contract. Make executable.

### Task 16: Write validate-all.sh

**Files:**
- Create: `scripts/validate-all.sh`

Orchestrator that runs: validate-lessons, validate-skills, validate-commands, validate-plugin, validate-hooks. (validate-plans and validate-prd are on-demand — they need file arguments, not repo-level.)

For each validator:
- Run it, capture exit code
- Print PASS/FAIL per validator
- Print summary: N/M validators passed
- Exit 1 if any failed
- Pass `--warn` through to all validators if provided

Make executable.

### Task 17: Write tests for plugin, hooks, and validate-all

**Files:**
- Create: `scripts/tests/test-validate-plugin.sh`
- Create: `scripts/tests/test-validate-hooks.sh`
- Create: `scripts/tests/test-validate-all.sh`

Plugin tests: matching versions pass, mismatched versions fail, missing file fails.
Hooks tests: valid hooks.json passes, nonexistent script fails, non-executable script fails.
Validate-all tests: runs on actual toolkit (should pass), `--warn` flag passes through.

### Task 18: Run tests, commit Batch 4

Run: `bash scripts/tests/test-validate-plugin.sh && bash scripts/tests/test-validate-hooks.sh && bash scripts/tests/test-validate-all.sh`
Expected: ALL PASSED

Commit:
```bash
git add scripts/validate-plugin.sh scripts/validate-hooks.sh scripts/validate-all.sh scripts/tests/test-validate-plugin.sh scripts/tests/test-validate-hooks.sh scripts/tests/test-validate-all.sh
git commit -m "feat: add validate-plugin, validate-hooks, validate-all with tests"
```

---

## Batch 5: Makefile, CI, and quality-gate.sh Integration

### Task 19: Create Makefile

**Files:**
- Create: `Makefile`

```makefile
.PHONY: test validate ci

test:
	@bash scripts/tests/run-all-tests.sh

validate:
	@bash scripts/validate-all.sh

ci: validate test
	@echo "CI: ALL PASSED"
```

### Task 20: Create GitHub Actions CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install jq
        run: sudo apt-get install -y jq
      - name: Run CI
        run: make ci
```

### Task 21: Add validate-all.sh to quality-gate.sh

**Files:**
- Modify: `scripts/quality-gate.sh`

Add a new check section between the existing header and Check 1 (Lesson Check):

```bash
# === Check 0: Toolkit Self-Validation ===
# Only runs when quality-gate is invoked from the toolkit itself
if [[ -f "$PROJECT_ROOT/scripts/validate-all.sh" ]]; then
    echo "=== Quality Gate: Toolkit Validation ==="
    if ! bash "$PROJECT_ROOT/scripts/validate-all.sh"; then
        echo ""
        echo "quality-gate: FAILED at toolkit validation"
        exit 1
    fi
fi
```

### Task 22: Run full CI, commit Batch 5

Run: `make ci`
Expected: ALL PASSED (both validate and test)

Also run: `bash scripts/validate-all.sh` on the actual toolkit to verify it passes against all real artifacts.

Commit:
```bash
git add Makefile .github/workflows/ci.yml scripts/quality-gate.sh
git commit -m "feat: add Makefile, GitHub Actions CI, wire validators into quality-gate"
```

---

## Batch 6: Integration Wiring and Final Verification

### Task 23: Run validate-all.sh against actual toolkit artifacts

Run every validator individually against the real toolkit to confirm they all pass:
```bash
bash scripts/validate-lessons.sh
bash scripts/validate-skills.sh
bash scripts/validate-commands.sh
bash scripts/validate-plugin.sh
bash scripts/validate-hooks.sh
bash scripts/validate-all.sh
```

Fix any real violations discovered (e.g., skills with name mismatches, commands missing fields).

### Task 24: Run full test suite

Run the complete test suite to verify no regressions:
```bash
bash scripts/tests/run-all-tests.sh
```

Expected: ALL test files pass, including all new test-validate-*.sh files.

### Task 25: Run make ci end-to-end

Run: `make ci`
Expected: validate passes, then tests pass, then "CI: ALL PASSED"

### Task 26: Final commit if any fixes needed

If Task 23 found real violations that needed fixing, commit those fixes:
```bash
git add -A
git commit -m "fix: resolve validator findings in toolkit artifacts"
```
