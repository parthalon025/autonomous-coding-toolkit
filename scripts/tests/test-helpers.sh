#!/usr/bin/env bash
# test-helpers.sh — Shared test assertions for validator tests
# Source this file, don't execute it directly.

FAILURES=0
TESTS=0

pass() {
    TESTS=$((TESTS + 1))
    echo "PASS: $1"
}

fail() {
    TESTS=$((TESTS + 1))
    echo "FAIL: $1"
    FAILURES=$((FAILURES + 1))
}

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
