#!/usr/bin/env bash
# Test validate-plans.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

VALIDATOR="$SCRIPT_DIR/../validate-plans.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Helper: create a plan file
create_plan() {
    local name="$1" content="$2"
    mkdir -p "$WORK/plans"
    printf '%s\n' "$content" > "$WORK/plans/$name"
}

# Helper: run validator against temp plans dir
run_validator() {
    local exit_code=0
    PLANS_DIR="$WORK/plans" bash "$VALIDATOR" "$@" 2>&1 || exit_code=$?
    echo "EXIT:$exit_code"
}

# === Test: Valid plan passes ===
rm -rf "$WORK/plans"
create_plan "2026-01-01-test-plan.md" '# Test Plan

## Batch 1: Setup

### Task 1: Do thing one

Some content.

### Task 2: Do thing two

More content.

## Batch 2: Implementation

### Task 3: Do thing three

Final content.'

output=$(run_validator)
assert_contains "valid plan: PASS" "validate-plans: PASS" "$output"
assert_contains "valid plan: exit 0" "EXIT:0" "$output"

# === Test: No batches fails (explicit file) ===
rm -rf "$WORK/plans"
create_plan "2026-01-01-no-batches.md" '# A Plan

This plan has no batch headers at all.

Just some text.'

exit_code=0
output=$(bash "$VALIDATOR" "$WORK/plans/2026-01-01-no-batches.md" 2>&1) || exit_code=$?
output="${output}
EXIT:${exit_code}"
assert_contains "no batches: reports violation" "No batches found" "$output"
assert_contains "no batches: exit 1" "EXIT:1" "$output"

# === Test: Empty batch (no tasks) fails ===
rm -rf "$WORK/plans"
create_plan "2026-01-01-empty-batch.md" '# Plan

## Batch 1: Setup

### Task 1: Do something

Content.

## Batch 2: Empty

No tasks here.

## Batch 3: More

### Task 2: Do another thing

Content.'

output=$(run_validator)
assert_contains "empty batch: reports violation" "has no tasks" "$output"
assert_contains "empty batch: exit 1" "EXIT:1" "$output"

# === Test: Non-sequential batch numbers fails ===
rm -rf "$WORK/plans"
create_plan "2026-01-01-nonseq.md" '# Plan

## Batch 1: First

### Task 1: Do thing

Content.

## Batch 3: Skipped Two

### Task 2: Do another

Content.'

output=$(run_validator)
assert_contains "non-sequential: reports violation" "expected Batch 2" "$output"
assert_contains "non-sequential: exit 1" "EXIT:1" "$output"

# === Test: Design docs (no Batch headers) are skipped ===
rm -rf "$WORK/plans"
create_plan "2026-01-01-design.md" '# Design Doc

This is a design document, not a plan. No Batch headers.'
create_plan "2026-01-01-plan.md" '# Plan

## Batch 1: Setup

### Task 1: Do thing

Content.'

output=$(run_validator)
assert_contains "design doc skipped: PASS" "validate-plans: PASS" "$output"
assert_contains "design doc skipped: exit 0" "EXIT:0" "$output"

# === Test: Single file argument validates just that file ===
rm -rf "$WORK/plans"
create_plan "2026-01-01-good.md" '# Plan

## Batch 1: Setup

### Task 1: Do thing

Content.'

exit_code=0
output=$(bash "$VALIDATOR" "$WORK/plans/2026-01-01-good.md" 2>&1) || exit_code=$?
output="${output}
EXIT:${exit_code}"
assert_contains "single file arg: PASS" "validate-plans: PASS" "$output"
assert_contains "single file arg: exit 0" "EXIT:0" "$output"

# === Test: --warn exits 0 even with violations ===
rm -rf "$WORK/plans"
create_plan "2026-01-01-bad.md" '# Plan

## Batch 1: Setup

No tasks here.'

output=$(run_validator --warn)
assert_contains "--warn: still reports violation" "has no tasks" "$output"
assert_contains "--warn: exits 0" "EXIT:0" "$output"

# === Test: --help exits 0 ===
output=$(run_validator --help)
assert_contains "--help: shows usage" "Usage:" "$output"
assert_contains "--help: exits 0" "EXIT:0" "$output"

# === Test: Task on next batch header line not counted for previous batch (#26) ===
# This tests the sed range fix — when a "### Task" line is the first line of
# the next batch (immediately after "## Batch N"), it must not be counted for
# the previous batch.
rm -rf "$WORK/plans"
create_plan "2026-01-01-adjacent.md" '# Plan

## Batch 1: Setup

Some content but no tasks here.

## Batch 2: Implementation

### Task 1: The only task

Content.'

output=$(run_validator)
assert_contains "adjacent batch: batch 1 has no tasks" "Batch 1 has no tasks" "$output"
assert_contains "adjacent batch: FAIL" "FAIL" "$output"

# === Test: Missing plans directory fails ===
rm -rf "$WORK/plans"
output=$(PLANS_DIR="$WORK/nonexistent" bash "$VALIDATOR" 2>&1 || echo "EXIT:$?")
assert_contains "missing dir: error message" "plans directory not found" "$output"
assert_contains "missing dir: exit 1" "EXIT:1" "$output"

report_results
