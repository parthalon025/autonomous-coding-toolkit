#!/bin/bash
# Run tests across all projects with memory awareness
# Usage: batch-test.sh <projects-dir> [project-name]
#
# Auto-detects test runner (pytest, npm test, make test) for each project.
# Checks available memory before running — skips full suite if < 4GB available.

set -euo pipefail

PROJECTS_DIR="${1:-}"
TARGET="${2:-}"

if [[ -z "$PROJECTS_DIR" || ! -d "$PROJECTS_DIR" ]]; then
    echo "Usage: batch-test.sh <projects-dir> [project-name]" >&2
    exit 1
fi

check_memory() {
    local avail_mb
    avail_mb=$(free -m | awk '/Mem:/{print $7}')
    if [ "$avail_mb" -lt 4000 ]; then
        echo "WARNING: Low memory (${avail_mb}MB). Consider running targeted tests."
        return 1
    fi
    return 0
}

run_project_tests() {
    local project_dir="$1"
    local project
    project="$(basename "$project_dir")"

    if [ ! -d "$project_dir" ]; then
        echo "SKIP: $project (not found)"
        return
    fi

    echo "=== $project ==="
    (
        cd "$project_dir"

        # Auto-detect test runner
        if [[ -f pyproject.toml || -f setup.py || -f pytest.ini ]]; then
            if check_memory; then
                .venv/bin/python -m pytest --timeout=120 -x -q 2>&1 || true
            else
                echo "Low memory — running with reduced parallelism"
                .venv/bin/python -m pytest --timeout=120 -x -q -n 0 2>&1 || true
            fi
        elif [[ -f package.json ]] && grep -q '"test"' package.json 2>/dev/null; then
            npm test 2>&1 || true
        elif [[ -f Makefile ]] && grep -q '^test:' Makefile 2>/dev/null; then
            make test 2>&1 || true
        else
            echo "  No test runner detected — skipped"
        fi
    )

    echo ""
}

if [[ -n "$TARGET" ]]; then
    run_project_tests "$PROJECTS_DIR/$TARGET"
else
    for d in "$PROJECTS_DIR"/*/; do
        [[ -d "$d" ]] && run_project_tests "$d"
    done
fi

echo "=== Done ==="
