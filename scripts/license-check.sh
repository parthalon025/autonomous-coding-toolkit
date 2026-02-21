#!/usr/bin/env bash
# license-check.sh — Check dependencies for license compatibility
#
# Usage: license-check.sh [--project-root <dir>]
# Flags GPL/AGPL in MIT-licensed projects.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="."

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        -h|--help)
            echo "license-check.sh — Check dependency licenses"
            echo "Usage: license-check.sh [--project-root <dir>]"
            echo "Flags GPL/AGPL in MIT-licensed projects."
            exit 0 ;;
        *) echo "Unknown: $1" >&2; exit 1 ;;
    esac
done

cd "$PROJECT_ROOT"
project_type=$(detect_project_type ".")

echo "=== License Check ==="
violations=0

case "$project_type" in
    python)
        if [[ -d ".venv" ]] && command -v pip-licenses >/dev/null 2>&1; then
            echo "Checking Python dependencies..."
            gpl_deps=$(.venv/bin/python -m pip-licenses --format=csv 2>/dev/null | grep -iE 'GPL|AGPL' | grep -v 'LGPL' || true)
            if [[ -n "$gpl_deps" ]]; then
                echo "WARNING: GPL/AGPL dependencies found:"
                echo "$gpl_deps" | sed 's/^/  /'
                violations=$((violations + 1))
            else
                echo "  No GPL/AGPL dependencies"
            fi
        else
            echo "  pip-licenses not available — skipping"
        fi
        ;;
    node)
        if command -v npx >/dev/null 2>&1; then
            echo "Checking Node dependencies..."
            gpl_deps=$(npx license-checker --csv 2>/dev/null | grep -iE 'GPL|AGPL' | grep -v 'LGPL' || true)
            if [[ -n "$gpl_deps" ]]; then
                echo "WARNING: GPL/AGPL dependencies found:"
                echo "$gpl_deps" | head -10 | sed 's/^/  /'
                violations=$((violations + 1))
            else
                echo "  No GPL/AGPL dependencies"
            fi
        else
            echo "  license-checker not available — skipping"
        fi
        ;;
    *)
        echo "  No license check for project type: $project_type"
        ;;
esac

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "license-check: $violations issue(s) found"
    exit 1
fi

echo "license-check: CLEAN"
exit 0
