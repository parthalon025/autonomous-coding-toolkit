#!/usr/bin/env bash
# Test quality-gate.sh — verifies refactored behavior using common.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QG="$SCRIPT_DIR/../quality-gate.sh"

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

assert_exit "no args exits 1" 1 bash "$QG"
assert_exit "--help exits 0" 0 bash "$QG" --help
assert_exit "nonexistent dir exits 1" 1 bash "$QG" --project-root /nonexistent/path

# === Sources common.sh ===

# Check that the script sources common.sh (grep for the source line)
TESTS=$((TESTS + 1))
if grep -q 'source.*lib/common.sh' "$QG"; then
    echo "PASS: quality-gate.sh sources lib/common.sh"
else
    echo "FAIL: quality-gate.sh sources lib/common.sh"
    echo "  expected: source line for lib/common.sh"
    FAILURES=$((FAILURES + 1))
fi

# === Python project detection via detect_project_type ===

# Create a minimal Python project with no actual test suite
# (so the test suite step will run but fail — we just care about detection)
mkdir -p "$WORK/py-proj"
touch "$WORK/py-proj/pyproject.toml"
# Create a fake .venv/bin/python that exits 0
mkdir -p "$WORK/py-proj/.venv/bin"
cat > "$WORK/py-proj/.venv/bin/python" <<'FAKE'
#!/bin/bash
echo "1 passed"
exit 0
FAKE
chmod +x "$WORK/py-proj/.venv/bin/python"

# Run quality-gate on the python project — lesson-check will be skipped (no git)
output=$(bash "$QG" --project-root "$WORK/py-proj" 2>&1) || true
assert_contains "detects pytest project" "Detected: pytest project" "$output"

# === Node project detection ===

mkdir -p "$WORK/node-proj"
echo '{"name":"test","scripts":{"test":"echo ok"}}' > "$WORK/node-proj/package.json"
output=$(bash "$QG" --project-root "$WORK/node-proj" 2>&1) || true
assert_contains "detects npm project" "Detected: npm project" "$output"

# === Lint check output (Python project with ruff) ===

output=$(bash "$QG" --project-root "$WORK/py-proj" 2>&1) || true
assert_contains "lint check section present" "Lint Check" "$output"

# === Lint check output (Node project — no eslint config → skipped) ===

output=$(bash "$QG" --project-root "$WORK/node-proj" 2>&1) || true
assert_contains "node lint skipped without config" "No eslint config found" "$output"

# === Memory check output ===

output=$(bash "$QG" --project-root "$WORK/py-proj" 2>&1) || true
# Should contain either "Memory OK" or "WARNING: Low memory"
TESTS=$((TESTS + 1))
if echo "$output" | grep -qE "(Memory OK|WARNING.*memory|WARNING.*Consider)"; then
    echo "PASS: memory check runs"
else
    echo "FAIL: memory check runs"
    echo "  expected memory check output"
    echo "  got: $output"
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
