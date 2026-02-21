#!/usr/bin/env bash
# quality-gate.sh — Composite quality gate for Ralph loop --quality-checks
# Runs lesson check + project test suite in sequence, fails fast on first failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=""

usage() {
    cat <<'USAGE'
Usage: quality-gate.sh --project-root <dir>

Composite quality gate for the Ralph loop. Runs checks in order, stops at first failure.

Checks:
  1. Lesson check — runs lesson-check.sh on git-changed files in project root
  2. Project test suite — auto-detects pytest / npm test / make test
  3. Memory warning — warns if available memory < 4G (never fails)

Options:
  --project-root <dir>  Project directory to check (required)
  --help, -h            Show this help

Exit: 0 if all pass, 1 on first failure
USAGE
    exit 0
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root)
            PROJECT_ROOT="${2:-}"
            shift 2
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "quality-gate: unknown option: $1" >&2
            echo "Run with --help for usage." >&2
            exit 1
            ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "quality-gate: --project-root is required" >&2
    exit 1
fi

if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "quality-gate: directory not found: $PROJECT_ROOT" >&2
    exit 1
fi

cd "$PROJECT_ROOT"

# === Check 1: Lesson check on changed files ===
echo "=== Quality Gate: Lesson Check ==="
changed_files=$(git diff --name-only 2>/dev/null || true)
if [[ -n "$changed_files" ]]; then
    # Pass changed files as arguments (they're relative to project root, which is cwd)
    # shellcheck disable=SC2086
    if ! "$SCRIPT_DIR/lesson-check.sh" $changed_files; then
        echo ""
        echo "quality-gate: FAILED at lesson check"
        exit 1
    fi
else
    echo "lesson-check: no changed files — skipped"
fi

# === Check 2: Project test suite (auto-detect) ===
echo ""
echo "=== Quality Gate: Test Suite ==="
test_ran=0

if [[ -f pyproject.toml || -f setup.py || -f pytest.ini ]]; then
    echo "Detected: pytest project"
    .venv/bin/python -m pytest --timeout=120 -x -q
    test_ran=1
elif [[ -f package.json ]] && grep -q '"test"' package.json 2>/dev/null; then
    echo "Detected: npm project"
    npm test
    test_ran=1
elif [[ -f Makefile ]] && grep -q '^test:' Makefile 2>/dev/null; then
    echo "Detected: Makefile project"
    make test
    test_ran=1
fi

if [[ $test_ran -eq 0 ]]; then
    echo "No test suite detected (no pyproject.toml/setup.py/pytest.ini, no npm test script, no Makefile test target) — skipped"
fi

# === Check 3: Memory warning (advisory only) ===
echo ""
echo "=== Quality Gate: Memory Check ==="
available_gb=$(free -g | awk '/Mem:/{print $7}')
if [[ "$available_gb" -lt 4 ]]; then
    # Get more precise value for the message
    available_human=$(free -h | awk '/Mem:/{print $7}')
    echo "WARNING: Low memory (${available_human} available) — consider -n 0 for pytest"
else
    echo "Memory OK (${available_gb}G available)"
fi

echo ""
echo "quality-gate: ALL PASSED"
exit 0
