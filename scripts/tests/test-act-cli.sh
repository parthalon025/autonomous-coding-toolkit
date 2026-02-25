#!/usr/bin/env bash
# test-act-cli.sh — Tests for bin/act.js CLI router
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

ACT="$REPO_ROOT/bin/act.js"

# ---------------------------------------------------------------------------
# version command
# ---------------------------------------------------------------------------
version_output=$(node "$ACT" version 2>&1)
assert_contains "version outputs 'act v'" "act v" "$version_output"

# ---------------------------------------------------------------------------
# help command
# ---------------------------------------------------------------------------
help_output=$(node "$ACT" help 2>&1)
assert_contains "help outputs usage line" "Usage: act <command>" "$help_output"
assert_contains "help lists 'plan' command" "plan" "$help_output"
assert_contains "help lists 'gate' command" "gate" "$help_output"

# ---------------------------------------------------------------------------
# unknown command exits non-zero
# ---------------------------------------------------------------------------
assert_exit "nonexistent command exits 1" 1 node "$ACT" nonexistent-command

# ---------------------------------------------------------------------------
# validate routes to validate-all.sh (output contains "validate")
# ---------------------------------------------------------------------------
# validate-all.sh runs validators — we just confirm it was reached by checking
# that output contains "validate" (the script name / summary line).
validate_output=$(node "$ACT" validate 2>&1 || true)
assert_contains "validate routes to validate-all.sh" "validate" "$validate_output"

# ---------------------------------------------------------------------------
# lessons without subcommand exits non-zero and shows usage hint
# ---------------------------------------------------------------------------
lessons_exit=0
lessons_output=$(node "$ACT" lessons 2>&1) || lessons_exit=$?
assert_exit "lessons without subcommand exits 1" 1 node "$ACT" lessons
assert_contains "lessons shows usage hint" "lessons" "$lessons_output"

report_results
