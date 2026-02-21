#!/usr/bin/env bash
# Test prior-art-search.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_SCRIPT="$SCRIPT_DIR/../prior-art-search.sh"

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

# --- Test: --help exits 0 ---
assert_exit "prior-art-search --help exits 0" 0 \
    bash "$SEARCH_SCRIPT" --help

# --- Test: --dry-run produces output without calling gh ---
output=$(bash "$SEARCH_SCRIPT" --dry-run "implement webhook handler" 2>&1)
echo "$output" | grep -q "Search query:" && TESTS=$((TESTS + 1)) && echo "PASS: dry-run shows search query" || {
    TESTS=$((TESTS + 1)); echo "FAIL: dry-run missing search query"; FAILURES=$((FAILURES + 1))
}

# --- Test: dry-run shows what would be searched ---
TESTS=$((TESTS + 1))
if echo "$output" | grep -q "Would search:"; then
    echo "PASS: dry-run shows would-search list"
else
    echo "FAIL: dry-run shows would-search list"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: --dry-run exits 0 ---
assert_exit "prior-art-search --dry-run exits 0" 0 \
    bash "$SEARCH_SCRIPT" --dry-run "test query"

# --- Test: missing query shows usage ---
assert_exit "prior-art-search: no args exits 1" 1 \
    bash "$SEARCH_SCRIPT"

# --- Test: --local-only flag accepted ---
assert_exit "prior-art-search --local-only --dry-run exits 0" 0 \
    bash "$SEARCH_SCRIPT" --local-only --dry-run "test query"

# --- Test: --github-only flag accepted ---
assert_exit "prior-art-search --github-only --dry-run exits 0" 0 \
    bash "$SEARCH_SCRIPT" --github-only --dry-run "test query"

# --- Test: unknown option exits 1 ---
assert_exit "prior-art-search: unknown option exits 1" 1 \
    bash "$SEARCH_SCRIPT" --bogus-flag

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
