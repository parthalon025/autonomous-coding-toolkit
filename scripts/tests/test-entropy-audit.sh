#!/usr/bin/env bash
# Test entropy-audit.sh — verifies refactored behavior
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EA="$SCRIPT_DIR/../entropy-audit.sh"

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
        FAILURES=$((FAILURES + 1))
    fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# === Sources common.sh ===

TESTS=$((TESTS + 1))
if grep -q 'source.*lib/common.sh' "$EA"; then
    echo "PASS: entropy-audit.sh sources lib/common.sh"
else
    echo "FAIL: entropy-audit.sh sources lib/common.sh"
    FAILURES=$((FAILURES + 1))
fi

# === No hardcoded $HOME/Documents/projects ===

TESTS=$((TESTS + 1))
if grep -q 'PROJECTS_DIR="\$HOME/Documents/projects"' "$EA"; then
    echo "FAIL: still has hardcoded PROJECTS_DIR"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: no hardcoded PROJECTS_DIR"
fi

# === Accepts --projects-dir argument ===

TESTS=$((TESTS + 1))
if grep -q '\-\-projects-dir' "$EA"; then
    echo "PASS: accepts --projects-dir argument"
else
    echo "FAIL: should accept --projects-dir argument"
    FAILURES=$((FAILURES + 1))
fi

# === Uses env var with default ===

TESTS=$((TESTS + 1))
if grep -qE 'PROJECTS_DIR="\$\{PROJECTS_DIR:-' "$EA"; then
    echo "PASS: uses PROJECTS_DIR env var with default"
else
    echo "FAIL: should use PROJECTS_DIR env var with default"
    FAILURES=$((FAILURES + 1))
fi

# === CLI tests ===

assert_exit "--help exits 0" 0 bash "$EA" --help

# === --projects-dir overrides default ===

mkdir -p "$WORK/test-proj/.git"
echo "# Test" > "$WORK/test-proj/CLAUDE.md"
output=$(bash "$EA" --projects-dir "$WORK" --project test-proj 2>&1) || true
assert_contains "custom projects-dir used" "Auditing test-proj" "$output"

# === PROJECTS_DIR env var works ===

output=$(PROJECTS_DIR="$WORK" bash "$EA" --project test-proj 2>&1) || true
assert_contains "env var PROJECTS_DIR works" "Auditing test-proj" "$output"

# === Empty find produces zero iterations (bug #13) ===
# Create a project with no code files — only a CLAUDE.md
mkdir -p "$WORK/empty-proj"
echo "# Empty project" > "$WORK/empty-proj/CLAUDE.md"
bash "$EA" --projects-dir "$WORK" --project empty-proj 2>&1 || true
# Find the report file (audit writes to a timestamped dir)
report=$(ls -t /tmp/entropy-audit-*/empty-proj.md 2>/dev/null | head -1)
TESTS=$((TESTS + 1))
if [[ -z "$report" ]]; then
    echo "FAIL: empty find: no report file generated"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: empty find: report file generated"
    report_content=$(cat "$report")
    # Should report "All files within limit" (zero violations, zero iterations)
    assert_contains "empty find: no size violations" "All files within limit" "$report_content"
    # Should NOT contain any file-specific warnings (phantom iteration would produce one)
    TESTS=$((TESTS + 1))
    if echo "$report_content" | grep -qE '⚠️.*lines$'; then
        echo "FAIL: empty find produced phantom file size warning"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: empty find: no phantom file size warnings"
    fi
    # Naming check should also report clean
    assert_contains "empty find: no naming drift" "No naming drift detected" "$report_content"
fi

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
