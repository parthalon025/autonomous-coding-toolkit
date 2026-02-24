#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Save test script dir — sourcing mab-run.sh overwrites SCRIPT_DIR
TEST_DIR="$SCRIPT_DIR"
source "$SCRIPT_DIR/test-helpers.sh"

MAB_RUN="$TEST_DIR/../mab-run.sh"

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

# --- Test: update_mab_data lesson deduplication ---
# Call update_mab_data twice with the same lesson — should have 1 entry with occurrences=2
TESTS=$((TESTS + 1))
if ! type update_mab_data &>/dev/null; then
    echo "FAIL: update_mab_data not found after sourcing mab-run.sh"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: update_mab_data available after --source-only"

    dedup_dir=$(mktemp -d)
    MAB_WORKTREE="$dedup_dir"
    mkdir -p "$dedup_dir/logs"
    # init_strategy_perf is already available (sourced via mab-run.sh --source-only)
    init_strategy_perf "$dedup_dir/logs/strategy-perf.json"

    # First call — creates new lesson entry
    update_mab_data "agent-a" "always check imports" "new-file"

    TESTS=$((TESTS + 1))
    count1=$(jq 'length' "$dedup_dir/logs/mab-lessons.json" 2>/dev/null || echo "0")
    if [[ "$count1" == "1" ]]; then
        echo "PASS: update_mab_data: first call creates 1 lesson entry"
    else
        echo "FAIL: update_mab_data: expected 1 entry after first call, got $count1"
        FAILURES=$((FAILURES + 1))
    fi

    # Second call with same lesson — should deduplicate (increment occurrences, not add)
    update_mab_data "agent-b" "always check imports" "new-file"

    TESTS=$((TESTS + 1))
    count2=$(jq 'length' "$dedup_dir/logs/mab-lessons.json" 2>/dev/null || echo "0")
    if [[ "$count2" == "1" ]]; then
        echo "PASS: update_mab_data: second call deduplicates (still 1 entry)"
    else
        echo "FAIL: update_mab_data: expected 1 entry after dedup, got $count2"
        FAILURES=$((FAILURES + 1))
    fi

    occ=$(jq '.[0].occurrences' "$dedup_dir/logs/mab-lessons.json" 2>/dev/null || echo "0")
    assert_eq "update_mab_data: occurrences incremented to 2" "2" "$occ"

    rm -rf "$dedup_dir"
fi

# --- Test: --mab flag wiring (run-plan.sh → run-plan-headless.sh → mab-run.sh) ---
# run-plan.sh parses --mab and sets MAB=true
RP_MAIN="$TEST_DIR/../run-plan.sh"
RP_HEADLESS="$TEST_DIR/../lib/run-plan-headless.sh"

TESTS=$((TESTS + 1))
if grep -q '\-\-mab) MAB=true' "$RP_MAIN" 2>/dev/null; then
    echo "PASS: run-plan.sh parses --mab flag and sets MAB=true"
else
    echo "FAIL: run-plan.sh should parse --mab and set MAB=true"
    FAILURES=$((FAILURES + 1))
fi

# run-plan-headless.sh checks MAB flag and invokes mab-run.sh
TESTS=$((TESTS + 1))
if grep -q 'MAB.*true' "$RP_HEADLESS" 2>/dev/null && \
   grep -q 'mab-run.sh' "$RP_HEADLESS" 2>/dev/null; then
    echo "PASS: run-plan-headless.sh checks MAB flag and invokes mab-run.sh"
else
    echo "FAIL: run-plan-headless.sh should check MAB flag and invoke mab-run.sh"
    FAILURES=$((FAILURES + 1))
fi

report_results
