# Full-Coverage Hardening Pass Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Audit all code for quality issues, fix findings, and add comprehensive tests to close every coverage gap in the toolkit.

**Architecture:** Two-phase approach — Phase 1 audits with shellcheck + schema validation + smoke tests, Phase 2 writes permanent test suites. Test files follow the existing bash framework (`assert_exit`/`assert_output_contains` helpers). The test runner at `scripts/tests/run-all-tests.sh` discovers files matching `test-*.sh` glob.

**Tech Stack:** bash, shellcheck 0.9.0, grep -P (PCRE), jq, awk

**Quality Gates:** `bash scripts/tests/run-all-tests.sh` — must maintain 109+ existing tests passing and add 60+ new tests.

---

## Batch 1: Static Analysis — Shellcheck + Lesson Scanner

### Task 1: Run shellcheck against all scripts and catalog findings

**Files:**
- Read: `scripts/*.sh`, `scripts/lib/*.sh`, `hooks/stop-hook.sh`
- Create: `docs/plans/audit-findings.md`

**Step 1: Run shellcheck against all scripts**

```bash
shellcheck -s bash -f gcc scripts/run-plan.sh scripts/lesson-check.sh scripts/quality-gate.sh scripts/setup-ralph-loop.sh scripts/auto-compound.sh scripts/entropy-audit.sh scripts/batch-audit.sh scripts/batch-test.sh scripts/lib/*.sh hooks/stop-hook.sh 2>&1 | tee /tmp/shellcheck-findings.txt
echo "Exit code: $?"
```

Expected: Some warnings (SC2086 word splitting, SC2155 declare/assign, etc.)

**Step 2: Catalog all findings**

Create `docs/plans/audit-findings.md` with:
- Each finding: file:line, shellcheck code, severity, description
- Group by severity (error, warning, info)
- For each finding, add a disposition: FIX or SUPPRESS (with justification)

**Step 3: Commit findings**

```bash
git add docs/plans/audit-findings.md
git commit -m "docs: add shellcheck audit findings"
```

### Task 2: Run lesson-scanner agent against toolkit's own codebase

**Files:**
- Read: `docs/lessons/*.md` (lesson definitions)
- Modify: `docs/plans/audit-findings.md` (append lesson scanner results)

**Step 1: Run lesson-check.sh against all shell scripts**

```bash
scripts/lesson-check.sh scripts/*.sh scripts/lib/*.sh hooks/stop-hook.sh
```

Expected: Clean (these are bash, lessons target python/js). Record result.

**Step 2: Run lesson-check.sh against any Python/JS in examples**

```bash
find . -name "*.py" -o -name "*.js" -o -name "*.ts" | grep -v node_modules | grep -v .venv | xargs scripts/lesson-check.sh 2>/dev/null || echo "No matching files"
```

**Step 3: Append results to audit-findings.md and commit**

```bash
git add docs/plans/audit-findings.md
git commit -m "docs: add lesson scanner results to audit findings"
```

---

## Batch 2: Schema Validation

### Task 3: Validate all lesson file YAML frontmatter

**Files:**
- Read: `docs/lessons/0001-*.md` through `docs/lessons/0006-*.md`
- Read: `docs/lessons/TEMPLATE.md` (schema reference)
- Modify: `docs/plans/audit-findings.md`

**Step 1: For each lesson file, verify required YAML fields exist**

Required fields per TEMPLATE.md:
- `id` — integer
- `title` — non-empty string
- `severity` — one of: blocker, should-fix, nice-to-have
- `languages` — array like `[python, javascript]` or `all`
- `category` — one of: async-traps, resource-lifecycle, silent-failures, integration-boundaries, test-anti-patterns, performance
- `pattern.type` — one of: syntactic, semantic
- `pattern.regex` — non-empty string (required if type=syntactic)
- `pattern.description` — non-empty string
- `fix` — non-empty string
- `example.bad` — non-empty
- `example.good` — non-empty

For each file, extract frontmatter and verify each field. Use awk:

```bash
for f in docs/lessons/0*.md; do
  echo "=== $f ==="
  # Extract and display all top-level fields
  awk '/^---$/{c++; if(c==2) exit} c==1 && !/^---$/{print}' "$f"
  echo ""
done
```

**Step 2: Validate regex patterns are valid grep -P**

For each syntactic lesson, test the regex compiles:

```bash
for f in docs/lessons/0*.md; do
  regex=$(awk 'BEGIN{ip=0} /^---$/{c++; if(c==2) exit} c==1 && /^pattern:/{ip=1;next} ip && /^[^[:space:]]/{ip=0} ip && /^[[:space:]]+regex:/{sub(/^[[:space:]]+regex:[[:space:]]+/,""); gsub(/^["'"'"']|["'"'"']$/,""); print}' "$f")
  if [[ -n "$regex" ]]; then
    # Unescape double backslashes (YAML stores \\s, we need \s)
    regex="${regex//\\\\/\\}"
    if echo "" | grep -P "$regex" >/dev/null 2>&1 || [[ $? -le 1 ]]; then
      echo "PASS: $(basename "$f") regex compiles: $regex"
    else
      echo "FAIL: $(basename "$f") invalid regex: $regex"
    fi
  fi
done
```

**Step 3: Append validation results to audit-findings.md and commit**

```bash
git add docs/plans/audit-findings.md
git commit -m "docs: add lesson schema validation to audit findings"
```

### Task 4: Validate plugin manifests, hooks.json, skill frontmatters, and command files

