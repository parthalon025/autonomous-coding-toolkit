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
trap 'rm -rf "$WORK"' EXIT

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
trap 'rm -rf "$WORK" "$WORK2"' EXIT
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

# --- Test: complete_batch stores duration ---
WORK3=$(mktemp -d)
trap 'rm -rf "$WORK" "$WORK2" "$WORK3"' EXIT
init_state "$WORK3" "plan.md" "headless"
complete_batch "$WORK3" 1 42 120

duration=$(jq -r '.durations["1"]' "$WORK3/.run-plan-state.json")
assert_eq "complete_batch: stores duration" "120" "$duration"

# --- Test: duration defaults to 0 when not provided ---
complete_batch "$WORK3" 2 55
duration=$(jq -r '.durations["2"]' "$WORK3/.run-plan-state.json")
assert_eq "complete_batch: duration defaults to 0" "0" "$duration"

# --- Test: init_state includes durations object ---
val=$(jq -r '.durations | type' "$WORK3/.run-plan-state.json")
assert_eq "init_state: has durations object" "object" "$val"

# --- Test: complete_batch with non-numeric batch_num ('final') ---
WORK4=$(mktemp -d)
trap 'rm -rf "$WORK" "$WORK2" "$WORK3" "$WORK4"' EXIT
init_state "$WORK4" "plan.md" "headless"
complete_batch "$WORK4" 1 42
complete_batch "$WORK4" "final" 50

val=$(jq -r '.test_counts["final"]' "$WORK4/.run-plan-state.json")
assert_eq "complete_batch: non-numeric batch 'final' stores test count" "50" "$val"

val=$(jq -r '.durations["final"]' "$WORK4/.run-plan-state.json")
assert_eq "complete_batch: non-numeric batch 'final' stores duration" "0" "$val"

val=$(jq -r '.completed_batches | last' "$WORK4/.run-plan-state.json")
assert_eq "complete_batch: non-numeric batch 'final' in completed_batches" "final" "$val"

# Numeric batches still work after non-numeric
val=$(jq -r '.test_counts["1"]' "$WORK4/.run-plan-state.json")
assert_eq "complete_batch: numeric batch still intact after non-numeric" "42" "$val"

# --- Test: get_previous_test_count returns -1 when key missing ---
WORK5=$(mktemp -d)
trap 'rm -rf "$WORK" "$WORK2" "$WORK3" "$WORK4" "$WORK5"' EXIT
init_state "$WORK5" "plan.md" "headless"
# Manually add a batch to completed_batches without a corresponding test_count entry
jq '.completed_batches += [1]' "$WORK5/.run-plan-state.json" > "$WORK5/.tmp.json" && mv "$WORK5/.tmp.json" "$WORK5/.run-plan-state.json"

val=$(get_previous_test_count "$WORK5")
assert_eq "get_previous_test_count: returns -1 when key missing" "-1" "$val"

# --- Test: set_quality_gate with non-numeric batch_num ('final') ---
WORK6=$(mktemp -d)
trap 'rm -rf "$WORK" "$WORK2" "$WORK3" "$WORK4" "$WORK5" "$WORK6"' EXIT
init_state "$WORK6" "plan.md" "headless"
complete_batch "$WORK6" 1 42
set_quality_gate "$WORK6" "final" "true" 99

val=$(jq -r '.last_quality_gate.batch' "$WORK6/.run-plan-state.json")
assert_eq "set_quality_gate: non-numeric batch 'final' stored" "final" "$val"

val=$(jq -r '.last_quality_gate.passed' "$WORK6/.run-plan-state.json")
assert_eq "set_quality_gate: non-numeric batch passed=true" "true" "$val"

val=$(jq -r '.last_quality_gate.test_count' "$WORK6/.run-plan-state.json")
assert_eq "set_quality_gate: non-numeric batch test_count" "99" "$val"

# --- Test: end-to-end complete_batch 'final' then get_previous_test_count ---
WORK7=$(mktemp -d)
trap 'rm -rf "$WORK" "$WORK2" "$WORK3" "$WORK4" "$WORK5" "$WORK6" "$WORK7"' EXIT
init_state "$WORK7" "plan.md" "headless"
complete_batch "$WORK7" 1 42
complete_batch "$WORK7" "final" 99

val=$(get_previous_test_count "$WORK7")
assert_eq "e2e: complete_batch 'final' then get_previous_test_count returns 99" "99" "$val"

# --- Test: init_state includes costs object ---
WORK_COST=$(mktemp -d)
trap 'rm -rf "$WORK" "$WORK2" "$WORK3" "$WORK4" "$WORK5" "$WORK6" "$WORK7" "$WORK_COST"' EXIT
init_state "$WORK_COST" "plan.md" "headless"

val=$(jq -r '.costs | type' "$WORK_COST/.run-plan-state.json")
assert_eq "init_state: has costs object" "object" "$val"

val=$(jq -r '.total_cost_usd' "$WORK_COST/.run-plan-state.json")
assert_eq "init_state: total_cost_usd starts at 0" "0" "$val"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
