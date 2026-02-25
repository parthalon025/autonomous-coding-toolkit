#!/usr/bin/env bash
# init.sh — Bootstrap a project for use with the Autonomous Coding Toolkit
#
# Usage: init.sh --project-root <dir> [--quickstart]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT=""
QUICKSTART=false

usage() {
    cat <<'USAGE'
Usage: init.sh --project-root <dir> [--quickstart]

Bootstrap a project for the Autonomous Coding Toolkit.

Creates:
  tasks/         — PRD and acceptance criteria
  logs/          — Telemetry, routing decisions, failure patterns
  progress.txt   — Append-only discovery log

Options:
  --project-root <dir>  Project directory to initialize (required)
  --quickstart          Copy quickstart plan + run quality gate
  --help, -h            Show this help
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
        --quickstart) QUICKSTART=true; shift ;;
        --help|-h) usage ;;
        *) echo "init: unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "init: --project-root is required" >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

echo "Autonomous Coding Toolkit — Project Init"
echo "========================================="
echo ""

# Detect project type
project_type=$(detect_project_type "$PROJECT_ROOT")
echo "Detected: $project_type project"

# Create directories
mkdir -p "$PROJECT_ROOT/tasks"
mkdir -p "$PROJECT_ROOT/logs"
mkdir -p "$PROJECT_ROOT/docs/plans"
echo "Created: tasks/, logs/, docs/plans/"

# Create progress.txt if missing
if [[ ! -f "$PROJECT_ROOT/progress.txt" ]]; then
    echo "# Progress — $(basename "$PROJECT_ROOT")" > "$PROJECT_ROOT/progress.txt"
    echo "# Append-only discovery log. Read at start of each batch." >> "$PROJECT_ROOT/progress.txt"
    echo "" >> "$PROJECT_ROOT/progress.txt"
    echo "Created: progress.txt"
else
    echo "Exists: progress.txt (skipped)"
fi

# Detect language for scope tags
scope_lang=""
case "$project_type" in
    python) scope_lang="language:python" ;;
    node) scope_lang="language:javascript" ;;
    bash) scope_lang="language:bash" ;;
    *) scope_lang="" ;;
esac

# Print next steps
echo ""
echo "--- Next Steps ---"
echo ""
echo "1. Quality gate:  act gate --project-root $PROJECT_ROOT"
echo "2. Run a plan:    act plan docs/plans/your-plan.md"

if [[ -n "$scope_lang" ]]; then
    echo ""
    echo "Recommended: Add to your CLAUDE.md:"
    echo "  ## Scope Tags"
    echo "  $scope_lang"
fi

# Quickstart mode
if [[ "$QUICKSTART" == true ]]; then
    echo ""
    echo "--- Quickstart ---"
    if [[ -f "$TOOLKIT_ROOT/examples/quickstart-plan.md" ]]; then
        cp "$TOOLKIT_ROOT/examples/quickstart-plan.md" "$PROJECT_ROOT/docs/plans/quickstart.md"
        echo "Copied: docs/plans/quickstart.md"
        echo ""
        echo "Run your first quality-gated execution:"
        echo "  act plan docs/plans/quickstart.md"
    else
        echo "WARNING: quickstart-plan.md not found in toolkit" >&2
    fi
fi

echo ""
echo "Init complete."