**Files:**
- Read: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
- Read: `hooks/hooks.json`
- Read: `skills/*/SKILL.md` (all 15)
- Read: `commands/*.md` (all 6)
- Modify: `docs/plans/audit-findings.md`

**Step 1: Validate JSON files with jq**

```bash
jq . .claude-plugin/plugin.json >/dev/null && echo "PASS: plugin.json valid JSON"
jq . .claude-plugin/marketplace.json >/dev/null && echo "PASS: marketplace.json valid JSON"
jq . hooks/hooks.json >/dev/null && echo "PASS: hooks.json valid JSON"
```

**Step 2: Check plugin.json has required fields**

```bash
jq -e '.name and .description and .version and .author' .claude-plugin/plugin.json >/dev/null && echo "PASS: plugin.json has required fields"
```

**Step 3: Check all 15 skills have YAML frontmatter with name, description, version**

```bash
for f in skills/*/SKILL.md; do
  name=$(awk '/^---$/{c++; if(c==2) exit} c==1 && /^name:/{sub(/^name:[[:space:]]+/,""); print}' "$f")
  desc=$(awk '/^---$/{c++; if(c==2) exit} c==1 && /^description:/{sub(/^description:[[:space:]]+/,""); print}' "$f")
  ver=$(awk '/^---$/{c++; if(c==2) exit} c==1 && /^version:/{sub(/^version:[[:space:]]+/,""); print}' "$f")
  if [[ -n "$name" && -n "$desc" && -n "$ver" ]]; then
    echo "PASS: $f (name=$name, version=$ver)"
  else
    echo "FAIL: $f missing: ${name:+}${name:-name }${desc:+}${desc:-desc }${ver:+}${ver:-version}"
  fi
done
```

**Step 4: Check all 6 commands have frontmatter with name and description**

```bash
for f in commands/*.md; do
  has_fm=$(awk '/^---$/{c++} c==2{print "yes"; exit}' "$f")
  if [[ "$has_fm" == "yes" ]]; then
    echo "PASS: $f has frontmatter"
  else
    echo "FAIL: $f missing frontmatter"
  fi
done
```

**Step 5: Append to audit-findings.md and commit**

```bash
git add docs/plans/audit-findings.md
git commit -m "docs: add manifest and frontmatter validation to audit findings"
```

---

## Batch 3: Integration Smoke Tests

### Task 5: Smoke test lesson-check.sh with known patterns

**Files:**
- Read: `scripts/lesson-check.sh`
- Read: `docs/lessons/0001-bare-exception-swallowing.md` (regex: `^\s*except\s*:`)
- Read: `docs/lessons/0006-venv-pip-path.md` (regex: `\.venv/bin/pip\b`)

**Step 1: Create test fixture files with known anti-patterns**

Create temporary files:

```bash
TMPDIR=$(mktemp -d)

# File that should trigger lesson-1 (bare except)
cat > "$TMPDIR/bad_except.py" <<'PYEOF'
try:
    do_something()
except:
    pass
PYEOF

# File that should trigger lesson-6 (.venv/bin/pip)
cat > "$TMPDIR/bad_pip.sh" <<'SHEOF'
.venv/bin/pip install requests
SHEOF

# Clean file — no violations
cat > "$TMPDIR/clean.py" <<'PYEOF'
try:
    do_something()
except Exception as e:
    logger.error("Failed: %s", e)
PYEOF
```

**Step 2: Run lesson-check against fixture files**

```bash
# Should find violations
scripts/lesson-check.sh "$TMPDIR/bad_except.py" "$TMPDIR/bad_pip.sh"
echo "Exit code: $?"
# Expected: exit 1, output showing [lesson-1] and [lesson-6]

# Should be clean
scripts/lesson-check.sh "$TMPDIR/clean.py"
echo "Exit code: $?"
# Expected: exit 0, "lesson-check: clean"
```

**Step 3: Clean up and record results**

```bash
rm -rf "$TMPDIR"
```

### Task 6: Smoke test quality-gate.sh with a mock project

**Files:**
- Read: `scripts/quality-gate.sh`

**Step 1: Create mock project directory**

```bash
MOCK_PROJECT=$(mktemp -d)
cd "$MOCK_PROJECT"
git init
echo "print('hello')" > main.py
git add main.py && git commit -m "init"
```

**Step 2: Run quality-gate.sh against it**

```bash
scripts/quality-gate.sh --project-root "$MOCK_PROJECT"
echo "Exit code: $?"
```

Expected: exit 0 (no changed files, no test suite detected, memory OK)

**Step 3: Verify --help works**

```bash
scripts/quality-gate.sh --help
echo "Exit code: $?"
```

Expected: exit 0, help text shown

**Step 4: Clean up**

```bash
rm -rf "$MOCK_PROJECT"
```

### Task 7: Smoke test setup-ralph-loop.sh and stop-hook.sh

**Files:**
- Read: `scripts/setup-ralph-loop.sh`
- Read: `hooks/stop-hook.sh`

**Step 1: Test setup-ralph-loop.sh creates valid state file**

```bash
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
bash /path/to/scripts/setup-ralph-loop.sh "Build a todo API" --max-iterations 10 --completion-promise "DONE"
# Verify state file
cat .claude/ralph-loop.local.md
# Should have: active: true, iteration: 1, max_iterations: 10, completion_promise: "DONE"
```

**Step 2: Test setup-ralph-loop.sh --help**

```bash
bash /path/to/scripts/setup-ralph-loop.sh --help
echo "Exit code: $?"
```

Expected: exit 0, help text

**Step 3: Test setup-ralph-loop.sh with no args**

