#!/usr/bin/env bash
# Test quality gate runner helper functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-quality-gate.sh"

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
    "$@" || actual_exit=$?
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

# --- Temp dir for git repo simulation ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# =============================================================================
# extract_test_count tests
# =============================================================================

# --- Test: extract passed count with skipped ---
val=$(extract_test_count "1953 passed, 15 skipped in 45.2s")
assert_eq "extract_test_count: passed with skipped" "1953" "$val"

# --- Test: extract passed count without skipped ---
val=$(extract_test_count "42 passed in 2.1s")
assert_eq "extract_test_count: passed without skipped" "42" "$val"

# --- Test: extract from no tests ran ---
val=$(extract_test_count "ERROR: no tests ran")
assert_eq "extract_test_count: no tests ran" "-1" "$val"

# --- Test: extract from empty string ---
val=$(extract_test_count "")
assert_eq "extract_test_count: empty string" "-1" "$val"

# --- Test: extract from multi-line pytest output ---
output="============================= test session starts ==============================
collected 87 items

tests/test_foo.py ........ [  9%]
tests/test_bar.py ........ [ 18%]

============================== 87 passed in 12.34s ==============================="
val=$(extract_test_count "$output")
assert_eq "extract_test_count: full pytest output" "87" "$val"

# --- Test: extract with failures in output ---
output="3 failed, 85 passed, 2 skipped in 30.1s"
val=$(extract_test_count "$output")
assert_eq "extract_test_count: with failures" "85" "$val"

# --- Test: extract from jest output ---
output="Tests:       3 failed, 45 passed, 48 total"
val=$(extract_test_count "$output")
assert_eq "extract_test_count: jest output" "45" "$val"

# --- Test: extract from jest all-pass output ---
output="Tests:       12 passed, 12 total"
val=$(extract_test_count "$output")
assert_eq "extract_test_count: jest all-pass" "12" "$val"

# --- Test: extract from go test output ---
output="ok  	github.com/foo/bar	0.123s
ok  	github.com/foo/baz	0.456s
FAIL	github.com/foo/qux	0.789s"
val=$(extract_test_count "$output")
assert_eq "extract_test_count: go test (2 ok of 3)" "2" "$val"

# --- Test: unrecognized format returns -1 ---
val=$(extract_test_count "Some random build output with no test results")
assert_eq "extract_test_count: unrecognized format" "-1" "$val"

# =============================================================================
# check_test_count_regression tests
# =============================================================================

# --- Test: no regression (increase) ---
assert_exit "check_test_count_regression: 200 >= 150 passes" 0 \
    check_test_count_regression 200 150

# --- Test: no regression (equal) ---
assert_exit "check_test_count_regression: 150 >= 150 passes" 0 \
    check_test_count_regression 150 150

# --- Test: regression detected ---
assert_exit "check_test_count_regression: 100 < 150 fails" 1 \
    check_test_count_regression 100 150

# --- Test: no regression from zero baseline ---
assert_exit "check_test_count_regression: 50 >= 0 passes" 0 \
    check_test_count_regression 50 0

# =============================================================================
# check_git_clean tests
# =============================================================================

# --- Setup: create a temp git repo ---
git -C "$WORK" init -q
git -C "$WORK" config user.email "test@test.com"
git -C "$WORK" config user.name "Test"
echo "initial" > "$WORK/file.txt"
git -C "$WORK" add file.txt
git -C "$WORK" commit -q -m "initial"

# --- Test: clean repo passes ---
assert_exit "check_git_clean: clean repo passes" 0 \
    check_git_clean "$WORK"

# --- Test: dirty repo (untracked file) fails ---
echo "dirty" > "$WORK/untracked.txt"
assert_exit "check_git_clean: untracked file fails" 1 \
    check_git_clean "$WORK"

# --- Test: dirty repo (modified file) fails ---
rm "$WORK/untracked.txt"
echo "modified" >> "$WORK/file.txt"
assert_exit "check_git_clean: modified file fails" 1 \
    check_git_clean "$WORK"

# --- Test: -1 skips regression check ---
assert_exit "check_test_count_regression: -1 new skips check" 0 \
    check_test_count_regression -1 150

assert_exit "check_test_count_regression: -1 previous skips check" 0 \
    check_test_count_regression 50 -1

# Clean up for any subsequent tests
git -C "$WORK" checkout -- file.txt

# =============================================================================
# Security: no eval in quality gate runner (#3)
# =============================================================================

TESTS=$((TESTS + 1))
QG_FILE="$SCRIPT_DIR/../lib/run-plan-quality-gate.sh"
if grep -q 'eval.*quality_gate_cmd\|eval.*\$quality_gate' "$QG_FILE"; then
    echo "FAIL: run-plan-quality-gate.sh uses eval on quality_gate_cmd (command injection risk, bug #3)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: run-plan-quality-gate.sh does not use eval on quality_gate_cmd"
fi

TESTS=$((TESTS + 1))
if grep -q 'bash -c.*quality_gate_cmd\|bash -c.*\$quality_gate' "$QG_FILE"; then
    echo "PASS: run-plan-quality-gate.sh uses bash -c instead of eval"
else
    echo "FAIL: run-plan-quality-gate.sh should use bash -c instead of eval (bug #3)"
    FAILURES=$((FAILURES + 1))
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
