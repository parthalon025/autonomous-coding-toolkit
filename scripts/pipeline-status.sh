#!/usr/bin/env bash
# pipeline-status.sh — Single-command view of Code Factory pipeline status
#
# Usage: pipeline-status.sh [--help] [project-root]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="${1:-.}"

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

# Git status
echo "--- Git ---"
branch=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
uncommitted=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null | wc -l || echo 0)
echo "  Branch:      $branch"
echo "  Uncommitted: $uncommitted files"

echo ""
echo "═══════════════════════════════════════════════"