```bash
bash /path/to/scripts/setup-ralph-loop.sh 2>&1
echo "Exit code: $?"
```

Expected: exit 1, error "No prompt provided"

**Step 4: Test stop-hook.sh with no state file**

```bash
cd "$TMPDIR"
rm -f .claude/ralph-loop.local.md
echo '{}' | bash /path/to/hooks/stop-hook.sh
echo "Exit code: $?"
```

Expected: exit 0 (no state file = allow exit)

**Step 5: Clean up and record**

```bash
rm -rf "$TMPDIR"
```

**Step 6: Commit smoke test results to audit-findings.md**

```bash
git add docs/plans/audit-findings.md
git commit -m "docs: add integration smoke test results to audit findings"
```

---

## Batch 4: Fix All Audit Findings

### Task 8: Fix shellcheck issues

**Files:**
- Modify: Any scripts with shellcheck findings from Task 1

**Step 1: Read audit-findings.md for all FIX-disposition items**

**Step 2: For each FIX item, apply the fix**

Common shellcheck fixes:
- SC2086 (word splitting): Quote variables — `"$var"` instead of `$var`
- SC2155 (declare/assign): Split `local var=$(...)` into `local var; var=$(...)`
- SC2034 (unused variable): Remove or prefix with `_`
- SC2181 (check $?): Use `if command; then` instead of `command; if [[ $? ... ]]`

For SUPPRESS items: Add `# shellcheck disable=SCXXXX` with comment explaining why.

**Step 3: Re-run shellcheck to verify**

```bash
shellcheck -s bash -f gcc scripts/run-plan.sh scripts/lesson-check.sh scripts/quality-gate.sh scripts/setup-ralph-loop.sh scripts/auto-compound.sh scripts/entropy-audit.sh scripts/batch-audit.sh scripts/batch-test.sh scripts/lib/*.sh hooks/stop-hook.sh
```

Expected: 0 findings (all fixed or suppressed)

**Step 4: Run existing tests to verify no regressions**

```bash
bash scripts/tests/run-all-tests.sh
```

Expected: 109/109 pass

**Step 5: Commit**

```bash
git add -A
git commit -m "fix: resolve shellcheck findings across all scripts"
```

### Task 9: Fix schema and smoke test findings

**Files:**
- Modify: Any files with schema or smoke test issues from Tasks 3-7

**Step 1: Fix any lesson file schema issues**

Check audit-findings.md for lesson file issues. Fix YAML frontmatter as needed.

**Step 2: Fix any manifest/frontmatter issues**

Fix plugin.json, marketplace.json, hooks.json, skill frontmatters, command frontmatters as needed.

**Step 3: Fix any bugs discovered during smoke tests**

**Step 4: Re-run all existing tests**

```bash
bash scripts/tests/run-all-tests.sh
```

Expected: 109/109 pass

**Step 5: Commit**

```bash
git add -A
git commit -m "fix: resolve schema and smoke test findings"
```

---

## Batch 5: lesson-check.sh Tests (**CRITICAL — A/B Competitive**)

### Task 10: Create test-lesson-check.sh with parse_lesson unit tests

**Files:**
- Create: `scripts/tests/test-lesson-check.sh`
- Read: `scripts/lesson-check.sh` (source `parse_lesson` function)
- Read: `docs/lessons/0001-*.md` through `docs/lessons/0006-*.md`

**Step 1: Write the test file with helper functions and parse_lesson tests**

Create `scripts/tests/test-lesson-check.sh`:

