#!/usr/bin/env bash
# Test auto-compound.sh — verifies refactored behavior using common.sh/ollama.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AC="$SCRIPT_DIR/../auto-compound.sh"

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

# === Sources shared libraries ===

TESTS=$((TESTS + 1))
if grep -q 'source.*lib/common.sh' "$AC"; then
    echo "PASS: auto-compound.sh sources lib/common.sh"
else
    echo "FAIL: auto-compound.sh sources lib/common.sh"
    FAILURES=$((FAILURES + 1))
fi

TESTS=$((TESTS + 1))
if grep -q 'source.*lib/ollama.sh' "$AC"; then
    echo "PASS: auto-compound.sh sources lib/ollama.sh"
else
    echo "FAIL: auto-compound.sh sources lib/ollama.sh"
    FAILURES=$((FAILURES + 1))
fi

# === CLI tests ===

assert_exit "no args exits 1" 1 bash "$AC"
assert_exit "--help exits 0" 0 bash "$AC" /dev/null --help

# === No silent PRD discard (lesson-7) ===
# The old line was: > /dev/null 2>&1 || true (discard all output)
# New code should capture output and log errors

TESTS=$((TESTS + 1))
if grep -q '> /dev/null 2>&1 || true' "$AC"; then
    echo "FAIL: PRD output still silently discarded (lesson-7 violation)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: PRD output not silently discarded"
fi

# === Uses detect_project_type in fallback ===

TESTS=$((TESTS + 1))
if grep -q 'detect_project_type' "$AC"; then
    echo "PASS: uses detect_project_type for fallback detection"
else
    echo "FAIL: should use detect_project_type for fallback detection"
    FAILURES=$((FAILURES + 1))
fi

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
