#!/usr/bin/env bash
# Test run-plan-headless.sh extraction
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RP="$SCRIPT_DIR/../run-plan.sh"
RPH="$SCRIPT_DIR/../lib/run-plan-headless.sh"

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

# === Extracted file exists ===

TESTS=$((TESTS + 1))
if [[ -f "$RPH" ]]; then
    echo "PASS: run-plan-headless.sh exists"
else
    echo "FAIL: run-plan-headless.sh should exist at scripts/lib/"
    FAILURES=$((FAILURES + 1))
fi

# === run-plan.sh sources it ===

TESTS=$((TESTS + 1))
if grep -q 'source.*lib/run-plan-headless.sh' "$RP"; then
    echo "PASS: run-plan.sh sources lib/run-plan-headless.sh"
else
    echo "FAIL: run-plan.sh should source lib/run-plan-headless.sh"
    FAILURES=$((FAILURES + 1))
fi

# === run-plan.sh no longer has inline run_mode_headless body ===
# The function definition should be in the extracted file, not in run-plan.sh

TESTS=$((TESTS + 1))
# Count lines of run_mode_headless in run-plan.sh — should be 0 (no function body)
if grep -q 'run_mode_headless()' "$RP"; then
    echo "FAIL: run-plan.sh should not define run_mode_headless()"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: run_mode_headless() not defined in run-plan.sh"
fi

# === Extracted file defines the function ===

TESTS=$((TESTS + 1))
if grep -q 'run_mode_headless()' "$RPH"; then
    echo "PASS: run-plan-headless.sh defines run_mode_headless()"
else
    echo "FAIL: run-plan-headless.sh should define run_mode_headless()"
    FAILURES=$((FAILURES + 1))
fi

# === run-plan.sh is under 300 lines ===

line_count=$(wc -l < "$RP")
TESTS=$((TESTS + 1))
if [[ $line_count -le 300 ]]; then
    echo "PASS: run-plan.sh is $line_count lines (<=300)"
else
    echo "FAIL: run-plan.sh is $line_count lines (should be <=300)"
    FAILURES=$((FAILURES + 1))
fi

# === Extracted file has the key logic markers ===

TESTS=$((TESTS + 1))
if grep -q 'mkdir -p.*logs' "$RPH"; then
    echo "PASS: headless file creates logs directory"
else
    echo "FAIL: headless file should create logs directory"
    FAILURES=$((FAILURES + 1))
fi

TESTS=$((TESTS + 1))
if grep -q 'claude -p' "$RPH"; then
    echo "PASS: headless file calls claude -p"
else
    echo "FAIL: headless file should call claude -p"
    FAILURES=$((FAILURES + 1))
fi

# === Empty batch detection ===
# The parser should return empty text for empty batches, and headless mode should skip them.
# This test verifies the parser side (headless mode integration is tested separately).

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

source "$SCRIPT_DIR/../lib/run-plan-parser.sh"

# Create a plan with 2 real batches and 1 empty trailing match
cat > "$WORK/plan-empty.md" << 'PLAN'
## Batch 1: Real Batch
### Task 1: Do something
Write some code.

## Batch 2: Also Real
### Task 2: Do more
Write more code.

## Batch 3:
PLAN

# get_batch_text should return empty for batch 3
val=$(get_batch_text "$WORK/plan-empty.md" 3)
assert_eq "get_batch_text: empty batch returns empty" "" "$val"

# count_batches should count all 3 (parser counts headers)
val=$(count_batches "$WORK/plan-empty.md")
assert_eq "count_batches: counts all headers including empty" "3" "$val"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
