#!/usr/bin/env bash
# Test plan quality scorecard
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$SCRIPT_DIR/../validate-plan-quality.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc (expected: $expected, got: $actual)"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" != *"$needle"* ]]; then
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

# =============================================================================
# High-quality plan (should score >= 60)
# =============================================================================

HIGH_QUALITY="$TMPDIR_ROOT/high-quality.md"
cat > "$HIGH_QUALITY" << 'EOF'
# High Quality Plan

## Batch 1: Setup (Tasks 1-2)

### Task 1: Create Data Model

**Files:**
- Create: `src/models.py`
- Test: `tests/test_models.py`

**Step 1: Write the failing test**

Write `tests/test_models.py` with assertions that verify Model class works.

**Step 2: Implement**

Create `src/models.py` with the Model class.

### Task 2: Add Validation

**Files:**
- Modify: `src/models.py`

Add validation. Write test first, then implement. Should reject invalid input.

## Batch 2: Integration (Tasks 3-4)

### Task 3: Wire Components

**Files:**
- Create: `src/pipeline.py`
- Test: `tests/test_pipeline.py`

Connect parser to transformer. Verify end-to-end with test that checks output format.

### Task 4: CLI Entry Point

**Files:**
- Create: `src/cli.py`
- Test: `tests/test_cli.py`

Add CLI. Test argument parsing. Should handle missing file gracefully.
EOF

output=$(bash "$VALIDATE" "$HIGH_QUALITY" 2>&1)
exit_code=$?

assert_eq "high quality plan passes" "0" "$exit_code"
assert_contains "high quality shows PASSED" "PASSED" "$output"

# =============================================================================
# Low-quality plan (should score < 60 with low min-score threshold)
# =============================================================================

LOW_QUALITY="$TMPDIR_ROOT/low-quality.md"
cat > "$LOW_QUALITY" << 'EOF'
# Low Quality Plan

## Batch 1: Do Everything

Build the whole thing. Make it work. Deploy it.

## Batch 2: More Stuff

Do more stuff. Fix what broke in batch 1.
Depends on batch 3 being done first.

## Batch 3: Final Things

Finish everything. Clean up.
EOF

output=$(bash "$VALIDATE" "$LOW_QUALITY" 2>&1 || true)
# Low quality: no tasks, no files, no tests, forward ref in batch 2 → batch 3
assert_contains "low quality shows scores" "Scorecard" "$output"

# With min-score=90 this should definitely fail
exit_code=0
bash "$VALIDATE" "$LOW_QUALITY" --min-score 90 >/dev/null 2>&1 || exit_code=$?
assert_eq "low quality fails at min-score 90" "1" "$exit_code"

# =============================================================================
# JSON output mode
# =============================================================================

json_output=$(bash "$VALIDATE" "$HIGH_QUALITY" --json 2>&1)
assert_contains "json has score field" '"score"' "$json_output"
assert_contains "json has dimensions" '"dimensions"' "$json_output"
assert_contains "json has passed field" '"passed"' "$json_output"
assert_contains "json has task_granularity" '"task_granularity"' "$json_output"
assert_contains "json has weight" '"weight"' "$json_output"

# =============================================================================
# Error cases
# =============================================================================

# No file
exit_code=0
bash "$VALIDATE" 2>/dev/null || exit_code=$?
assert_eq "no file arg exits 1" "1" "$exit_code"

# Missing file
exit_code=0
bash "$VALIDATE" "$TMPDIR_ROOT/nonexistent.md" 2>/dev/null || exit_code=$?
assert_eq "missing file exits 1" "1" "$exit_code"

# File with no batches
NO_BATCHES="$TMPDIR_ROOT/no-batches.md"
echo "# Just a title" > "$NO_BATCHES"
exit_code=0
bash "$VALIDATE" "$NO_BATCHES" 2>/dev/null || exit_code=$?
assert_eq "no batches exits 1" "1" "$exit_code"

# =============================================================================
# Custom min-score
# =============================================================================

# High quality with min-score=101 should fail (max score is 100)
exit_code=0
bash "$VALIDATE" "$HIGH_QUALITY" --min-score 101 >/dev/null 2>&1 || exit_code=$?
assert_eq "min-score 101 is impossible to pass" "1" "$exit_code"

# High quality with min-score=1 should pass
exit_code=0
bash "$VALIDATE" "$HIGH_QUALITY" --min-score 1 >/dev/null 2>&1 || exit_code=$?
assert_eq "min-score 1 is easy to pass" "0" "$exit_code"

# =============================================================================
# Dimension-specific tests
# =============================================================================

# Forward dependency reference
FORWARD_REF="$TMPDIR_ROOT/forward-ref.md"
cat > "$FORWARD_REF" << 'EOF'
# Forward Reference Plan

## Batch 1: First

### Task 1: Setup

**Files:**
- Create: `src/setup.py`

This task needs batch 2 to be done first. Check tests pass.

## Batch 2: Second

### Task 2: Build

**Files:**
- Create: `src/build.py`

Build the thing. Verify it works.
EOF

json=$(bash "$VALIDATE" "$FORWARD_REF" --json 2>&1)
dep_score=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['dimensions']['dependency_ordering']['score'])")
assert_eq "forward ref lowers dependency score" "50" "$dep_score"

# Oversized batch (> 5 tasks)
BIG_BATCH="$TMPDIR_ROOT/big-batch.md"
cat > "$BIG_BATCH" << 'EOF'
# Big Batch Plan

## Batch 1: Everything

### Task 1: A
Do A. Check it works.
### Task 2: B
Do B. Verify output.
### Task 3: C
Do C. Test the result.
### Task 4: D
Do D. Assert correctness.
### Task 5: E
Do E. Should pass all tests.
### Task 6: F
Do F. Confirm it works.
### Task 7: G
Do G. Must be correct.
EOF

json=$(bash "$VALIDATE" "$BIG_BATCH" --json 2>&1)
size_score=$(echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['dimensions']['batch_size']['score'])")
assert_eq "oversized batch gets 0 on batch_size" "0" "$size_score"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