```bash
#!/usr/bin/env bash
# Test lesson-check.sh — parse_lesson(), regex matching, language filter, exit codes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LESSON_CHECK="$SCRIPT_DIR/../lesson-check.sh"

# Source the lesson-check.sh to get parse_lesson and file_matches_languages
# We need to source it without running the main logic.
# Extract functions only by sourcing in a subshell context.
LESSONS_DIR="$SCRIPT_DIR/../../docs/lessons"

FAILURES=0
TESTS=0

assert_equals() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$actual" != "$expected" ]]; then
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
    local output
    output=$("$@" 2>&1) || actual_exit=$?
    TESTS=$((TESTS + 1))
    if [[ "$actual_exit" -ne "$expected_exit" ]]; then
        echo "FAIL: $desc"
        echo "  expected exit: $expected_exit"
        echo "  actual exit:   $actual_exit"
        echo "  output: ${output:0:300}"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_output_contains() {
    local desc="$1" needle="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    TESTS=$((TESTS + 1))
    if [[ "$output" != *"$needle"* ]]; then
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  in: ${output:0:300}"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_output_not_contains() {
    local desc="$1" needle="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    TESTS=$((TESTS + 1))
    if [[ "$output" == *"$needle"* ]]; then
        echo "FAIL: $desc"
        echo "  expected NOT to contain: $needle"
        echo "  in: ${output:0:300}"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

# --- Create test fixtures ---
FIXTURES=$(mktemp -d)
trap 'rm -rf "$FIXTURES"' EXIT

# Python file with bare except (triggers lesson-1)
cat > "$FIXTURES/bare_except.py" <<'EOF'
try:
    do_something()
except:
    pass
EOF

# Python file with clean except (should NOT trigger)
cat > "$FIXTURES/clean_except.py" <<'EOF'
try:
    do_something()
except Exception as e:
    logger.error("Failed: %s", e)
EOF

# Shell file with .venv/bin/pip (triggers lesson-6)
cat > "$FIXTURES/bad_pip.sh" <<'EOF'
.venv/bin/pip install requests
EOF

# Python file with sqlite3.connect (triggers lesson-5)
cat > "$FIXTURES/bad_sqlite.py" <<'EOF'
import sqlite3
conn = sqlite3.connect("test.db")
EOF

# Python file with hardcoded test count (triggers lesson-4)
cat > "$FIXTURES/bad_test_count.py" <<'EOF'
def test_items():
    items = get_all()
    assert len(items) == 42
EOF

# Clean shell file — no violations
cat > "$FIXTURES/clean.sh" <<'EOF'
#!/bin/bash
echo "hello world"
EOF

# Empty file
touch "$FIXTURES/empty.py"

# --- Tests: Exit codes ---
assert_exit "clean file exits 0" 0 "$LESSON_CHECK" "$FIXTURES/clean.sh"
assert_exit "bare except exits 1" 1 "$LESSON_CHECK" "$FIXTURES/bare_except.py"
assert_exit "no files exits 0" 0 "$LESSON_CHECK"
assert_exit "--help exits 0" 0 "$LESSON_CHECK" --help

# --- Tests: Detection accuracy ---
assert_output_contains "detects bare except" "[lesson-1]" "$LESSON_CHECK" "$FIXTURES/bare_except.py"
assert_output_not_contains "clean except not detected" "[lesson-1]" "$LESSON_CHECK" "$FIXTURES/clean_except.py"
assert_output_contains "detects .venv/bin/pip" "[lesson-6]" "$LESSON_CHECK" "$FIXTURES/bad_pip.sh"
assert_output_contains "detects sqlite3.connect" "[lesson-5]" "$LESSON_CHECK" "$FIXTURES/bad_sqlite.py"
assert_output_contains "detects hardcoded test count" "[lesson-4]" "$LESSON_CHECK" "$FIXTURES/bad_test_count.py"

# --- Tests: Language filtering ---
# lesson-1 is python-only — should NOT trigger on .sh files even if they contain "except:"
cat > "$FIXTURES/except_in_shell.sh" <<'EOF'
# This has except: in a comment
except:
EOF
assert_output_not_contains "python lesson skips .sh files" "[lesson-1]" "$LESSON_CHECK" "$FIXTURES/except_in_shell.sh"

# lesson-6 is shell-only — should NOT trigger on .py files
cat > "$FIXTURES/pip_in_python.py" <<'EOF'
# .venv/bin/pip is mentioned in a comment
path = ".venv/bin/pip"
EOF
assert_output_not_contains "shell lesson skips .py files" "[lesson-6]" "$LESSON_CHECK" "$FIXTURES/pip_in_python.py"

# --- Tests: Multiple files ---
assert_output_contains "multiple files: finds violation in first" "[lesson-1]" "$LESSON_CHECK" "$FIXTURES/bare_except.py" "$FIXTURES/clean.sh"
assert_exit "multiple files with violation exits 1" 1 "$LESSON_CHECK" "$FIXTURES/bare_except.py" "$FIXTURES/clean.sh"

# --- Tests: Stdin pipe mode ---
assert_output_contains "stdin pipe detects violation" "[lesson-1]" bash -c "echo '$FIXTURES/bare_except.py' | $LESSON_CHECK"

# --- Tests: --help shows dynamic lessons ---
assert_output_contains "--help shows lesson-1" "[lesson-1]" "$LESSON_CHECK" --help
assert_output_contains "--help shows lesson-6" "[lesson-6]" "$LESSON_CHECK" --help

# --- Tests: Empty and nonexistent files ---
assert_exit "empty file exits 0" 0 "$LESSON_CHECK" "$FIXTURES/empty.py"
assert_exit "nonexistent file exits 0" 0 "$LESSON_CHECK" "$FIXTURES/does_not_exist.py"

# --- Tests: Violation count ---
assert_output_contains "reports violation count" "violation(s) found" "$LESSON_CHECK" "$FIXTURES/bare_except.py"
assert_output_contains "clean reports clean" "lesson-check: clean" "$LESSON_CHECK" "$FIXTURES/clean.sh"

# --- Summary ---
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run the test**

```bash
bash scripts/tests/test-lesson-check.sh
```

Expected: All tests pass. If any fail, fix lesson-check.sh or the test expectations.

**Step 3: Verify existing tests still pass**

```bash
bash scripts/tests/run-all-tests.sh
```

Expected: 109/109 still pass (new test file won't be picked up by `test-run-plan-*.sh` glob)

**Step 4: Update run-all-tests.sh to also discover test-lesson-check.sh and other new test files**

Modify `scripts/tests/run-all-tests.sh` line 13 — change the glob from `test-run-plan-*.sh` to `test-*.sh`:

```bash
# Old:
mapfile -t TEST_FILES < <(find "$SCRIPT_DIR" -maxdepth 1 -name "test-run-plan-*.sh" -type f | sort)
# New:
mapfile -t TEST_FILES < <(find "$SCRIPT_DIR" -maxdepth 1 -name "test-*.sh" -type f | sort)
```

**Step 5: Run updated test runner**

```bash
bash scripts/tests/run-all-tests.sh
```

Expected: 109 + new tests all pass (8 test files now)

**Step 6: Commit**

```bash
git add scripts/tests/test-lesson-check.sh scripts/tests/run-all-tests.sh
git commit -m "test: add comprehensive tests for lesson-check.sh"
```

---

## Batch 6: stop-hook.sh + setup-ralph-loop.sh Tests (**CRITICAL — A/B Competitive**)

### Task 11: Create test-stop-hook.sh

**Files:**
- Create: `scripts/tests/test-stop-hook.sh`
- Read: `hooks/stop-hook.sh`

**Step 1: Write test-stop-hook.sh**

Create `scripts/tests/test-stop-hook.sh`:

```bash
#!/usr/bin/env bash
# Test hooks/stop-hook.sh — state file parsing, iteration, completion promise, JSON output
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STOP_HOOK="$SCRIPT_DIR/../../hooks/stop-hook.sh"

