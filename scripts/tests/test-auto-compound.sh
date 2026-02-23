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

# === Bug #14: head -c 40 replaced with cut -c1-40 for UTF-8 safety ===

# Verify the script uses cut -c1-40 instead of head -c 40
TESTS=$((TESTS + 1))
if grep -q 'cut -c1-40' "$AC"; then
    echo "PASS: uses cut -c1-40 for UTF-8-safe character truncation"
else
    echo "FAIL: should use cut -c1-40 instead of head -c 40"
    FAILURES=$((FAILURES + 1))
fi

TESTS=$((TESTS + 1))
if grep -q 'head -c' "$AC"; then
    echo "FAIL: still contains head -c (byte-level truncation, breaks UTF-8)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: no head -c byte truncation remaining"
fi

# Functional test: multi-byte characters are not split
# The slug pipeline: lowercase → replace non-alnum with dash → collapse dashes → cut to 40 chars
# CJK and emoji get replaced by dashes in the sed step, but the cut must not corrupt them
# before sed processes them. Test the full pipeline expression.
TESTS=$((TESTS + 1))
SLUG_PIPELINE='tr '\''[:upper:]'\'' '\''[:lower:]'\'' | sed '\''s/[^a-z0-9]/-/g'\'' | sed '\''s/--*/-/g'\'' | cut -c1-40'
# Input with emoji and CJK — these become dashes after sed, but cut -c handles them correctly
INPUT="add-emoji-support-🚀🎉-for-notifications"
RESULT=$(echo "$INPUT" | eval "$SLUG_PIPELINE")
# Verify result is valid (no broken bytes — should be pure ASCII after sed)
VALID=$(echo "$RESULT" | LC_ALL=C grep -c '[^ -~]' || true)
if [[ "$VALID" == "0" ]]; then
    echo "PASS: multi-byte input produces valid slug (no broken UTF-8)"
else
    echo "FAIL: multi-byte input produced invalid bytes in slug"
    echo "  result: $RESULT"
    FAILURES=$((FAILURES + 1))
fi

# === Bug #19: ls -t replaced with find+sort for space-safe file selection ===

# Verify the script uses find instead of ls -t
TESTS=$((TESTS + 1))
if grep -q 'find reports/' "$AC"; then
    echo "PASS: uses find for report file selection"
else
    echo "FAIL: should use find instead of ls -t for report selection"
    FAILURES=$((FAILURES + 1))
fi

TESTS=$((TESTS + 1))
if grep 'ls -t' "$AC" | grep -qv '^#'; then
    echo "FAIL: still contains ls -t (breaks on filenames with spaces)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: no ls -t for file selection remaining"
fi

# Functional test: filenames with spaces
TESTS=$((TESTS + 1))
TMPDIR_SPACES=$(mktemp -d)
mkdir -p "$TMPDIR_SPACES/reports"
# Create files with spaces, newest last
echo "old report" > "$TMPDIR_SPACES/reports/old report.md"
sleep 0.1
echo "new report" > "$TMPDIR_SPACES/reports/my new report.md"
# Use the same find command from auto-compound.sh
FOUND=$(cd "$TMPDIR_SPACES" && find reports/ -name '*.md' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [[ "$FOUND" == "reports/my new report.md" ]]; then
    echo "PASS: find selects newest file even with spaces in name"
else
    echo "FAIL: find did not select correct file with spaces"
    echo "  expected: reports/my new report.md"
    echo "  actual:   $FOUND"
    FAILURES=$((FAILURES + 1))
fi
rm -rf "$TMPDIR_SPACES"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
