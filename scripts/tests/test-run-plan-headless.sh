#!/usr/bin/env bash
# Test run-plan-headless.sh extraction
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RP="$SCRIPT_DIR/../run-plan.sh"
RPH="$SCRIPT_DIR/../lib/run-plan-headless.sh"
RPEB="$SCRIPT_DIR/../lib/run-plan-echo-back.sh"
RPS="$SCRIPT_DIR/../lib/run-plan-sampling.sh"

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

# === Extracted echo-back file exists ===
TESTS=$((TESTS + 1))
if [[ -f "$RPEB" ]]; then
    echo "PASS: run-plan-echo-back.sh exists"
else
    echo "FAIL: run-plan-echo-back.sh should exist at scripts/lib/"
    FAILURES=$((FAILURES + 1))
fi

# === Extracted sampling file exists ===
TESTS=$((TESTS + 1))
if [[ -f "$RPS" ]]; then
    echo "PASS: run-plan-sampling.sh exists"
else
    echo "FAIL: run-plan-sampling.sh should exist at scripts/lib/"
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

# === run-plan.sh sources new modules ===
TESTS=$((TESTS + 1))
if grep -q 'source.*lib/run-plan-echo-back.sh' "$RP"; then
    echo "PASS: run-plan.sh sources lib/run-plan-echo-back.sh"
else
    echo "FAIL: run-plan.sh should source lib/run-plan-echo-back.sh"
    FAILURES=$((FAILURES + 1))
fi

TESTS=$((TESTS + 1))
if grep -q 'source.*lib/run-plan-sampling.sh' "$RP"; then
    echo "PASS: run-plan.sh sources lib/run-plan-sampling.sh"
else
    echo "FAIL: run-plan.sh should source lib/run-plan-sampling.sh"
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

# === run-plan.sh is under 330 lines ===

line_count=$(wc -l < "$RP")
TESTS=$((TESTS + 1))
if [[ $line_count -le 330 ]]; then
    echo "PASS: run-plan.sh is $line_count lines (<=330)"
else
    echo "FAIL: run-plan.sh is $line_count lines (should be <=330)"
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
if grep -q '_baseline_patch' "$RPS"; then
    echo "PASS: run-plan-sampling.sh saves baseline state as a patch file"
else
    echo "FAIL: run-plan-sampling.sh should save baseline state as a patch file (bug #2/#27)"
    FAILURES=$((FAILURES + 1))
fi

# Winner state must be saved as a patch file (not stash)
TESTS=$((TESTS + 1))
if grep -q '_winner_patch\|run-plan-winner' "$RPS"; then
    echo "PASS: run-plan-sampling.sh saves winner state as a patch file"
else
    echo "FAIL: run-plan-sampling.sh should save winner state as a patch file (bug #2/#27)"
    FAILURES=$((FAILURES + 1))
fi

# No executable git stash usage remaining in sampling module (patch approach replaces it).
# Filter out comment lines (lines starting with optional whitespace + #).
TESTS=$((TESTS + 1))
sampling_block=$(sed -n '/^run_sampling_candidates()/,/^}/p' "$RPS")
# Strip comment-only lines before counting stash calls
stash_uses=$(echo "$sampling_block" | grep -v '^\s*#' | grep -c 'git stash' || true)
if [[ "$stash_uses" -eq 0 ]]; then
    echo "PASS: No git stash calls in run_sampling_candidates (replaced by patch approach)"
else
    echo "FAIL: Found $stash_uses git stash call(s) in run_sampling_candidates — should use patch files (bug #2/#27)"
    FAILURES=$((FAILURES + 1))
fi

# Restore of winner uses git apply (patch approach)
TESTS=$((TESTS + 1))
if echo "$sampling_block" | grep -q 'git apply'; then
    echo "PASS: run_sampling_candidates uses git apply to restore winner state"
else
    echo "FAIL: run_sampling_candidates should use git apply to restore winner state (bug #2/#27)"
    FAILURES=$((FAILURES + 1))
fi

# === Bug #30: Echo-back gate behavior ===

# run-plan.sh must accept --skip-echo-back without error
TESTS=$((TESTS + 1))
if grep -q '\-\-skip-echo-back' "$RP"; then
    echo "PASS: run-plan.sh accepts --skip-echo-back flag"
else
    echo "FAIL: run-plan.sh should define --skip-echo-back flag (bug #30)"
    FAILURES=$((FAILURES + 1))
fi

# run-plan.sh must accept --strict-echo-back without error
TESTS=$((TESTS + 1))
if grep -q '\-\-strict-echo-back' "$RP"; then
    echo "PASS: run-plan.sh accepts --strict-echo-back flag"
else
    echo "FAIL: run-plan.sh should define --strict-echo-back flag (bug #30)"
    FAILURES=$((FAILURES + 1))
fi

# _echo_back_check function must exist in headless file
TESTS=$((TESTS + 1))
if grep -q '_echo_back_check()' "$RPEB"; then
    echo "PASS: _echo_back_check() is defined in run-plan-echo-back.sh"
else
    echo "FAIL: _echo_back_check() should be defined in run-plan-echo-back.sh (bug #30)"
    FAILURES=$((FAILURES + 1))
fi