FAILURES=0
TESTS=0

assert_exit() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    local output
    output=$("$@" 2>&1) || actual_exit=$?
    TESTS=$((TESTS + 1))
    if [[ "$actual_exit" -ne "$expected_exit" ]]; then
        echo "FAIL: $desc"
        echo "  expected exit: $expected_exit"
        echo "  actual exit:   $actual_exit"
        echo "  output: ${output:0:500}"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_output_contains() {
    local desc="$1" needle="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    TESTS=$((TESTS + 1))
    if [[ "$output" != *"$needle"* ]]; then
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  in: ${output:0:500}"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_json_field() {
    local desc="$1" field="$2" expected="$3" json="$4"
    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null || echo "PARSE_ERROR")
    TESTS=$((TESTS + 1))
    if [[ "$actual" != "$expected" ]]; then
        echo "FAIL: $desc"
        echo "  field: $field"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

# --- Setup ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# --- Test: No state file = allow exit ---
assert_exit "no state file exits 0" 0 bash -c "echo '{}' | bash '$STOP_HOOK'"

# --- Test: State file with max iterations reached ---
mkdir -p .claude
cat > .claude/ralph-loop.local.md <<'STATE'
---
active: true
iteration: 10
max_iterations: 10
completion_promise: null
started_at: "2026-01-01T00:00:00Z"
---

Build something
STATE

assert_exit "max iterations reached exits 0" 0 bash -c "echo '{}' | bash '$STOP_HOOK'"
# State file should be removed
TESTS=$((TESTS + 1))
if [[ -f .claude/ralph-loop.local.md ]]; then
    echo "FAIL: state file should be removed at max iterations"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: state file removed at max iterations"
fi

# --- Test: Corrupted state file (non-numeric iteration) ---
mkdir -p .claude
cat > .claude/ralph-loop.local.md <<'STATE'
---
active: true
iteration: abc
max_iterations: 10
completion_promise: null
started_at: "2026-01-01T00:00:00Z"
---

Build something
STATE

assert_exit "corrupted iteration exits 0" 0 bash -c "echo '{}' | bash '$STOP_HOOK'"
assert_output_contains "corrupted iteration warns" "corrupted" bash -c "echo '{}' | bash '$STOP_HOOK'" || true

# --- Test: Active loop with transcript containing completion promise ---
mkdir -p .claude
cat > .claude/ralph-loop.local.md <<'STATE'
---
active: true
iteration: 3
max_iterations: 0
completion_promise: "ALL_TESTS_PASS"
started_at: "2026-01-01T00:00:00Z"
---

Build and test everything
STATE

# Create mock transcript with completion promise
TRANSCRIPT="$WORK/transcript.jsonl"
cat > "$TRANSCRIPT" <<TRANSCRIPT_EOF
{"role":"user","message":{"content":[{"type":"text","text":"start"}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"Done! <promise>ALL_TESTS_PASS</promise>"}]}}
TRANSCRIPT_EOF

HOOK_INPUT=$(jq -n --arg tp "$TRANSCRIPT" '{"transcript_path": $tp}')
OUTPUT=$(echo "$HOOK_INPUT" | bash "$STOP_HOOK" 2>&1) || true
TESTS=$((TESTS + 1))
if [[ "$OUTPUT" == *"Detected"* ]]; then
    echo "PASS: completion promise detected"
else
    echo "FAIL: completion promise not detected"
    echo "  output: ${OUTPUT:0:500}"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: Active loop WITHOUT completion promise in transcript → block and continue ---
mkdir -p .claude
cat > .claude/ralph-loop.local.md <<'STATE'
---
active: true
iteration: 3
max_iterations: 0
completion_promise: "ALL_TESTS_PASS"
started_at: "2026-01-01T00:00:00Z"
---

Build and test everything
STATE

TRANSCRIPT2="$WORK/transcript2.jsonl"
cat > "$TRANSCRIPT2" <<TRANSCRIPT_EOF
{"role":"user","message":{"content":[{"type":"text","text":"start"}]}}
{"role":"assistant","message":{"content":[{"type":"text","text":"Still working on it..."}]}}
TRANSCRIPT_EOF

HOOK_INPUT2=$(jq -n --arg tp "$TRANSCRIPT2" '{"transcript_path": $tp}')
OUTPUT2=$(echo "$HOOK_INPUT2" | bash "$STOP_HOOK" 2>&1) || true

# Should output JSON with "decision": "block"
assert_json_field "block decision when promise not found" ".decision" "block" "$OUTPUT2"
assert_json_field "reason contains prompt" ".reason" "Build and test everything" "$OUTPUT2"

# Iteration should be incremented
TESTS=$((TESTS + 1))
if [[ -f .claude/ralph-loop.local.md ]]; then
    NEW_ITER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' .claude/ralph-loop.local.md | grep '^iteration:' | sed 's/iteration: *//')
    if [[ "$NEW_ITER" == "4" ]]; then
        echo "PASS: iteration incremented to 4"
    else
        echo "FAIL: iteration should be 4, got $NEW_ITER"
        FAILURES=$((FAILURES + 1))
    fi
else
    echo "FAIL: state file should still exist"
    FAILURES=$((FAILURES + 1))
fi

# --- Summary ---
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test**

