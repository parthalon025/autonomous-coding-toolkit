#!/usr/bin/env bash
# Test state manager functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-state.sh"

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

# --- Temp dir for worktree simulation ---
WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT

# --- Test: init_state creates the file ---
init_state "$WORK" "docs/plans/2026-02-20-feature.md" "headless"

TESTS=$((TESTS + 1))
if [[ -f "$WORK/.run-plan-state.json" ]]; then
    echo "PASS: init_state creates state file"
else
    echo "FAIL: init_state should create .run-plan-state.json"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: read_state_field reads plan_file ---
val=$(read_state_field "$WORK" "plan_file")
assert_eq "read plan_file" "docs/plans/2026-02-20-feature.md" "$val"

# --- Test: read_state_field reads mode ---
val=$(read_state_field "$WORK" "mode")
assert_eq "read mode" "headless" "$val"

# --- Test: read_state_field reads current_batch ---
val=$(read_state_field "$WORK" "current_batch")
assert_eq "read current_batch (initial)" "1" "$val"

# --- Test: read_state_field reads started_at ---
val=$(read_state_field "$WORK" "started_at")
TESTS=$((TESTS + 1))
if [[ -n "$val" && "$val" != "null" ]]; then
    echo "PASS: started_at is set"
else
    echo "FAIL: started_at should be a non-null timestamp"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: completed_batches starts empty ---
val=$(read_state_field "$WORK" "completed_batches")
assert_eq "completed_batches starts empty" "[]" "$val"

# --- Test: last_quality_gate starts null ---
val=$(read_state_field "$WORK" "last_quality_gate")
assert_eq "last_quality_gate starts null" "null" "$val"

# --- Test: complete_batch updates state ---
complete_batch "$WORK" 1 42

val=$(read_state_field "$WORK" "current_batch")
assert_eq "current_batch after completing batch 1" "2" "$val"

val=$(read_state_field "$WORK" "completed_batches")
assert_eq "completed_batches has batch 1" "[1]" "$val"

val=$(jq -r '.test_counts["1"]' "$WORK/.run-plan-state.json")
assert_eq "test_count for batch 1" "42" "$val"

# --- Test: multiple complete_batch calls accumulate ---
complete_batch "$WORK" 2 55

val=$(read_state_field "$WORK" "current_batch")
assert_eq "current_batch after completing batch 2" "3" "$val"

val=$(read_state_field "$WORK" "completed_batches")
assert_eq "completed_batches has both" "[1,2]" "$val"

val=$(jq -r '.test_counts["2"]' "$WORK/.run-plan-state.json")
assert_eq "test_count for batch 2" "55" "$val"

# Previous batch 1 count still there
val=$(jq -r '.test_counts["1"]' "$WORK/.run-plan-state.json")
assert_eq "test_count for batch 1 still intact" "42" "$val"

# --- Test: get_previous_test_count ---
val=$(get_previous_test_count "$WORK")
assert_eq "previous test count after batch 2" "55" "$val"

# --- Test: get_previous_test_count with no completions ---
WORK2=$(mktemp -d)
trap "rm -rf '$WORK' '$WORK2'" EXIT
init_state "$WORK2" "plan.md" "team"

val=$(get_previous_test_count "$WORK2")
assert_eq "previous test count with no completions" "0" "$val"

# --- Test: set_quality_gate ---
set_quality_gate "$WORK" 2 "true" 55

val=$(jq -r '.last_quality_gate.batch' "$WORK/.run-plan-state.json")
assert_eq "quality gate batch" "2" "$val"

val=$(jq -r '.last_quality_gate.passed' "$WORK/.run-plan-state.json")
assert_eq "quality gate passed" "true" "$val"

val=$(jq -r '.last_quality_gate.test_count' "$WORK/.run-plan-state.json")
assert_eq "quality gate test_count" "55" "$val"

# Verify timestamp exists
val=$(jq -r '.last_quality_gate.timestamp' "$WORK/.run-plan-state.json")
TESTS=$((TESTS + 1))
if [[ -n "$val" && "$val" != "null" ]]; then
    echo "PASS: quality gate has timestamp"
else
    echo "FAIL: quality gate should have timestamp"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: set_quality_gate with failed gate ---
set_quality_gate "$WORK" 3 "false" 50

val=$(jq -r '.last_quality_gate.batch' "$WORK/.run-plan-state.json")
assert_eq "failed quality gate batch" "3" "$val"

val=$(jq -r '.last_quality_gate.passed' "$WORK/.run-plan-state.json")
assert_eq "failed quality gate passed" "false" "$val"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
