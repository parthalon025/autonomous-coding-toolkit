#!/usr/bin/env bash
# Test shared common.sh functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_exit() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    "$@" || actual_exit=$?
    TESTS=$((TESTS + 1))
    if [[ "$expected_exit" != "$actual_exit" ]]; then
        echo "FAIL: $desc"
        echo "  expected exit: $expected_exit"
        echo "  actual exit:   $actual_exit"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT

# === detect_project_type tests ===

# Python project (pyproject.toml)
mkdir -p "$WORK/py-proj"
touch "$WORK/py-proj/pyproject.toml"
val=$(detect_project_type "$WORK/py-proj")
assert_eq "detect_project_type: pyproject.toml -> python" "python" "$val"

# Python project (setup.py)
mkdir -p "$WORK/py-setup"
touch "$WORK/py-setup/setup.py"
val=$(detect_project_type "$WORK/py-setup")
assert_eq "detect_project_type: setup.py -> python" "python" "$val"

# Node project (package.json)
mkdir -p "$WORK/node-proj"
echo '{"name":"test"}' > "$WORK/node-proj/package.json"
val=$(detect_project_type "$WORK/node-proj")
assert_eq "detect_project_type: package.json -> node" "node" "$val"

# Makefile project
mkdir -p "$WORK/make-proj"
echo 'test:' > "$WORK/make-proj/Makefile"
val=$(detect_project_type "$WORK/make-proj")
assert_eq "detect_project_type: Makefile -> make" "make" "$val"

# Unknown project
mkdir -p "$WORK/empty"
val=$(detect_project_type "$WORK/empty")
assert_eq "detect_project_type: empty -> unknown" "unknown" "$val"

# === strip_json_fences tests ===

val=$(echo '```json
{"key":"value"}
```' | strip_json_fences)
assert_eq "strip_json_fences: removes fences" '{"key":"value"}' "$val"

val=$(echo '{"key":"value"}' | strip_json_fences)
assert_eq "strip_json_fences: plain JSON unchanged" '{"key":"value"}' "$val"

# === check_memory_available tests ===

# This test just verifies the function exists and returns 0/1
# We can't control actual memory, so test the interface
assert_exit "check_memory_available: runs without error" 0 \
    check_memory_available 0

# === require_command tests ===

assert_exit "require_command: bash exists" 0 \
    require_command "bash"

assert_exit "require_command: nonexistent-binary-xyz fails" 1 \
    require_command "nonexistent-binary-xyz"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