```bash
bash scripts/tests/test-stop-hook.sh
```

Expected: All pass

**Step 3: Commit**

```bash
git add scripts/tests/test-stop-hook.sh
git commit -m "test: add comprehensive tests for stop-hook.sh"
```

### Task 12: Create test-setup-ralph-loop.sh

**Files:**
- Create: `scripts/tests/test-setup-ralph-loop.sh`
- Read: `scripts/setup-ralph-loop.sh`

**Step 1: Write test-setup-ralph-loop.sh**

Create `scripts/tests/test-setup-ralph-loop.sh`:

```bash
#!/usr/bin/env bash
# Test scripts/setup-ralph-loop.sh — state file creation, arg parsing, error handling
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_RALPH="$SCRIPT_DIR/../setup-ralph-loop.sh"

FAILURES=0
TESTS=0

assert_exit() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    local output
    output=$("$@" 2>&1) || actual_exit=$?
    TESTS=$((TESTS + 1))
    if [[ "$actual_exit" -ne "$expected_exit" ]]; then
        echo "FAIL: $desc"
        echo "  expected exit: $expected_exit"
        echo "  actual exit:   $actual_exit"
        echo "  output: ${output:0:300}"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_output_contains() {
    local desc="$1" needle="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    TESTS=$((TESTS + 1))
    if [[ "$output" != *"$needle"* ]]; then
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  in: ${output:0:300}"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_file_contains() {
    local desc="$1" needle="$2" filepath="$3"
    TESTS=$((TESTS + 1))
    if [[ ! -f "$filepath" ]]; then
        echo "FAIL: $desc (file not found: $filepath)"
        FAILURES=$((FAILURES + 1))
    elif grep -q "$needle" "$filepath"; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected file to contain: $needle"
        FAILURES=$((FAILURES + 1))
    fi
}

# --- Setup ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- Test: --help exits 0 ---
assert_exit "--help exits 0" 0 bash "$SETUP_RALPH" --help

# --- Test: No prompt exits 1 ---
assert_exit "no prompt exits 1" 1 bash -c "cd '$WORK' && bash '$SETUP_RALPH'"

# --- Test: Invalid --max-iterations exits 1 ---
assert_exit "non-numeric max-iterations exits 1" 1 bash -c "cd '$WORK' && bash '$SETUP_RALPH' Build something --max-iterations abc"

# --- Test: Basic prompt creates state file ---
rm -rf "$WORK/.claude"
(cd "$WORK" && bash "$SETUP_RALPH" "Build a todo API") >/dev/null 2>&1
TESTS=$((TESTS + 1))
if [[ -f "$WORK/.claude/ralph-loop.local.md" ]]; then
    echo "PASS: state file created"
else
    echo "FAIL: state file not created"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: State file has correct frontmatter ---
assert_file_contains "state has active: true" "active: true" "$WORK/.claude/ralph-loop.local.md"
assert_file_contains "state has iteration: 1" "iteration: 1" "$WORK/.claude/ralph-loop.local.md"
assert_file_contains "state has max_iterations: 0" "max_iterations: 0" "$WORK/.claude/ralph-loop.local.md"
assert_file_contains "state has prompt text" "Build a todo API" "$WORK/.claude/ralph-loop.local.md"

# --- Test: With --max-iterations and --completion-promise ---
rm -rf "$WORK/.claude"
(cd "$WORK" && bash "$SETUP_RALPH" "Fix the auth bug" --max-iterations 20 --completion-promise "DONE") >/dev/null 2>&1
assert_file_contains "max-iterations in state" "max_iterations: 20" "$WORK/.claude/ralph-loop.local.md"
assert_file_contains "completion-promise in state" 'completion_promise: "DONE"' "$WORK/.claude/ralph-loop.local.md"
assert_file_contains "prompt in state" "Fix the auth bug" "$WORK/.claude/ralph-loop.local.md"

# --- Test: Multi-word prompt without quotes ---
rm -rf "$WORK/.claude"
(cd "$WORK" && bash "$SETUP_RALPH" Build a todo API with tests) >/dev/null 2>&1
assert_file_contains "multi-word prompt joined" "Build a todo API with tests" "$WORK/.claude/ralph-loop.local.md"

# --- Test: Output contains activation message ---
rm -rf "$WORK/.claude"
assert_output_contains "output shows activated" "Ralph loop activated" bash -c "cd '$WORK' && bash '$SETUP_RALPH' Test prompt"

# --- Summary ---
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test**

```bash
bash scripts/tests/test-setup-ralph-loop.sh
```

Expected: All pass

**Step 3: Commit**

```bash
git add scripts/tests/test-setup-ralph-loop.sh
git commit -m "test: add tests for setup-ralph-loop.sh"
```

---

## Batch 7: quality-gate.sh + Utility Tests

### Task 13: Create test-quality-gate.sh for orchestration logic

**Files:**
- Create: `scripts/tests/test-quality-gate.sh`
- Read: `scripts/quality-gate.sh`

**Step 1: Write test-quality-gate.sh**

Create `scripts/tests/test-quality-gate.sh`:

```bash
#!/usr/bin/env bash
# Test scripts/quality-gate.sh — CLI args, test runner detection, exit codes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUALITY_GATE="$SCRIPT_DIR/../quality-gate.sh"

FAILURES=0
TESTS=0

