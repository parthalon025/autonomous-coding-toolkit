#!/usr/bin/env bash
# Test license-check.sh — verifies CLI, project detection, and license scanning
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LC="$SCRIPT_DIR/../license-check.sh"

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

WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT

# === CLI tests ===

assert_exit "--help exits 0" 0 bash "$LC" --help
assert_exit "unknown flag exits 1" 1 bash "$LC" --bogus

# === Help text ===

output=$(bash "$LC" --help 2>&1)
assert_contains "help mentions license" "license" "$output"

# === Sources common.sh ===

TESTS=$((TESTS + 1))
if grep -q 'source.*lib/common.sh' "$LC"; then
    echo "PASS: license-check.sh sources lib/common.sh"
else
    echo "FAIL: license-check.sh sources lib/common.sh"
    FAILURES=$((FAILURES + 1))
fi

# === Unknown project type exits clean ===

mkdir -p "$WORK/empty-proj"
output=$(bash "$LC" --project-root "$WORK/empty-proj" 2>&1)
exit_code=$?
assert_eq "unknown project exits 0" "0" "$exit_code"
assert_contains "unknown project says CLEAN" "CLEAN" "$output"
assert_contains "shows License Check header" "License Check" "$output"

# === Python project without pip-licenses skips gracefully ===

mkdir -p "$WORK/py-proj"
touch "$WORK/py-proj/pyproject.toml"
output=$(bash "$LC" --project-root "$WORK/py-proj" 2>&1)
exit_code=$?
assert_eq "python without pip-licenses exits 0" "0" "$exit_code"
assert_contains "python skip message" "skipping" "$output"

# === Node project without npx skips gracefully ===
# (npx is likely available, so test the output structure instead)

mkdir -p "$WORK/node-proj"
echo '{"name":"test"}' > "$WORK/node-proj/package.json"
output=$(bash "$LC" --project-root "$WORK/node-proj" 2>&1) || true
assert_contains "node project checks deps" "Node dependencies" "$output"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
