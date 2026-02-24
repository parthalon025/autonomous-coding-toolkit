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

# === run-plan.sh is under 320 lines ===

line_count=$(wc -l < "$RP")
TESTS=$((TESTS + 1))
if [[ $line_count -le 320 ]]; then
    echo "PASS: run-plan.sh is $line_count lines (<=320)"
else
    echo "FAIL: run-plan.sh is $line_count lines (should be <=320)"
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

# === Bug #4: CLAUDE.md Run-Plan section removal uses awk not sed ===
# The sed range deletion pattern '/^## Run-Plan:/,/^## [^R]/' has no terminating
# anchor when Run-Plan is the last section, so it deletes from Run-Plan to EOF.
# The fix replaces it with awk which handles last-section correctly.

TESTS=$((TESTS + 1))
# awk should be used for section removal; the old sed range pattern should not be present
if grep -q "awk" "$RPH" && grep -q 'in_section' "$RPH"; then
    echo "PASS: CLAUDE.md section removal uses awk (last-section safe, bug #4)"
else
    echo "FAIL: CLAUDE.md section removal should use awk to handle last section correctly (bug #4)"
    FAILURES=$((FAILURES + 1))
fi

TESTS=$((TESTS + 1))
# The old broken sed range pattern must not be present
if grep -q "sed '/\^## Run-Plan:/,/\^## \[^R\]/" "$RPH" 2>/dev/null || \
   grep -q "sed '/\^\#\# Run-Plan:/,/\^\#\# \[^R\]" "$RPH" 2>/dev/null; then
    echo "FAIL: Old sed range deletion pattern still present (unbounded at last section, bug #4)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: Old unbounded sed range deletion pattern removed"
fi

# === Bug #16/#28: SAMPLE_COUNT resets at top of batch loop using SAMPLE_DEFAULT ===

# User's --sample value must be preserved into SAMPLE_DEFAULT before the loop
TESTS=$((TESTS + 1))
if grep -q 'SAMPLE_DEFAULT=.*SAMPLE_COUNT' "$RPH"; then
    echo "PASS: SAMPLE_DEFAULT saves user's --sample value before batch loop"
else
    echo "FAIL: SAMPLE_DEFAULT should save user's --sample value before batch loop (bug #16/#28)"
    FAILURES=$((FAILURES + 1))
fi

# The reset inside the loop must use SAMPLE_DEFAULT, not hardcoded 0
TESTS=$((TESTS + 1))
batch_loop_region=$(sed -n '/for ((batch = START_BATCH/,/SAMPLE_ON_RETRY/p' "$RPH")
if echo "$batch_loop_region" | grep -q 'SAMPLE_COUNT=\$SAMPLE_DEFAULT'; then
    echo "PASS: SAMPLE_COUNT resets to SAMPLE_DEFAULT at start of each batch iteration"
else
    echo "FAIL: SAMPLE_COUNT should reset to SAMPLE_DEFAULT (not 0) at start of each batch iteration (bug #16/#28)"
    FAILURES=$((FAILURES + 1))
fi

# === Bug #2/#27: Sampling block uses patch files instead of stash ===
# The fix replaced git stash/pop with git diff > patch + git apply to
# eliminate LIFO ordering issues. These tests verify the new approach.

# Baseline state must be saved as a patch file (not stash)
TESTS=$((TESTS + 1))
if grep -q '_baseline_patch' "$RPH"; then
    echo "PASS: Sampling block saves baseline state as a patch file"
else
    echo "FAIL: Sampling block should save baseline state as a patch file (bug #2/#27)"
    FAILURES=$((FAILURES + 1))
fi

# Winner state must be saved as a patch file (not stash)
TESTS=$((TESTS + 1))
if grep -q '_winner_patch\|run-plan-winner' "$RPH"; then
    echo "PASS: Sampling block saves winner state as a patch file"
else
    echo "FAIL: Sampling block should save winner state as a patch file (bug #2/#27)"
    FAILURES=$((FAILURES + 1))
fi

# No executable git stash usage remaining in sampling block (patch approach replaces it).
# Filter out comment lines (lines starting with optional whitespace + #).
TESTS=$((TESTS + 1))
sampling_block=$(sed -n '/If sampling enabled/,/continue.*Skip normal retry/p' "$RPH")
# Strip comment-only lines before counting stash calls
stash_uses=$(echo "$sampling_block" | grep -v '^\s*#' | grep -c 'git stash' || true)
if [[ "$stash_uses" -eq 0 ]]; then
    echo "PASS: No git stash calls in sampling block (replaced by patch approach)"
else
    echo "FAIL: Found $stash_uses git stash call(s) in sampling block — should use patch files (bug #2/#27)"
    FAILURES=$((FAILURES + 1))
fi

# Restore of winner uses git apply (patch approach)
TESTS=$((TESTS + 1))
if echo "$sampling_block" | grep -q 'git apply'; then
    echo "PASS: Sampling block uses git apply to restore winner state"
else
    echo "FAIL: Sampling block should use git apply to restore winner state (bug #2/#27)"
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
