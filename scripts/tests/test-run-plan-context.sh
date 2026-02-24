#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"
source "$SCRIPT_DIR/../lib/progress-writer.sh"
source "$SCRIPT_DIR/../lib/run-plan-context.sh"

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

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  actual: ${haystack:0:200}..."
        FAILURES=$((FAILURES + 1))
    fi
}

assert_not_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected NOT to contain: $needle"
        FAILURES=$((FAILURES + 1))
    fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT  # #59: ensure cleanup on any exit path, including early test failure

# === Setup test fixtures ===

# State file
cat > "$WORK/.run-plan-state.json" << 'JSON'
{
  "plan": "test-plan.md",
  "mode": "headless",
  "batches": {
    "1": {"passed": true, "test_count": 50, "duration": 120},
    "2": {"passed": true, "test_count": 75, "duration": 90}
  }
}
JSON

# Progress file
cat > "$WORK/progress.txt" << 'TXT'
Batch 1: Created shared library
Batch 2: Fixed test parsing
Discovery: jest output needs special handling
TXT

# Git repo for git log
cd "$WORK" && git init -q && git commit --allow-empty -m "batch 1: initial" -q && git commit --allow-empty -m "batch 2: add tests" -q
cd - > /dev/null

# Plan with context_refs
cat > "$WORK/test-plan.md" << 'PLAN'
## Batch 1: Foundation
### Task 1: Setup
Create lib.

## Batch 2: Tests
### Task 2: Add tests
context_refs: src/lib.sh

## Batch 3: Integration
### Task 3: Wire together
context_refs: src/lib.sh, tests/test-lib.sh
PLAN

# Context ref files
mkdir -p "$WORK/src" "$WORK/tests"
echo "#!/bin/bash" > "$WORK/src/lib.sh"
echo "echo hello" >> "$WORK/src/lib.sh"
echo "#!/bin/bash" > "$WORK/tests/test-lib.sh"

# === Tests ===

# generate_batch_context for batch 3 (has context_refs and prior batches)
ctx=$(generate_batch_context "$WORK/test-plan.md" 3 "$WORK")
assert_contains "context: includes quality gate expectation" "tests must stay above 75" "$ctx"
assert_contains "context: includes prior batch summary" "Batch 2" "$ctx"
assert_contains "context: includes context_refs content" "echo hello" "$ctx"
assert_not_contains "context: excludes batch 1 details for batch 3" "Batch 1: Foundation" "$ctx"

