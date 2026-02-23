#!/usr/bin/env bash
# pipeline-status.sh — Single-command view of Code Factory pipeline status
#
# Usage: pipeline-status.sh [--help] [project-root]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

SHOW_COSTS=false
PROJECT_ROOT=""
for arg in "$@"; do
    case "$arg" in
        --show-costs) SHOW_COSTS=true ;;
        --help|-h) ;;
        *) PROJECT_ROOT="$arg" ;;
    esac
done
PROJECT_ROOT="${PROJECT_ROOT:-.}"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "pipeline-status.sh — Show Code Factory pipeline status"
    echo "Usage: pipeline-status.sh [project-root]"
    exit 0
fi

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

    # Cost tracking
    total_cost=$(jq -r '.total_cost_usd // 0' "$STATE_FILE")
    if [[ "$total_cost" != "0" ]]; then
        echo "  Cost:      \$${total_cost}"
        # Per-batch breakdown
        jq -r '.costs // {} | to_entries[] | "    Batch \(.key): $\(.value.estimated_cost_usd // 0) (\(.value.input_tokens // 0) in / \(.value.output_tokens // 0) out)"' "$STATE_FILE" 2>/dev/null || true
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
