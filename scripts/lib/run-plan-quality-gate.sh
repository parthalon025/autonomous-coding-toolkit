#!/usr/bin/env bash
# run-plan-quality-gate.sh — Quality gate runner for plan execution
#
# Wraps quality-gate.sh with test count regression detection + git status check.
# Runs between every batch in all modes.
#
# Functions:
#   extract_test_count <test_output>                          -> parse "N passed" from pytest output
#   check_test_count_regression <new_count> <previous_count>  -> 0 if new >= previous, 1 otherwise
#   check_git_clean <worktree>                                -> 0 if clean, 1 if dirty
#   run_quality_gate <worktree> <quality_gate_cmd> <batch_num> -> full gate: cmd + regression + clean + state update
#
# Requires: run-plan-state.sh sourced for run_quality_gate (state functions)

QUALITY_GATE_SCRIPT="${QUALITY_GATE_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../quality-gate.sh}"

# Extract passed test count from pytest output.
# Parses "N passed" pattern. Returns 0 if no match.
extract_test_count() {
    local output="$1"
    local count
    # Match "N passed" — handles "85 passed" in lines like "3 failed, 85 passed, 2 skipped in 30.1s"
    count=$(echo "$output" | grep -oP '\b(\d+) passed\b' | tail -1 | grep -oP '^\d+' || true)
    if [[ -n "$count" ]]; then
        echo "$count"
    else
        echo "0"
    fi
}

# Check for test count regression.
# Returns 0 if new_count >= previous_count, 1 otherwise.
check_test_count_regression() {
    local new_count="$1" previous_count="$2"
    if [[ "$new_count" -ge "$previous_count" ]]; then
        return 0
    else
        echo "WARNING: Test count regression: $new_count < $previous_count (previous)" >&2
        return 1
    fi
}

# Check if worktree has uncommitted changes.
# Returns 0 if clean, 1 if dirty.
check_git_clean() {
    local worktree="$1"
    local status
    status=$(git -C "$worktree" status --porcelain 2>/dev/null)
    if [[ -z "$status" ]]; then
        return 0
    else
        echo "WARNING: Worktree has uncommitted changes:" >&2
        echo "$status" >&2
        return 1
    fi
}

# Run the full quality gate for a batch.
# Executes quality_gate_cmd, checks test regression, checks git clean, updates state.
# Returns 0 on pass, 1 on fail.
#
# Requires run-plan-state.sh functions: get_previous_test_count, complete_batch, set_quality_gate
run_quality_gate() {
    local worktree="$1" quality_gate_cmd="$2" batch_num="$3"
    local gate_output gate_exit test_count previous_count passed

    echo "=== Quality Gate: Batch $batch_num ==="

    # 1. Execute quality gate command in worktree
    gate_output=$(cd "$worktree" && eval "$quality_gate_cmd" 2>&1) && gate_exit=0 || gate_exit=$?
    echo "$gate_output"

    if [[ $gate_exit -ne 0 ]]; then
        echo ""
        echo "QUALITY GATE FAILED: command exited $gate_exit"
        set_quality_gate "$worktree" "$batch_num" "false" 0
        return 1
    fi

    # 2. Extract test count from output
    test_count=$(extract_test_count "$gate_output")
    echo "Test count: $test_count"

    # 3. Compare against previous batch count
    previous_count=$(get_previous_test_count "$worktree")
    if ! check_test_count_regression "$test_count" "$previous_count"; then
        echo "QUALITY GATE FAILED: test count regression ($test_count < $previous_count)"
        set_quality_gate "$worktree" "$batch_num" "false" "$test_count"
        return 1
    fi

    # 4. Check git clean
    if ! check_git_clean "$worktree"; then
        echo "QUALITY GATE FAILED: uncommitted changes in worktree"
        set_quality_gate "$worktree" "$batch_num" "false" "$test_count"
        return 1
    fi

    # 5. Update state — batch complete, gate passed
    complete_batch "$worktree" "$batch_num" "$test_count"
    set_quality_gate "$worktree" "$batch_num" "true" "$test_count"

    echo "QUALITY GATE PASSED (batch $batch_num, $test_count tests)"
    return 0
}
