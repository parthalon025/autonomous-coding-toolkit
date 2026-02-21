#!/usr/bin/env bash
# Test analyze-report.sh — verifies refactored behavior using ollama.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AR="$SCRIPT_DIR/../analyze-report.sh"

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
if grep -q 'source.*lib/common.sh' "$AR"; then
    echo "PASS: analyze-report.sh sources lib/common.sh"
else
    echo "FAIL: analyze-report.sh sources lib/common.sh"
    FAILURES=$((FAILURES + 1))
fi

TESTS=$((TESTS + 1))
if grep -q 'source.*lib/ollama.sh' "$AR"; then
    echo "PASS: analyze-report.sh sources lib/ollama.sh"
else
    echo "FAIL: analyze-report.sh sources lib/ollama.sh"
    FAILURES=$((FAILURES + 1))
fi

# === Uses ollama_query ===

TESTS=$((TESTS + 1))
if grep -q 'ollama_query' "$AR"; then
    echo "PASS: uses ollama_query function"
else
    echo "FAIL: should use ollama_query function"
    FAILURES=$((FAILURES + 1))
fi

# === Uses ollama_extract_json ===

TESTS=$((TESTS + 1))
if grep -q 'ollama_extract_json' "$AR"; then
    echo "PASS: uses ollama_extract_json function"
else
    echo "FAIL: should use ollama_extract_json function"
    FAILURES=$((FAILURES + 1))
fi

# === No inline curl to Ollama ===

TESTS=$((TESTS + 1))
if grep -q 'curl.*api/generate' "$AR"; then
    echo "FAIL: still has inline curl to Ollama API"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: no inline curl to Ollama API"
fi

# === CLI tests ===

assert_exit "no args exits 1" 1 bash "$AR"
assert_exit "nonexistent file exits 1" 1 bash "$AR" /nonexistent/report.md

# === Dry run works ===

WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT
echo "# Test report" > "$WORK/report.md"
output=$(bash "$AR" "$WORK/report.md" --dry-run 2>&1) || true
TESTS=$((TESTS + 1))
if echo "$output" | grep -q "DRY RUN"; then
    echo "PASS: dry-run mode works"
else
    echo "FAIL: dry-run mode should output DRY RUN"
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
