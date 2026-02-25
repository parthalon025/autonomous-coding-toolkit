#!/usr/bin/env bash
# Test benchmarks/runner.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNNER="$REPO_ROOT/benchmarks/runner.sh"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Test 1: list shows benchmarks ---
output=$(bash "$RUNNER" list 2>&1)
assert_contains "list shows benchmarks" "01-rest-endpoint" "$output"
assert_contains "list shows all 5" "05-multi-file-feature" "$output"

# --- Test 2: help works ---
output=$(bash "$RUNNER" help 2>&1)
assert_contains "help shows usage" "Usage:" "$output"

# --- Test 3: unknown benchmark fails gracefully ---
exit_code=0
bash "$RUNNER" run nonexistent-benchmark >/dev/null 2>&1 || exit_code=$?
assert_eq "unknown benchmark exits non-zero" "1" "$exit_code"

report_results
