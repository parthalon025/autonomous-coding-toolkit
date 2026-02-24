#!/usr/bin/env bash
# Test quality-gate.sh — verifies refactored behavior using common.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QG="$SCRIPT_DIR/../quality-gate.sh"

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
    "$@" >/dev/null 2>&1 || actual_exit=$?
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

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if echo "$haystack" | grep -qF "$needle"; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  in: $(echo "$haystack" | head -5)"
        FAILURES=$((FAILURES + 1))
    fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# === CLI tests ===

assert_exit "no args exits 1" 1 bash "$QG"
assert_exit "--help exits 0" 0 bash "$QG" --help
assert_exit "nonexistent dir exits 1" 1 bash "$QG" --project-root /nonexistent/path

# === Sources common.sh ===

# Check that the script sources common.sh (grep for the source line)
TESTS=$((TESTS + 1))
if grep -q 'source.*lib/common.sh' "$QG"; then
    echo "PASS: quality-gate.sh sources lib/common.sh"
else
    echo "FAIL: quality-gate.sh sources lib/common.sh"
    echo "  expected: source line for lib/common.sh"
    FAILURES=$((FAILURES + 1))
fi

# === Python project detection via detect_project_type ===

# Create a minimal Python project with no actual test suite
# (so the test suite step will run but fail — we just care about detection)
mkdir -p "$WORK/py-proj"
touch "$WORK/py-proj/pyproject.toml"
# Create a fake .venv/bin/python that exits 0
mkdir -p "$WORK/py-proj/.venv/bin"
cat > "$WORK/py-proj/.venv/bin/python" <<'FAKE'
#!/bin/bash
echo "1 passed"
exit 0
FAKE
chmod +x "$WORK/py-proj/.venv/bin/python"

# Run quality-gate on the python project — lesson-check will be skipped (no git)
output=$(bash "$QG" --project-root "$WORK/py-proj" 2>&1) || true
assert_contains "detects pytest project" "Detected: pytest project" "$output"

# === Node project detection ===

mkdir -p "$WORK/node-proj"
echo '{"name":"test","scripts":{"test":"echo ok"}}' > "$WORK/node-proj/package.json"
output=$(bash "$QG" --project-root "$WORK/node-proj" 2>&1) || true
assert_contains "detects npm project" "Detected: npm project" "$output"

# === Lint check output (Python project with ruff) ===

output=$(bash "$QG" --project-root "$WORK/py-proj" 2>&1) || true
assert_contains "lint check section present" "Lint Check" "$output"

# === Lint check output (Node project — no eslint config → skipped) ===

output=$(bash "$QG" --project-root "$WORK/node-proj" 2>&1) || true
assert_contains "node lint skipped without config" "No eslint config found" "$output"

# === --quick flag skips lint ===

output=$(bash "$QG" --project-root "$WORK/py-proj" --quick 2>&1) || true
TESTS=$((TESTS + 1))
if echo "$output" | grep -qF "Lint Check"; then
    echo "FAIL: --quick skips lint check"
    echo "  Lint Check header should not appear with --quick"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: --quick skips lint check"
fi
assert_contains "--quick still runs tests" "Test Suite" "$output"
assert_contains "--quick still runs memory" "Memory Check" "$output"

# === --with-license flag adds license check ===

output=$(bash "$QG" --project-root "$WORK/py-proj" --with-license 2>&1) || true
assert_contains "--with-license runs license check" "License Check" "$output"

# === without --with-license, no license check ===

output=$(bash "$QG" --project-root "$WORK/py-proj" 2>&1) || true
TESTS=$((TESTS + 1))
# License Check should NOT appear in the quality-gate section headers
# (it may appear in lesson check output, so check for the specific gate header)
if echo "$output" | grep -qF "Quality Gate: License Check"; then
    echo "FAIL: no license check without --with-license"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: no license check without --with-license"
fi

# === --quick and --with-license combined ===

output=$(bash "$QG" --project-root "$WORK/py-proj" --quick --with-license 2>&1) || true
TESTS=$((TESTS + 1))
if echo "$output" | grep -qF "Lint Check"; then
    echo "FAIL: --quick --with-license skips lint"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: --quick --with-license skips lint"
fi
assert_contains "--quick --with-license keeps license" "License Check" "$output"

# === Memory check output ===

output=$(bash "$QG" --project-root "$WORK/py-proj" 2>&1) || true
# Should contain either "Memory OK" or "WARNING: Low memory" or "skipped"
TESTS=$((TESTS + 1))
if echo "$output" | grep -qE "(Memory OK|WARNING.*memory|WARNING.*Consider|Memory check skipped)"; then
    echo "PASS: memory check runs"
else
    echo "FAIL: memory check runs"
    echo "  expected memory check output"
    echo "  got: $output"
    FAILURES=$((FAILURES + 1))
fi

# Memory display should use decimal GB (e.g., "3.9G") not truncated integer
TESTS=$((TESTS + 1))
if echo "$output" | grep -qE 'Memory OK \([0-9]+\.[0-9]+G'; then
    echo "PASS: memory display uses decimal GB (MB-based, not truncated)"
else
    # On systems where free is unavailable, this is expected to skip
    if echo "$output" | grep -qF "Memory check skipped"; then
        echo "PASS: memory display skipped (free unavailable — acceptable)"
    else
        echo "FAIL: memory display should show decimal GB (e.g., 3.9G)"
        echo "  got: $(echo "$output" | grep -i memory)"
        FAILURES=$((FAILURES + 1))
    fi
fi

# quality-gate.sh should not use free -g (only free -m via common.sh)
TESTS=$((TESTS + 1))
if grep -q 'free -g' "$QG"; then
    echo "FAIL: quality-gate.sh should not use free -g (use free -m)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: quality-gate.sh does not use free -g"
fi

# === Word-splitting fix (#5): changed_files passed to lesson-check via array ===

TESTS=$((TESTS + 1))
# Should use readarray and "${changed_array[@]}" — not bare $changed_files
if grep -q 'readarray.*changed_array' "$QG" && grep -q '"${changed_array\[@\]}"' "$QG"; then
    echo "PASS: quality-gate passes files to lesson-check via array (no word-splitting, bug #5)"
else
    echo "FAIL: quality-gate should use readarray + \${changed_array[@]} for lesson-check args (bug #5)"
    FAILURES=$((FAILURES + 1))
fi

# The old unquoted $changed_files pattern must not be present
TESTS=$((TESTS + 1))
# Strip comment lines and look for the old unquoted expansion used as args
if grep -v '^\s*#' "$QG" | grep -q 'lesson-check.sh \$changed_files\b'; then
    echo "FAIL: quality-gate still passes unquoted \$changed_files to lesson-check (bug #5)"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: quality-gate does not pass unquoted \$changed_files to lesson-check"
fi

# === ast-grep section present in full mode (advisory, doesn't fail gate) ===

output=$(bash "$QG" --project-root "$WORK/py-proj" 2>&1) || true
TESTS=$((TESTS + 1))
if echo "$output" | grep -qiE "structural|ast-grep"; then
    echo "PASS: ast-grep section present in full mode"
else
    echo "FAIL: ast-grep section should be present in full mode"
    FAILURES=$((FAILURES + 1))
fi

# ast-grep section should be skipped in --quick mode
output=$(bash "$QG" --project-root "$WORK/py-proj" --quick 2>&1) || true
TESTS=$((TESTS + 1))
if echo "$output" | grep -qF "Structural Analysis"; then
    echo "FAIL: --quick should skip ast-grep structural analysis"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: --quick skips ast-grep structural analysis"
fi

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
