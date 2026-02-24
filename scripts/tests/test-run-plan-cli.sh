#!/usr/bin/env bash
# Test run-plan.sh CLI argument parsing and validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_PLAN="$SCRIPT_DIR/../run-plan.sh"

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
assert_exit "--help exits 0" 0 "$RUN_PLAN" --help

# --- Test: -h exits 0 ---
assert_exit "-h exits 0" 0 "$RUN_PLAN" -h

# --- Test: no args exits 1 ---
assert_exit "no args exits 1" 1 "$RUN_PLAN"

# --- Test: nonexistent plan file exits 1 ---
assert_exit "nonexistent plan exits 1" 1 "$RUN_PLAN" /tmp/nonexistent-plan-file-abc123.md

# --- Test: help output mentions run-plan ---
assert_output_contains "help mentions run-plan" "run-plan" "$RUN_PLAN" --help

# --- Test: help output mentions --mode ---
assert_output_contains "help mentions --mode" "--mode" "$RUN_PLAN" --help

# --- Test: help output mentions headless ---
assert_output_contains "help mentions headless" "headless" "$RUN_PLAN" --help

# --- Test: help output mentions --resume ---
assert_output_contains "help mentions --resume" "--resume" "$RUN_PLAN" --help

# --- Test: help output mentions --on-failure ---
assert_output_contains "help mentions --on-failure" "--on-failure" "$RUN_PLAN" --help

# --- Test: help output mentions --mab ---
assert_output_contains "help mentions --mab" "--mab" "$RUN_PLAN" --help

# --- Test: --resume without state file exits 1 ---
TMPDIR_RESUME=$(mktemp -d)
trap 'rm -rf "$TMPDIR_RESUME"' EXIT
assert_exit "--resume without state file exits 1" 1 "$RUN_PLAN" --resume --worktree "$TMPDIR_RESUME"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
