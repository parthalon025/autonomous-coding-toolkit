#!/usr/bin/env bash
# Run tests across all projects with memory awareness
# Usage: batch-test.sh <projects-dir> [project-name]
#
# Auto-detects test runner (pytest, npm test, make test) for each project.
# Checks available memory before running — skips full suite if < 4GB available.
# Exits non-zero if any project's tests fail. Reports summary.

set -euo pipefail

PROJECTS_DIR="${1:-}"
TARGET="${2:-}"

if [[ -z "$PROJECTS_DIR" || ! -d "$PROJECTS_DIR" ]]; then
    echo "Usage: batch-test.sh <projects-dir> [project-name]" >&2
    exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILED_PROJECTS=()

check_memory() {
    local avail_mb
    avail_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $7}') || avail_mb=0
    if [[ -z "$avail_mb" || "$avail_mb" -lt 4000 ]]; then
        echo "WARNING: Low memory (${avail_mb:-unknown}MB). Consider running targeted tests."
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
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return 0
    fi

    echo "=== $project ==="
    local exit_code=0
    (
        cd "$project_dir"

        # Auto-detect test runner
        if [[ -f pyproject.toml || -f setup.py || -f pytest.ini ]]; then
            if check_memory; then
                .venv/bin/python -m pytest --timeout=120 -x -q 2>&1
            else
                echo "Low memory — running with reduced parallelism"
                .venv/bin/python -m pytest --timeout=120 -x -q -n 0 2>&1
            fi
        elif [[ -f package.json ]] && grep -q '"test"' package.json 2>/dev/null; then
            npm test 2>&1
        elif [[ -f Makefile ]] && grep -q '^test:' Makefile 2>/dev/null; then
            make test 2>&1
        else
            echo "  No test runner detected — skipped"
            exit 2  # Signal "skipped" to caller
        fi
    ) || exit_code=$?

    if [[ $exit_code -eq 2 ]]; then
        SKIP_COUNT=$((SKIP_COUNT + 1))
    elif [[ $exit_code -ne 0 ]]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_PROJECTS+=("$project")
        echo "  FAILED (exit $exit_code)"
    else
        PASS_COUNT=$((PASS_COUNT + 1))
    fi

    echo ""
    return 0  # Don't abort the loop — continue to next project
}

if [[ -n "$TARGET" ]]; then
    run_project_tests "$PROJECTS_DIR/$TARGET"
else
    for d in "$PROJECTS_DIR"/*/; do
        [[ -d "$d" ]] && run_project_tests "$d"
    done
fi

echo "=== Summary ==="
echo "  Passed: $PASS_COUNT"
echo "  Failed: $FAIL_COUNT"
echo "  Skipped: $SKIP_COUNT"
if [[ ${#FAILED_PROJECTS[@]} -gt 0 ]]; then
    echo "  Failed projects: ${FAILED_PROJECTS[*]}"
fi
echo "=== Done ==="

if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
fi
