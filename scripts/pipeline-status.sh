#!/usr/bin/env bash
# pipeline-status.sh — Single-command view of Code Factory pipeline status
#
# Usage: pipeline-status.sh [--help] [--show-costs] [project-root]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

SHOW_COSTS=false
PROJECT_ROOT=""

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "pipeline-status.sh — Show Code Factory pipeline status"
            echo "Usage: pipeline-status.sh [--show-costs] [project-root]"
            echo ""
            echo "Options:"
            echo "  --show-costs    Show per-batch cost breakdown from state file"
            exit 0
            ;;
        --show-costs)
            SHOW_COSTS=true
            ;;
        *)
            PROJECT_ROOT="$arg"
            ;;
    esac
done

PROJECT_ROOT="${PROJECT_ROOT:-.}"

echo "═══════════════════════════════════════════════"
echo "  Code Factory Pipeline Status"
echo "═══════════════════════════════════════════════"
echo "Project: $(basename "$(realpath "$PROJECT_ROOT")")"
echo "Type:    $(detect_project_type "$PROJECT_ROOT")"
echo ""

# Run-plan state
STATE_FILE="$PROJECT_ROOT/.run-plan-state.json"
if [[ -f "$STATE_FILE" ]]; then
    echo "--- Run Plan ---"
    plan=$(jq -r '.plan_file // "unknown"' "$STATE_FILE")
    mode=$(jq -r '.mode // "unknown"' "$STATE_FILE")
    current=$(jq -r '.current_batch // 0' "$STATE_FILE")
    completed=$(jq -r '.completed_batches | length' "$STATE_FILE")
    started=$(jq -r '.started_at // "unknown"' "$STATE_FILE")
    echo "  Plan:      $(basename "$plan")"
    echo "  Mode:      $mode"
    echo "  Progress:  $completed batches completed (current: $current)"
    echo "  Started:   $started"

    # Last quality gate
    gate_passed=$(jq -r '.last_quality_gate.passed // "n/a"' "$STATE_FILE")
    gate_tests=$(jq -r '.last_quality_gate.test_count // "n/a"' "$STATE_FILE")
    echo "  Last gate: passed=$gate_passed, tests=$gate_tests"

    # Cost summary: total from state file costs map (if present)
    # Fix #70: .costs values may be objects (from record_batch_cost) or plain numbers/strings (legacy).
    # Try .estimated_cost_usd first, then tonumber for backward compat.
    total_cost=$(jq -r '
        if .costs then
            (.costs | to_entries | map(
                if .value | type == "object" then (.value.estimated_cost_usd // 0)
                else (.value | tonumber? // 0) end
            ) | add // 0)
        else 0 end
    ' "$STATE_FILE" 2>/dev/null || echo "0")
    if [[ "$total_cost" != "0" && "$total_cost" != "null" && -n "$total_cost" ]]; then
        echo "  Total cost: \$$total_cost"
    fi
    echo ""
else
    echo "--- Run Plan ---"
    echo "  No active run-plan state found"
    echo ""
fi

# PRD status
if [[ -f "$PROJECT_ROOT/tasks/prd.json" ]]; then
    echo "--- PRD ---"
    total=$(jq 'length' "$PROJECT_ROOT/tasks/prd.json")
    passing=$(jq '[.[] | select(.passes == true)] | length' "$PROJECT_ROOT/tasks/prd.json")
    echo "  Tasks: $passing/$total passing"
    echo ""
else
    echo "--- PRD ---"
    echo "  No PRD found (tasks/prd.json)"
    echo ""
fi

# MAB status
PERF_FILE="$PROJECT_ROOT/logs/strategy-perf.json"
LESSONS_FILE="$PROJECT_ROOT/logs/mab-lessons.json"
if [[ -f "$PERF_FILE" ]]; then
    echo "--- MAB (Multi-Armed Bandit) ---"
    cal_count=$(jq -r '.calibration_count // 0' "$PERF_FILE" 2>/dev/null)
    cal_complete=$(jq -r '.calibration_complete // false' "$PERF_FILE" 2>/dev/null)
    echo "  Calibration: $cal_count/10 (complete: $cal_complete)"

    # Per-type win rates
    for bt in "new-file" "refactoring" "integration" "test-only"; do
        sp_w=$(jq -r --arg bt "$bt" '.[$bt].superpowers.wins // 0' "$PERF_FILE" 2>/dev/null)
        sp_l=$(jq -r --arg bt "$bt" '.[$bt].superpowers.losses // 0' "$PERF_FILE" 2>/dev/null)
        r_w=$(jq -r --arg bt "$bt" '.[$bt].ralph.wins // 0' "$PERF_FILE" 2>/dev/null)
        r_l=$(jq -r --arg bt "$bt" '.[$bt].ralph.losses // 0' "$PERF_FILE" 2>/dev/null)
        sp_total=$((sp_w + sp_l))
        r_total=$((r_w + r_l))
        if [[ $sp_total -gt 0 || $r_total -gt 0 ]]; then
            echo "  $bt: superpowers=${sp_w}W/${sp_l}L  ralph=${r_w}W/${r_l}L"
        fi
    done

    # Lesson count
    if [[ -f "$LESSONS_FILE" ]]; then
        lesson_count=$(jq 'length' "$LESSONS_FILE" 2>/dev/null || echo "0")
        echo "  Lessons: $lesson_count patterns recorded"
    fi
    echo ""
fi

# Cost breakdown (--show-costs) (#42/#43)
# Filter to numeric-only batch keys before sort to avoid tonumber crash on "final" or other non-numeric keys.
if [[ "$SHOW_COSTS" == "true" && -f "$STATE_FILE" ]]; then
    echo "--- Cost Breakdown ---"
    has_costs=$(jq -r 'if .costs then "yes" else "no" end' "$STATE_FILE" 2>/dev/null || echo "no")
    if [[ "$has_costs" == "yes" ]]; then
        jq -r '
            .costs // {} |
            to_entries |
            [.[] | select(.key | test("^[0-9]+$"))] |
            sort_by(.key | tonumber) |
            .[] |
            "  Batch \(.key): $\(if .value | type == "object" then .value.estimated_cost_usd // 0 else .value end)"
        ' "$STATE_FILE" 2>/dev/null || echo "  (cost data unreadable)"
    else
        echo "  No cost data in state file"
    fi
    echo ""
fi

# Progress file
if [[ -f "$PROJECT_ROOT/progress.txt" ]]; then
    echo "--- Progress ---"
    tail -5 "$PROJECT_ROOT/progress.txt" | sed 's/^/  /'
    echo ""
fi

# Routing decisions
if [[ -f "$PROJECT_ROOT/logs/routing-decisions.log" ]]; then
    echo "--- Routing Decisions ---"
    tail -20 "$PROJECT_ROOT/logs/routing-decisions.log" | sed 's/^/  /'
    echo ""
fi

# Git status
echo "--- Git ---"
branch=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
uncommitted=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null | wc -l || echo 0)
echo "  Branch:      $branch"
echo "  Uncommitted: $uncommitted files"

# Detailed cost breakdown (only with --show-costs)
if [[ "$SHOW_COSTS" == true && -f "$STATE_FILE" ]]; then
    echo ""
    echo "--- Cost Details ---"
    jq -r '
        .costs // {} | to_entries | sort_by(.key | tonumber) |
        .[] | "  Batch \(.key): $\(.value.estimated_cost_usd) | \(.value.input_tokens) in | \(.value.output_tokens) out | cache: \(.value.cache_read_tokens) read | \(.value.model // "unknown")"
    ' "$STATE_FILE" 2>/dev/null || echo "  No cost data"
    total=$(jq -r '.total_cost_usd // 0' "$STATE_FILE")
    echo "  Total: \$${total}"
    echo ""
fi

echo ""
echo "═══════════════════════════════════════════════"
