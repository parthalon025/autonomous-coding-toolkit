#!/bin/bash
# Batch audit across all project repos
# Usage: batch-audit.sh <projects-dir> [focus]
# Focus: stale-refs | security | test-coverage | naming | lessons | full (default: stale-refs)

set -euo pipefail

PROJECTS_DIR="${1:-}"
FOCUS="${2:-stale-refs}"

if [[ -z "$PROJECTS_DIR" || ! -d "$PROJECTS_DIR" ]]; then
    echo "Usage: batch-audit.sh <projects-dir> [focus]" >&2
    echo "Focus options: stale-refs | security | test-coverage | naming | lessons | full" >&2
    exit 1
fi

RESULTS_DIR="/tmp/batch-audit-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RESULTS_DIR"

echo "=== Batch Audit: $FOCUS ==="
echo "Results: $RESULTS_DIR"
echo ""

for PROJECT_DIR in "$PROJECTS_DIR"/*/; do
    [[ ! -d "$PROJECT_DIR" ]] && continue
    project="$(basename "$PROJECT_DIR")"

    echo "--- $project ---"
    RESULT_FILE="$RESULTS_DIR/$project.txt"

    claude -p "Run /audit $FOCUS on this project. Output the audit report only, no fixes." \
        --allowedTools "Bash,Read,Grep,Glob" \
        --cwd "$PROJECT_DIR" \
        --output-format text > "$RESULT_FILE" 2>&1 || true

    echo "  Findings saved to $RESULT_FILE"
    echo ""
done

echo "=== Complete ==="
echo "All results in: $RESULTS_DIR"
echo "Quick view: cat $RESULTS_DIR/*.txt"