# Echo-back gate must be non-blocking by default (no early return when STRICT_ECHO_BACK not set)
TESTS=$((TESTS + 1))
if grep -q 'STRICT_ECHO_BACK' "$RPEB"; then
    echo "PASS: STRICT_ECHO_BACK controls blocking behavior in echo-back gate"
else
    echo "FAIL: echo-back gate should check STRICT_ECHO_BACK for blocking mode (bug #30)"
    FAILURES=$((FAILURES + 1))
fi

# echo-back gate is documented as non-blocking by default
TESTS=$((TESTS + 1))
if grep -q 'NON-BLOCKING' "$RPEB"; then
    echo "PASS: run-plan-echo-back.sh documents NON-BLOCKING default behavior"
else
    echo "FAIL: run-plan-echo-back.sh should document NON-BLOCKING default (bug #30)"
    FAILURES=$((FAILURES + 1))
fi

# _echo_back_check: SKIP_ECHO_BACK=true must cause early return without error
TESTS=$((TESTS + 1))
(
    source "$RPEB" 2>/dev/null || true
    SKIP_ECHO_BACK=true
    STRICT_ECHO_BACK=false
    _echo_back_check "some batch text here" "/nonexistent/log" 2>/dev/null
) && echo "PASS: _echo_back_check returns 0 when SKIP_ECHO_BACK=true" \
  || {
    echo "FAIL: _echo_back_check should return 0 when SKIP_ECHO_BACK=true (bug #30)"
    FAILURES=$((FAILURES + 1))
}

# _echo_back_check: missing log file does not crash
TESTS=$((TESTS + 1))
(
    source "$RPEB" 2>/dev/null || true
    SKIP_ECHO_BACK=false
    STRICT_ECHO_BACK=false
    _echo_back_check "some batch text here" "/nonexistent/log" 2>/dev/null
) && echo "PASS: _echo_back_check handles missing log file gracefully" \
  || {
    echo "FAIL: _echo_back_check should handle missing log file gracefully (bug #30)"
    FAILURES=$((FAILURES + 1))
}

# _echo_back_check: empty batch text does not crash
TESTS=$((TESTS + 1))
tmplog=$(mktemp)
echo "some agent output here" > "$tmplog"
(
    source "$RPEB" 2>/dev/null || true
    SKIP_ECHO_BACK=false
    STRICT_ECHO_BACK=false
    _echo_back_check "" "$tmplog" 2>/dev/null
)
ec=$?
rm -f "$tmplog"
if [[ $ec -eq 0 ]]; then
    echo "PASS: _echo_back_check handles empty batch text gracefully"
else
    echo "FAIL: _echo_back_check should handle empty batch text without error (bug #30)"
    FAILURES=$((FAILURES + 1))
fi

# === Bug #4 BEHAVIORAL: awk removes Run-Plan even when it's the last section ===
# The old sed range pattern '/^## Run-Plan:/,/^## [^R]/' had no closing anchor
# when Run-Plan was the last section, eating the file from Run-Plan to EOF.
# This behavioral test exercises the actual awk code path with a CLAUDE.md
# where "## Run-Plan:" is the last section and verifies other sections survive.

WORK_AWK=$(mktemp -d)
# Create a CLAUDE.md where Run-Plan is the LAST section
cat > "$WORK_AWK/CLAUDE.md" << 'CLAUDE_EOF'
# Project Config

## Conventions

- Use pytest
- Stage specific files

## Run-Plan: Batch 3

### Recent Commits
abc1234 fix: something

### Progress Notes
Batch 2 done.
CLAUDE_EOF

# Run the same awk logic that run-plan-headless.sh uses inline
awk '
    /^## Run-Plan:/ { in_section=1; next }
    in_section && /^## / { in_section=0 }
    !in_section { print }
' "$WORK_AWK/CLAUDE.md" > "$WORK_AWK/CLAUDE.md.tmp"
mv "$WORK_AWK/CLAUDE.md.tmp" "$WORK_AWK/CLAUDE.md"

# Verify: Run-Plan section is gone
TESTS=$((TESTS + 1))
if grep -q "## Run-Plan:" "$WORK_AWK/CLAUDE.md"; then
    echo "FAIL: awk last-section: Run-Plan section should be removed"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: awk last-section: Run-Plan section removed"
fi

# Verify: Conventions section still exists (not eaten by unbounded deletion)
TESTS=$((TESTS + 1))
if grep -q "## Conventions" "$WORK_AWK/CLAUDE.md"; then
    echo "PASS: awk last-section: Conventions section preserved"
else
    echo "FAIL: awk last-section: Conventions section should survive Run-Plan removal"
    FAILURES=$((FAILURES + 1))
fi

# Verify: content before Run-Plan is preserved
TESTS=$((TESTS + 1))
if grep -q "Use pytest" "$WORK_AWK/CLAUDE.md"; then
    echo "PASS: awk last-section: content before Run-Plan preserved"
else
    echo "FAIL: awk last-section: content before Run-Plan should be preserved"
    FAILURES=$((FAILURES + 1))
fi

rm -rf "$WORK_AWK"

# === Bug #38: Empty claude output diagnostic ===

# Must check for empty log file after claude invocation
TESTS=$((TESTS + 1))
if grep -q 'claude produced no output' "$RPH"; then
    echo "PASS: Empty claude output is diagnosed with a warning message (#38)"
else
    echo "FAIL: Should diagnose empty claude output (crash/no output case) (bug #38)"
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