# generate_batch_context for batch 1 (no prior context)
ctx=$(generate_batch_context "$WORK/test-plan.md" 1 "$WORK")
assert_contains "context batch 1: minimal context" "Run-Plan" "$ctx"
# Should be short — no prior batches, no context_refs
char_count=${#ctx}
TESTS=$((TESTS + 1))
if [[ $char_count -lt 2000 ]]; then
    echo "PASS: context batch 1: under 2000 chars ($char_count)"
else
    echo "FAIL: context batch 1: over 2000 chars ($char_count)"
    FAILURES=$((FAILURES + 1))
fi

# Token budget: context should stay under 6000 chars (~1500 tokens)
ctx=$(generate_batch_context "$WORK/test-plan.md" 3 "$WORK")
char_count=${#ctx}
TESTS=$((TESTS + 1))
if [[ $char_count -lt 6000 ]]; then
    echo "PASS: context batch 3: under 6000 chars ($char_count)"
else
    echo "FAIL: context batch 3: over 6000 chars ($char_count)"
    FAILURES=$((FAILURES + 1))
fi

# Failure patterns injection
mkdir -p "$WORK/logs"
cat > "$WORK/logs/failure-patterns.json" << 'JSON'
[{"batch_title_pattern": "integration", "failure_type": "missing import", "frequency": 3, "winning_fix": "check all imports before running tests"}]
JSON

ctx=$(generate_batch_context "$WORK/test-plan.md" 3 "$WORK")
assert_contains "context: includes failure pattern warning" "missing import" "$ctx"

# === MAB lessons injection ===

# Create MAB lessons file
cat > "$WORK/logs/mab-lessons.json" << 'JSON'
[{"pattern": "check imports before tests", "context": "integration", "winner": "superpowers", "occurrences": 3, "promoted": false}]
JSON

ctx_mab=$(generate_batch_context "$WORK/test-plan.md" 3 "$WORK")
assert_contains "context: MAB lessons injected when file present" "check imports before tests" "$ctx_mab"
assert_contains "context: MAB lessons section header" "MAB Lessons" "$ctx_mab"

# Remove MAB lessons and verify no section
rm -f "$WORK/logs/mab-lessons.json"
ctx_no_mab=$(generate_batch_context "$WORK/test-plan.md" 3 "$WORK")
assert_not_contains "context: no MAB section when file absent" "MAB Lessons" "$ctx_no_mab"

# === No tail fallback: structured read returns empty, no wrong-batch data injected (#54) ===

# Progress.txt with only batch 1 content (no batch 2)
WORK_NOTAIL=$(mktemp -d)
trap 'rm -rf "$WORK_NOTAIL"' EXIT
cat > "$WORK_NOTAIL/test-plan.md" << 'PLAN_NOTAIL'
## Batch 1: Alpha
### Task 1: Do alpha
Do something.

## Batch 2: Beta
### Task 2: Do beta
Do more.
PLAN_NOTAIL
cat > "$WORK_NOTAIL/.run-plan-state.json" << 'JSON_NOTAIL'
{"plan": "test-plan.md", "mode": "headless", "batches": {}}
JSON_NOTAIL

# Write unrelated content to progress.txt (no structured headers)
echo "some unrelated content from a different run" > "$WORK_NOTAIL/progress.txt"
echo "batch 99 leftovers here" >> "$WORK_NOTAIL/progress.txt"

# generate_batch_context for batch 2: progress.txt exists but has no structured batch 1 data
# Should NOT inject the tail content as "Progress Notes"
cd "$WORK_NOTAIL" && git init -q && git commit --allow-empty -m "init" -q
cd - > /dev/null
ctx_notail=$(generate_batch_context "$WORK_NOTAIL/test-plan.md" 2 "$WORK_NOTAIL")
assert_not_contains "no-tail-fallback: unrelated progress.txt content not injected" "batch 99 leftovers" "$ctx_notail"
assert_not_contains "no-tail-fallback: tail content not injected as Progress Notes" "unrelated content from a different run" "$ctx_notail"

# === git -C fix: git log works without cd (#61) ===

# Verify the generate_batch_context produces git log output without needing cwd change
ctx_gitlog=$(generate_batch_context "$WORK/test-plan.md" 3 "$WORK")
assert_contains "git-C: recent commits appear in context" "Recent Commits" "$ctx_gitlog"

# === Failure pattern recording ===

# Clean up pre-existing patterns file for isolated testing
rm -f "$WORK/logs/failure-patterns.json"

record_failure_pattern "$WORK" "Integration Wiring" "missing import" "check imports before tests"

assert_eq "record_failure_pattern: creates file" "true" "$(test -f "$WORK/logs/failure-patterns.json" && echo true || echo false)"

# Record same pattern again — should increment frequency
record_failure_pattern "$WORK" "Integration Wiring" "missing import" "check imports before tests"
freq=$(jq '.[0].frequency' "$WORK/logs/failure-patterns.json")
assert_eq "record_failure_pattern: increments frequency" "2" "$freq"

# Record different pattern
record_failure_pattern "$WORK" "Test Suite" "flaky assertion" "use deterministic comparisons"
count=$(jq 'length' "$WORK/logs/failure-patterns.json")
assert_eq "record_failure_pattern: adds new pattern" "2" "$count"

# === Bug #60 BEHAVIORAL: whitespace in context_refs is trimmed ===
# context_refs: " src/lib.sh , tests/test-lib.sh " should resolve both files
# despite leading/trailing spaces around each path.

WORK_WS=$(mktemp -d)
trap 'rm -rf "$WORK_WS"' EXIT

# Plan with whitespace-padded context_refs
cat > "$WORK_WS/test-plan.md" << 'PLAN_WS'
## Batch 1: Setup
### Task 1: Init
Do init work.

## Batch 2: Test whitespace
### Task 2: Check refs
context_refs:  src/padded.sh , tests/padded-test.sh
PLAN_WS

# Create the referenced files
mkdir -p "$WORK_WS/src" "$WORK_WS/tests"
echo "PADDED_CONTENT=true" > "$WORK_WS/src/padded.sh"
echo "PADDED_TEST=true" > "$WORK_WS/tests/padded-test.sh"

# State and git setup
cat > "$WORK_WS/.run-plan-state.json" << 'JSON_WS'
{"plan": "test-plan.md", "mode": "headless", "batches": {}}
JSON_WS
cd "$WORK_WS" && git init -q && git commit --allow-empty -m "init" -q
cd - > /dev/null

ctx_ws=$(generate_batch_context "$WORK_WS/test-plan.md" 2 "$WORK_WS")

assert_contains "whitespace-trimmed: padded.sh content included" "PADDED_CONTENT=true" "$ctx_ws"
assert_contains "whitespace-trimmed: padded-test.sh content included" "PADDED_TEST=true" "$ctx_ws"

# === Bug #50 BEHAVIORAL: non-readable progress.txt propagates error ===
# When progress.txt exists but has restricted permissions, the tail call should
# not silently swallow the error — stderr should show the permission denial.

WORK_PERM=$(mktemp -d)
trap 'rm -rf "$WORK_PERM"' EXIT

mkdir -p "$WORK_PERM/src"
cat > "$WORK_PERM/test-plan.md" << 'PLAN_PERM'
## Batch 1: Init
### Task 1: Do something
Do something.

## Batch 2: Next
### Task 2: Do more
Do more.
PLAN_PERM

cat > "$WORK_PERM/.run-plan-state.json" << 'JSON_PERM'
{"plan": "test-plan.md", "mode": "headless", "batches": {"1": {"passed": true, "test_count": 10, "duration": 30}}}
JSON_PERM

# Create an unreadable progress.txt (note: this only works when not root)
echo "some progress" > "$WORK_PERM/progress.txt"
chmod 000 "$WORK_PERM/progress.txt"

cd "$WORK_PERM" && git init -q && git commit --allow-empty -m "init" -q
cd - > /dev/null

# build_variable_suffix should produce stderr when progress.txt is unreadable
# (the fix removed || true, so tail's permission error is visible)
prompt_stderr=""
prompt_stderr=$(build_variable_suffix "$WORK_PERM/test-plan.md" 2 "$WORK_PERM" 10 2>&1 >/dev/null) || true

TESTS=$((TESTS + 1))
# Only check if we're not root (root can read anything)
if [[ "$(id -u)" -eq 0 ]]; then
    echo "PASS: (skipped — running as root, permission test not applicable)"
else
    if [[ -n "$prompt_stderr" ]]; then
        echo "PASS: unreadable progress.txt: error propagated to stderr"
    else
        echo "FAIL: unreadable progress.txt: error should propagate (not suppressed by || true)"
        FAILURES=$((FAILURES + 1))
    fi
fi

# Cleanup (restore permission before rm can work)
chmod 644 "$WORK_PERM/progress.txt" 2>/dev/null || true

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