assert_exit() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    local output
    output=$("$@" 2>&1) || actual_exit=$?
    TESTS=$((TESTS + 1))
    if [[ "$actual_exit" -ne "$expected_exit" ]]; then
        echo "FAIL: $desc"
        echo "  expected exit: $expected_exit"
        echo "  actual exit:   $actual_exit"
        echo "  output: ${output:0:300}"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_output_contains() {
    local desc="$1" needle="$2"
    shift 2
    local output
    output=$("$@" 2>&1) || true
    TESTS=$((TESTS + 1))
    if [[ "$output" != *"$needle"* ]]; then
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  in: ${output:0:300}"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

# --- Test: --help exits 0 ---
assert_exit "--help exits 0" 0 "$QUALITY_GATE" --help

# --- Test: No --project-root exits 1 ---
assert_exit "no project-root exits 1" 1 "$QUALITY_GATE"

# --- Test: Nonexistent directory exits 1 ---
assert_exit "nonexistent dir exits 1" 1 "$QUALITY_GATE" --project-root /tmp/nonexistent-dir-$$

# --- Test: Unknown option exits 1 ---
assert_exit "unknown option exits 1" 1 "$QUALITY_GATE" --unknown-flag

# --- Test: Clean git repo with no test suite passes ---
MOCK=$(mktemp -d)
trap 'rm -rf "$MOCK"' EXIT
cd "$MOCK"
git init -q
echo "hello" > file.txt
git add file.txt && git commit -q -m "init"
cd - >/dev/null

assert_exit "clean repo passes" 0 "$QUALITY_GATE" --project-root "$MOCK"
assert_output_contains "skips test suite when none detected" "No test suite detected" "$QUALITY_GATE" --project-root "$MOCK"
assert_output_contains "shows ALL PASSED" "ALL PASSED" "$QUALITY_GATE" --project-root "$MOCK"
assert_output_contains "shows Memory" "Memory" "$QUALITY_GATE" --project-root "$MOCK"

# --- Test: help text mentions required options ---
assert_output_contains "help mentions --project-root" "--project-root" "$QUALITY_GATE" --help
assert_output_contains "help mentions lesson check" "Lesson check" "$QUALITY_GATE" --help

# --- Summary ---
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test**

```bash
bash scripts/tests/test-quality-gate.sh
```

**Step 3: Commit**

```bash
git add scripts/tests/test-quality-gate.sh
git commit -m "test: add orchestration tests for quality-gate.sh"
```

---

## Batch 8: Low-Risk Validation Tests + Integration Wiring

### Task 14: Create test-lesson-schema.sh (reusable lesson file validator)

**Files:**
- Create: `scripts/tests/test-lesson-schema.sh`

**Step 1: Write test-lesson-schema.sh**

Create `scripts/tests/test-lesson-schema.sh`:

```bash
#!/usr/bin/env bash
# Test that all lesson files in docs/lessons/ have valid YAML frontmatter
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LESSONS_DIR="$SCRIPT_DIR/../../docs/lessons"

FAILURES=0
TESTS=0

assert_true() {
    local desc="$1" condition="$2"
    TESTS=$((TESTS + 1))
    if eval "$condition"; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        FAILURES=$((FAILURES + 1))
    fi
}

VALID_SEVERITIES="blocker should-fix nice-to-have"
VALID_TYPES="syntactic semantic"
VALID_CATEGORIES="async-traps resource-lifecycle silent-failures integration-boundaries test-anti-patterns performance"

for f in "$LESSONS_DIR"/[0-9]*.md; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f")

    # Extract frontmatter
    fm=$(awk '/^---$/{c++; if(c==2) exit} c==1 && !/^---$/{print}' "$f")

    # Required top-level fields
    id=$(echo "$fm" | grep '^id:' | sed 's/^id:[[:space:]]*//')
    title=$(echo "$fm" | grep '^title:' | sed 's/^title:[[:space:]]*//' | sed 's/^["'"'"']//;s/["'"'"']$//')
    severity=$(echo "$fm" | grep '^severity:' | sed 's/^severity:[[:space:]]*//')
    languages=$(echo "$fm" | grep '^languages:' | sed 's/^languages:[[:space:]]*//')
    category=$(echo "$fm" | grep '^category:' | sed 's/^category:[[:space:]]*//')
    fix=$(echo "$fm" | grep '^fix:' | sed 's/^fix:[[:space:]]*//')

    # Nested pattern fields
    ptype=$(echo "$fm" | awk '/^pattern:/{ip=1;next} ip && /^[^[:space:]]/{ip=0} ip && /^[[:space:]]+type:/{sub(/^[[:space:]]+type:[[:space:]]+/,""); print}')

    assert_true "$base: has id" '[[ -n "$id" ]]'
    assert_true "$base: id is numeric" '[[ "$id" =~ ^[0-9]+$ ]]'
    assert_true "$base: has title" '[[ -n "$title" ]]'
    assert_true "$base: has severity" '[[ -n "$severity" ]]'
    assert_true "$base: severity is valid" '[[ "$VALID_SEVERITIES" == *"$severity"* ]]'
    assert_true "$base: has languages" '[[ -n "$languages" ]]'
    assert_true "$base: has category" '[[ -n "$category" ]]'
    assert_true "$base: category is valid" '[[ "$VALID_CATEGORIES" == *"$category"* ]]'
    assert_true "$base: has pattern.type" '[[ -n "$ptype" ]]'
    assert_true "$base: pattern.type is valid" '[[ "$VALID_TYPES" == *"$ptype"* ]]'
    assert_true "$base: has fix" '[[ -n "$fix" ]]'

    # If syntactic, must have regex
    if [[ "$ptype" == "syntactic" ]]; then
        pregex=$(echo "$fm" | awk '/^pattern:/{ip=1;next} ip && /^[^[:space:]]/{ip=0} ip && /^[[:space:]]+regex:/{sub(/^[[:space:]]+regex:[[:space:]]+/,""); gsub(/^["'"'"']|["'"'"']$/,""); print}')
        assert_true "$base: syntactic has regex" '[[ -n "$pregex" ]]'

        # Test regex compiles with grep -P
        pregex_unesc="${pregex//\\\\/\\}"
        compile_ok=true
        echo "" | grep -P "$pregex_unesc" >/dev/null 2>&1 || { [[ $? -le 1 ]] || compile_ok=false; }
        assert_true "$base: regex compiles" '$compile_ok'
    fi
done

# --- Summary ---
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test**

```bash
bash scripts/tests/test-lesson-schema.sh
```

**Step 3: Commit**

```bash
git add scripts/tests/test-lesson-schema.sh
git commit -m "test: add lesson schema validation tests"
```

### Task 15: Create test-plugin-manifests.sh (JSON + frontmatter validation)

**Files:**
- Create: `scripts/tests/test-plugin-manifests.sh`

**Step 1: Write test-plugin-manifests.sh**

Create `scripts/tests/test-plugin-manifests.sh`:

```bash
#!/usr/bin/env bash
# Test plugin manifests, hooks.json, skill frontmatters, and command frontmatters
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/../.."

FAILURES=0
TESTS=0

assert_true() {
    local desc="$1" condition="$2"
    TESTS=$((TESTS + 1))
    if eval "$condition"; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        FAILURES=$((FAILURES + 1))
    fi
}

# --- JSON validity ---
assert_true "plugin.json is valid JSON" 'jq . "$REPO_ROOT/.claude-plugin/plugin.json" >/dev/null 2>&1'
assert_true "marketplace.json is valid JSON" 'jq . "$REPO_ROOT/.claude-plugin/marketplace.json" >/dev/null 2>&1'
assert_true "hooks.json is valid JSON" 'jq . "$REPO_ROOT/hooks/hooks.json" >/dev/null 2>&1'

# --- plugin.json required fields ---
assert_true "plugin.json has name" 'jq -e ".name" "$REPO_ROOT/.claude-plugin/plugin.json" >/dev/null 2>&1'
assert_true "plugin.json has description" 'jq -e ".description" "$REPO_ROOT/.claude-plugin/plugin.json" >/dev/null 2>&1'
assert_true "plugin.json has version" 'jq -e ".version" "$REPO_ROOT/.claude-plugin/plugin.json" >/dev/null 2>&1'
assert_true "plugin.json has author" 'jq -e ".author" "$REPO_ROOT/.claude-plugin/plugin.json" >/dev/null 2>&1'

# --- marketplace.json required fields ---
assert_true "marketplace.json has \$schema" 'jq -e ".\"\\$schema\"" "$REPO_ROOT/.claude-plugin/marketplace.json" >/dev/null 2>&1'
assert_true "marketplace.json has plugins" 'jq -e ".plugins" "$REPO_ROOT/.claude-plugin/marketplace.json" >/dev/null 2>&1'

# --- hooks.json structure ---
assert_true "hooks.json has hooks.Stop" 'jq -e ".hooks.Stop" "$REPO_ROOT/hooks/hooks.json" >/dev/null 2>&1'
assert_true "hooks.json references stop-hook.sh" 'jq -r ".hooks.Stop[0].hooks[0].command" "$REPO_ROOT/hooks/hooks.json" | grep -q "stop-hook.sh"'

# --- Skill frontmatters ---
for f in "$REPO_ROOT"/skills/*/SKILL.md; do
    base=$(basename "$(dirname "$f")")
    has_name=$(awk '/^---$/{c++; if(c==2) exit} c==1 && /^name:/{print "yes"}' "$f")
    has_desc=$(awk '/^---$/{c++; if(c==2) exit} c==1 && /^description:/{print "yes"}' "$f")
    has_ver=$(awk '/^---$/{c++; if(c==2) exit} c==1 && /^version:/{print "yes"}' "$f")
    assert_true "skill $base has name" '[[ "$has_name" == "yes" ]]'
    assert_true "skill $base has description" '[[ "$has_desc" == "yes" ]]'
    assert_true "skill $base has version" '[[ "$has_ver" == "yes" ]]'
done

# --- Command frontmatters ---
for f in "$REPO_ROOT"/commands/*.md; do
    base=$(basename "$f")
    has_fm=$(awk '/^---$/{c++} c==2{print "yes"; exit}' "$f")
    assert_true "command $base has frontmatter" '[[ "$has_fm" == "yes" ]]'
done

# --- Summary ---
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test**

```bash
bash scripts/tests/test-plugin-manifests.sh
```

**Step 3: Commit**

```bash
git add scripts/tests/test-plugin-manifests.sh
git commit -m "test: add plugin manifest and frontmatter validation tests"
```

### Task 16: Final integration verification

**Files:**
- Read: all test files

**Step 1: Run full test suite**

```bash
bash scripts/tests/run-all-tests.sh
```

Expected: All tests pass across all test files (old + new)

**Step 2: Count total tests**

```bash
bash scripts/tests/run-all-tests.sh 2>&1 | tail -5
```

Expected: Total should be 170+ (109 existing + 60+ new)

**Step 3: Run shellcheck one final time**

```bash
shellcheck -s bash scripts/tests/test-*.sh
```

Expected: Clean (our test files should also pass shellcheck)

**Step 4: Commit any final fixes**

```bash
git add -A
git commit -m "test: final integration verification — all tests pass"
```

**Step 5: Push to remote**

```bash
git push origin main
```
