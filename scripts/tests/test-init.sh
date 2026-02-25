#!/usr/bin/env bash
# Test scripts/init.sh — project bootstrapper
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT_SCRIPT="$REPO_ROOT/scripts/init.sh"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Setup temp project ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
git init -q

# --- Test 1: init creates tasks/ directory ---
bash "$INIT_SCRIPT" --project-root "$WORK" 2>&1 || true
assert_eq "init creates tasks/ directory" "true" "$([ -d "$WORK/tasks" ] && echo true || echo false)"

# --- Test 2: init creates progress.txt ---
assert_eq "init creates progress.txt" "true" "$([ -f "$WORK/progress.txt" ] && echo true || echo false)"

# --- Test 3: init creates logs/ directory ---
assert_eq "init creates logs/ directory" "true" "$([ -d "$WORK/logs" ] && echo true || echo false)"

# --- Test 4: init detects project type ---
output=$(bash "$INIT_SCRIPT" --project-root "$WORK" 2>&1 || true)
assert_contains "init detects project type" "Detected:" "$output"

# --- Test 5: init with --quickstart copies quickstart plan ---
mkdir -p "$WORK/docs/plans"
bash "$INIT_SCRIPT" --project-root "$WORK" --quickstart 2>&1 || true
assert_eq "quickstart creates plan file" "true" "$([ -f "$WORK/docs/plans/quickstart.md" ] && echo true || echo false)"

# --- Test 6: init is idempotent ---
bash "$INIT_SCRIPT" --project-root "$WORK" 2>&1 || true
exit_code=0
bash "$INIT_SCRIPT" --project-root "$WORK" 2>&1 || exit_code=$?
assert_eq "init is idempotent (exit 0 on re-run)" "0" "$exit_code"

report_results
