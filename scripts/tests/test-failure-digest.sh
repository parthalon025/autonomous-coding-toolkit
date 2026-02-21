#!/usr/bin/env bash
# Test failure-digest.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIGEST_SCRIPT="$SCRIPT_DIR/../failure-digest.sh"

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

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create a fake log with errors
cat > "$WORK/batch-1-attempt-1.log" << 'LOG'
Some setup output...
FAILED tests/test_auth.py::test_login - AssertionError: expected 200 got 401
FAILED tests/test_auth.py::test_signup - KeyError: 'email'
Traceback (most recent call last):
  File "src/auth.py", line 42, in login
    token = generate_token(user)
TypeError: generate_token() missing 1 required argument: 'secret'
3 failed, 10 passed in 5.2s
LOG

# --- Test: extracts failed test names ---
output=$(bash "$DIGEST_SCRIPT" "$WORK/batch-1-attempt-1.log")
echo "$output" | grep -q "test_login" && echo "PASS: found test_login" && TESTS=$((TESTS + 1)) || {
    echo "FAIL: missing test_login"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1))
}

echo "$output" | grep -q "test_signup" && echo "PASS: found test_signup" && TESTS=$((TESTS + 1)) || {
    echo "FAIL: missing test_signup"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1))
}

# --- Test: extracts error types ---
echo "$output" | grep -q "TypeError" && echo "PASS: found TypeError" && TESTS=$((TESTS + 1)) || {
    echo "FAIL: missing TypeError"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1))
}

# --- Test: help flag ---
bash "$DIGEST_SCRIPT" --help >/dev/null 2>&1
TESTS=$((TESTS + 1))
echo "PASS: --help exits cleanly"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
