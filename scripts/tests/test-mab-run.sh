#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

MAB_RUN="$SCRIPT_DIR/../mab-run.sh"

# --- Test: --help exits 0 and mentions key concepts ---
help_output=$("$MAB_RUN" --help 2>&1) || true
assert_exit "--help exits 0" 0 "$MAB_RUN" --help
assert_contains "--help mentions worktree" "worktree" "$help_output"
assert_contains "--help mentions judge" "judge" "$help_output"

# --- Test: missing plan exits 1 ---
assert_exit "missing plan exits 1" 1 "$MAB_RUN" --plan /tmp/nonexistent-plan-$$.md --batch 1 --work-unit "test" --worktree /tmp

# --- Test: non-numeric batch exits 1 ---
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Create a minimal plan file
cat > "$TEST_TMPDIR/plan.md" <<'MD'
# Test Plan

## Batch 1: Test batch

Do something.
MD

assert_exit "non-numeric batch exits 1" 1 "$MAB_RUN" --plan "$TEST_TMPDIR/plan.md" --batch abc --work-unit "test" --worktree "$TEST_TMPDIR"

# --- Test: --dry-run exits 0 with valid args ---
dry_output=$("$MAB_RUN" --plan "$TEST_TMPDIR/plan.md" --batch 1 --work-unit "test batch" --worktree "$TEST_TMPDIR" --dry-run 2>&1) || true
dry_exit=0
"$MAB_RUN" --plan "$TEST_TMPDIR/plan.md" --batch 1 --work-unit "test batch" --worktree "$TEST_TMPDIR" --dry-run > /dev/null 2>&1 || dry_exit=$?
assert_eq "--dry-run exits 0" "0" "$dry_exit"
assert_contains "--dry-run shows planned actions" "DRY RUN" "$dry_output"

# --- Test: --init-data creates valid JSON files ---
init_dir=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR" "$init_dir"' EXIT
"$MAB_RUN" --init-data --worktree "$init_dir" > /dev/null 2>&1 || true

TESTS=$((TESTS + 1))
if [[ -f "$init_dir/logs/strategy-perf.json" ]] && jq . "$init_dir/logs/strategy-perf.json" > /dev/null 2>&1; then
    echo "PASS: --init-data creates valid strategy-perf.json"
else
    echo "FAIL: --init-data did not create valid strategy-perf.json"
    FAILURES=$((FAILURES + 1))
fi

TESTS=$((TESTS + 1))
if [[ -f "$init_dir/logs/mab-lessons.json" ]] && jq . "$init_dir/logs/mab-lessons.json" > /dev/null 2>&1; then
    echo "PASS: --init-data creates valid mab-lessons.json"
else
    echo "FAIL: --init-data did not create valid mab-lessons.json"
    FAILURES=$((FAILURES + 1))
fi
rm -rf "$init_dir"

# --- Test: select_winner_with_gate_override ---
# Source mab-run functions for unit testing — fail loudly if sourcing breaks
source "$MAB_RUN" --source-only 2>/dev/null || true

TESTS=$((TESTS + 1))
if ! type select_winner_with_gate_override &>/dev/null; then
    echo "FAIL: select_winner_with_gate_override not found after sourcing mab-run.sh"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: select_winner_with_gate_override available after --source-only"

    # Only A passes → A wins
    result=$(select_winner_with_gate_override 0 1 "agent-b")
    assert_eq "only A passes → agent-a" "agent-a" "$result"

    # Only B passes → B wins
    result=$(select_winner_with_gate_override 1 0 "agent-a")
    assert_eq "only B passes → agent-b" "agent-b" "$result"

    # Neither passes → none
    result=$(select_winner_with_gate_override 1 1 "agent-a")
    assert_eq "neither passes → none" "none" "$result"

    # Both pass → judge winner
    result=$(select_winner_with_gate_override 0 0 "agent-b")
    assert_eq "both pass → judge winner" "agent-b" "$result"
fi

# --- Test: assemble_agent_prompt substitutes placeholders ---
TESTS=$((TESTS + 1))
if ! type assemble_agent_prompt &>/dev/null; then
    echo "FAIL: assemble_agent_prompt not found after sourcing mab-run.sh"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: assemble_agent_prompt available after --source-only"

    prompt_template="Work: {WORK_UNIT_DESCRIPTION}, PRD: {PRD_PATH}, Gate: {QUALITY_GATE_CMD}"
    result=$(assemble_agent_prompt "$prompt_template" \
        "implement feature X" \
        "tasks/prd.json" \
        "docs/ARCHITECTURE-MAP.json" \
        "no lessons yet" \
        "scripts/quality-gate.sh --project-root .")

    assert_contains "substitutes WORK_UNIT_DESCRIPTION" "implement feature X" "$result"
    assert_contains "substitutes PRD_PATH" "tasks/prd.json" "$result"
    assert_contains "substitutes QUALITY_GATE_CMD" "scripts/quality-gate.sh --project-root ." "$result"
    assert_not_contains "no remaining placeholders" "{WORK_UNIT_DESCRIPTION}" "$result"
fi

report_results
