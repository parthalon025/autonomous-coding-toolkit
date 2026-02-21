#!/usr/bin/env bash
# quality-gate.sh — Composite quality gate for Ralph loop --quality-checks
# Runs lesson check + project test suite in sequence, fails fast on first failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
PROJECT_ROOT=""
QUICK=false
WITH_LICENSE=false

usage() {
    cat <<'USAGE'
Usage: quality-gate.sh --project-root <dir> [--quick] [--with-license]

Composite quality gate for the Ralph loop. Runs checks in order, stops at first failure.

Checks:
  1. Lesson check — runs lesson-check.sh on git-changed files in project root
  2. Lint check — ruff (Python) or eslint (Node) if available (skipped with --quick)
  3. Project test suite — auto-detects pytest / npm test / make test
  4. License check — flags GPL/AGPL deps (only with --with-license, skipped with --quick)
  5. Memory warning — warns if available memory < 4G (never fails)

Options:
  --project-root <dir>  Project directory to check (required)
  --quick               Skip lint and license checks (fast inner-loop mode)
  --with-license        Include dependency license audit
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
        --quick)
            QUICK=true
            shift
            ;;
        --with-license)
            WITH_LICENSE=true
            shift
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

# === Check 2: Lint Check (skipped with --quick) ===
if [[ "$QUICK" != true ]]; then
    echo ""
    echo "=== Quality Gate: Lint Check ==="
    lint_ran=0

    case "$(detect_project_type "$PROJECT_ROOT")" in
        python)
            if command -v ruff >/dev/null 2>&1; then
                echo "Running: ruff check --select E,W,F"
                if ! ruff check --select E,W,F "$PROJECT_ROOT" 2>/dev/null; then
                    echo ""
                    echo "quality-gate: FAILED at lint check"
                    exit 1
                fi
                lint_ran=1
            else
                echo "ruff not installed — skipping Python lint"
            fi
            ;;
        node)
            if [[ -f "$PROJECT_ROOT/.eslintrc" || -f "$PROJECT_ROOT/.eslintrc.js" || -f "$PROJECT_ROOT/.eslintrc.json" || -f "$PROJECT_ROOT/eslint.config.js" ]]; then
                echo "Running: npx eslint"
                if ! npx eslint "$PROJECT_ROOT" 2>/dev/null; then
                    echo ""
                    echo "quality-gate: FAILED at lint check"
                    exit 1
                fi
                lint_ran=1
            else
                echo "No eslint config found — skipping Node lint"
            fi
            ;;
    esac

    if [[ $lint_ran -eq 0 ]]; then
        echo "No linter configured — skipped"
    fi
fi

# === Check 3: Project test suite (auto-detect) ===
echo ""
echo "=== Quality Gate: Test Suite ==="
test_ran=0

project_type=$(detect_project_type "$PROJECT_ROOT")
case "$project_type" in
    python)
        echo "Detected: pytest project"
        .venv/bin/python -m pytest --timeout=120 -x -q
        test_ran=1
        ;;
    node)
        if grep -q '"test"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
            echo "Detected: npm project"
            npm test
            test_ran=1
        fi
        ;;
    make)
        if grep -q '^test:' "$PROJECT_ROOT/Makefile" 2>/dev/null; then
            echo "Detected: Makefile project"
            make test
            test_ran=1
        fi
        ;;
    bash)
        if [[ -x "$PROJECT_ROOT/scripts/tests/run-all-tests.sh" ]]; then
            echo "Detected: bash project (run-all-tests.sh)"
            "$PROJECT_ROOT/scripts/tests/run-all-tests.sh"
            test_ran=1
        fi
        ;;
esac

if [[ $test_ran -eq 0 ]]; then
    echo "No test suite detected (no pyproject.toml/setup.py/pytest.ini, no npm test script, no Makefile test target) — skipped"
fi

# === Check 4: License Check (only with --with-license, skipped with --quick) ===
if [[ "$WITH_LICENSE" == true ]]; then
    echo ""
    echo "=== Quality Gate: License Check ==="
    if ! "$SCRIPT_DIR/license-check.sh" --project-root "$PROJECT_ROOT"; then
        echo "quality-gate: FAILED at license check"
        exit 1
    fi
fi

# === Check 5: Memory warning (advisory only) ===
echo ""
echo "=== Quality Gate: Memory Check ==="
if check_memory_available 4; then
    available_gb=$(free -g | awk '/Mem:/{print $7}')
    echo "Memory OK (${available_gb}G available)"
else
    echo "WARNING: Consider -n 0 for pytest"
fi

echo ""
echo "quality-gate: ALL PASSED"
exit 0
