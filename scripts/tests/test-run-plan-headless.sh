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

# === Bug #27: Stash pop guarded by stash creation check ===

# The initial stash should track before/after count
TESTS=$((TESTS + 1))
if grep -q '_stash_before.*git stash list' "$RPH" && grep -q '_stash_after.*git stash list' "$RPH"; then
    echo "PASS: Stash tracks before/after count to detect no-op"
else
    echo "FAIL: Stash should track before/after count to detect no-op stash (bug #27)"
    FAILURES=$((FAILURES + 1))
fi

# Stash flags must be split: _baseline_stash_created for per-candidate restore, _winner_stash_created for final restore
TESTS=$((TESTS + 1))
if grep -q '_baseline_stash_created' "$RPH" && grep -q '_winner_stash_created' "$RPH"; then
    echo "PASS: Stash flags split into _baseline_stash_created and _winner_stash_created"
else
    echo "FAIL: Stash flags should be split into _baseline_stash_created and _winner_stash_created"
    FAILURES=$((FAILURES + 1))
fi

# The old conflated _stash_created flag must not exist (except inside variable names like _baseline_stash_created)
TESTS=$((TESTS + 1))
# Match bare _stash_created (not preceded by baseline_ or winner_)
bare_stash=$(grep -P '(?<!baseline)(?<!winner)_stash_created' "$RPH" || true)
if [[ -z "$bare_stash" ]]; then
    echo "PASS: No bare _stash_created flag remains (all are baseline or winner prefixed)"
else
    echo "FAIL: Found bare _stash_created — should be _baseline_stash_created or _winner_stash_created"
    FAILURES=$((FAILURES + 1))
fi

# All git stash pop calls in the sampling block must be guarded by a stash_created check
TESTS=$((TESTS + 1))
sampling_block=$(sed -n '/If sampling enabled/,/continue.*Skip normal retry/p' "$RPH")
total_pops=$(echo "$sampling_block" | grep -c 'git stash pop' || true)
# Check: every stash pop line has _stash_created on same line OR on the if-line directly above
unguarded=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if ! echo "$line" | grep -q '_stash_created'; then
        unguarded=$((unguarded + 1))
    fi
done <<< "$(echo "$sampling_block" | grep 'git stash pop')"
# Also count block-guarded pops (stash pop on its own line, but inside if _stash_created block)
block_guarded=$(echo "$sampling_block" | grep -B1 'git stash pop' | grep -c '_stash_created' || true)
effective_unguarded=$((unguarded - block_guarded))
[[ $effective_unguarded -lt 0 ]] && effective_unguarded=0
if [[ "$effective_unguarded" -eq 0 ]]; then
    echo "PASS: All git stash pop calls in sampling block are guarded ($total_pops total)"
else
    echo "FAIL: Found $effective_unguarded unguarded git stash pop in sampling block ($total_pops total, bug #27)"
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
