#!/usr/bin/env bash
# quality-gate.sh — Composite quality gate for Ralph loop --quality-checks
# Runs lesson check + project test suite in sequence, fails fast on first failure.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
PROJECT_ROOT=""
QUICK=false
WITH_LICENSE=false

usage() {
    cat <<'USAGE'
Usage: quality-gate.sh --project-root <dir> [--quick] [--with-license]

Composite quality gate for the Ralph loop. Runs checks in order, stops at first failure.

Checks:
  0. Toolkit validation — runs validate-all.sh if present (toolkit self-check)
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

# === Check 0: Toolkit Self-Validation ===
# Only runs when quality-gate is invoked from the toolkit itself
if [[ -f "$PROJECT_ROOT/scripts/validate-all.sh" ]]; then
    echo "=== Quality Gate: Toolkit Validation ==="
    if ! bash "$PROJECT_ROOT/scripts/validate-all.sh"; then
        echo ""
        echo "quality-gate: FAILED at toolkit validation"
        exit 1
    fi
fi

# === Check 1: Lesson check on changed files ===
echo "=== Quality Gate: Lesson Check ==="
changed_files=$(git diff --name-only 2>/dev/null || true)
if [[ -n "$changed_files" ]]; then
    # Use an array to avoid word-splitting on filenames with spaces (#5).
    readarray -t changed_array <<< "$changed_files"
    if ! "$SCRIPT_DIR/lesson-check.sh" "${changed_array[@]}"; then
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

# === Check 2.5: ast-grep structural analysis (optional, advisory) ===
if [[ "$QUICK" != true ]]; then
    echo ""
    echo "=== Quality Gate: Structural Analysis (ast-grep) ==="
    if command -v ast-grep >/dev/null 2>&1; then
        PATTERNS_DIR="$SCRIPT_DIR/patterns"
        ast_violations=0
        if [[ -d "$PATTERNS_DIR" ]]; then
            for pattern_file in "$PATTERNS_DIR"/*.yml; do
                [[ -f "$pattern_file" ]] || continue
                matches=$(ast-grep scan --rule "$pattern_file" "$PROJECT_ROOT" 2>/dev/null || true)
                if [[ -n "$matches" ]]; then
                    echo "WARNING: $(basename "$pattern_file" .yml): $(echo "$matches" | wc -l) matches"
                    echo "$matches" | head -3
                    ast_violations=$((ast_violations + 1))
                fi
            done
        fi
        if [[ $ast_violations -gt 0 ]]; then
            echo "ast-grep: $ast_violations pattern(s) matched (advisory)"
        else
            echo "ast-grep: clean"
        fi
    else
        echo "ast-grep not installed — skipping structural analysis"
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
_mem_exit=0
check_memory_available 4 || _mem_exit=$?
if [[ $_mem_exit -eq 0 ]]; then
    available_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $7}')
    available_display=$(awk "BEGIN {printf \"%.1f\", ${available_mb:-0} / 1024}")
    echo "Memory OK (${available_display}G available)"
elif [[ $_mem_exit -eq 2 ]]; then
    echo "WARNING: Memory check skipped (cannot determine available memory)"
else
    echo "WARNING: Consider -n 0 for pytest"
fi

echo ""
echo "quality-gate: ALL PASSED"
exit 0
