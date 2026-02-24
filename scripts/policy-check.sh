#!/usr/bin/env bash
# policy-check.sh — Advisory policy checker
#
# Usage: policy-check.sh [--project-root <dir>] [--strict] [--scope <tags>]
#
# Reads policies/*.md and checks project files for violations.
# Advisory mode by default (always exits 0).
# --strict: exit 1 on any violation.
#
# Policy files are markdown with code blocks showing positive patterns.
# This script checks for the ABSENCE of positive patterns (anti-patterns).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="."
STRICT=false
SCOPE_FILTER=""
VIOLATIONS=0

usage() {
    cat <<'EOF'
policy-check.sh — Advisory policy checker

USAGE:
  policy-check.sh [OPTIONS]

OPTIONS:
  --project-root <dir>  Project to check (default: current directory)
  --strict              Exit 1 on violations (default: advisory, always exit 0)
  --scope <tags>        Comma-separated scope tags to filter policies
  -h, --help            Show this help

POLICIES:
  Reads from policies/ directory in the toolkit root.
  Each .md file defines positive patterns for a language or domain.

EXIT CODES:
  0  Advisory mode (default) — always exits 0, prints violations to stdout
  0  Strict mode — no violations found
  1  Strict mode — violations found
EOF
}

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --strict) STRICT=true; shift ;;
        --scope) SCOPE_FILTER="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) PROJECT_ROOT="$1"; shift ;;
    esac
done

if [[ ! -d "$PROJECT_ROOT" ]]; then
    echo "Error: project directory not found: $PROJECT_ROOT" >&2
    exit 1
fi

POLICY_DIR="$TOOLKIT_ROOT/policies"
if [[ ! -d "$POLICY_DIR" ]]; then
    echo "Error: policies directory not found: $POLICY_DIR" >&2
    exit 1
fi

# Detect project language
detect_language() {
    local dir="$1"
    local langs=""
    if [[ -f "$dir/setup.py" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/requirements.txt" ]]; then
        langs+="python "
    fi
    if [[ -f "$dir/package.json" ]]; then
        langs+="node "
    fi
    # Check for shell scripts
    if find "$dir" -maxdepth 2 -name '*.sh' -print -quit 2>/dev/null | grep -q .; then
        langs+="bash "
    fi
    if [[ -f "$dir/Makefile" ]]; then
        langs+="make "
    fi
    echo "$langs"
}

# Check: bash scripts have strict mode
check_bash_strict_mode() {
    local dir="$1"
    local count=0
    while IFS= read -r script; do
        [[ -z "$script" ]] && continue
        # Library files (sourced, not executed directly) inherit strict mode
        if [[ "$(basename "$(dirname "$script")")" == "lib" ]]; then
            continue
        fi
        if ! head -15 "$script" | grep -q 'set -.*e'; then
            echo "  POLICY: $script — missing strict mode (set -euo pipefail)"
            count=$((count + 1))
        fi
    done < <(find "$dir" -name '*.sh' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)
    return $count
}

# Check: bash scripts quote variables in conditionals
check_bash_quoting() {
    local dir="$1"
    local count=0
    while IFS= read -r script; do
        [[ -z "$script" ]] && continue
        # Look for unquoted $VAR in [[ ]] conditionals (simplified check)
        if grep -En '\[\[.*\$[A-Za-z_]+[^"}\]]' "$script" 2>/dev/null | grep -v '#' | head -3 | grep -q .; then
            echo "  POLICY: $script — possible unquoted variable in conditional"
            count=$((count + 1))
        fi
    done < <(find "$dir" -name '*.sh' -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)
    return $count
}

# Check: python files use closing() for sqlite
check_python_sqlite_closing() {
    local dir="$1"
    local count=0
    while IFS= read -r pyfile; do
        [[ -z "$pyfile" ]] && continue
        if grep -q 'sqlite3\.connect' "$pyfile" 2>/dev/null; then
            if ! grep -q 'closing(' "$pyfile" 2>/dev/null; then
                echo "  POLICY: $pyfile — sqlite3.connect without closing() context manager"
                count=$((count + 1))
            fi
        fi
    done < <(find "$dir" -name '*.py' -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null)
    return $count
}

# Check: python async defs have await
check_python_async_await() {
    local dir="$1"
    local count=0
    # This is a simplified heuristic — the lesson-scanner does deeper analysis
    while IFS= read -r pyfile; do
        [[ -z "$pyfile" ]] && continue
        # Find async def functions and check if they contain await
        if grep -q 'async def' "$pyfile" 2>/dev/null; then
            # Very rough check: file has async def but no await at all
            if ! grep -q 'await ' "$pyfile" 2>/dev/null; then
                echo "  POLICY: $pyfile — async def without any await (may be unnecessary async)"
                count=$((count + 1))
            fi
        fi
    done < <(find "$dir" -name '*.py' -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null)
    return $count
}

# Check: test files don't have hardcoded counts
check_test_hardcoded_counts() {
    local dir="$1"
    local count=0
    while IFS= read -r testfile; do
        [[ -z "$testfile" ]] && continue
        # Look for exact equality assertions on counts
        if grep -En 'assert.*==[[:space:]]*[0-9]{2,}|assertEquals.*[0-9]{2,}|-eq[[:space:]]+[0-9]{2,}' "$testfile" 2>/dev/null | head -3 | grep -q .; then
            echo "  POLICY: $testfile — possible hardcoded test count assertion"
            count=$((count + 1))
        fi
    done < <(find "$dir" \( -name 'test_*.py' -o -name '*_test.py' -o -name 'test-*.sh' -o -name '*.test.js' -o -name '*.test.ts' \) -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null)
    return $count
}

# Main
echo "POLICY CHECK: $PROJECT_ROOT"
echo ""

languages=$(detect_language "$PROJECT_ROOT")
echo "Detected languages: ${languages:-none}"
echo ""

# Run applicable checks
for policy_file in "$POLICY_DIR"/*.md; do
    policy_name=$(basename "$policy_file" .md)

    case "$policy_name" in
        universal)
            echo "Checking: universal policies"
            # Universal checks are mostly process-level, hard to check statically
            echo "  (process-level policies — checked by skill, not script)"
            echo ""
            ;;
        bash)
            if echo "$languages" | grep -q 'bash'; then
                echo "Checking: bash policies"
                violations_before=$VIOLATIONS
                check_bash_strict_mode "$PROJECT_ROOT" || VIOLATIONS=$((VIOLATIONS + $?))
                echo ""
            fi
            ;;
        python)
            if echo "$languages" | grep -q 'python'; then
                echo "Checking: python policies"
                check_python_sqlite_closing "$PROJECT_ROOT" || VIOLATIONS=$((VIOLATIONS + $?))
                check_python_async_await "$PROJECT_ROOT" || VIOLATIONS=$((VIOLATIONS + $?))
                echo ""
            fi
            ;;
        testing)
            echo "Checking: testing policies"
            check_test_hardcoded_counts "$PROJECT_ROOT" || VIOLATIONS=$((VIOLATIONS + $?))
            echo ""
            ;;
    esac
done

# Summary
echo "─────────────────────────────────────"
if [[ $VIOLATIONS -gt 0 ]]; then
    echo "POLICY CHECK: $VIOLATIONS violation(s) found"
    if [[ "$STRICT" == "true" ]]; then
        exit 1
    fi
else
    echo "POLICY CHECK: clean (no violations)"
fi

exit 0
