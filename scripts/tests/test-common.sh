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
trap 'rm -rf "$WORK"' EXIT

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

# Bash project detection (run-all-tests.sh)
mkdir -p "$WORK/bash-proj/scripts/tests"
echo '#!/bin/bash' > "$WORK/bash-proj/scripts/tests/run-all-tests.sh"
chmod +x "$WORK/bash-proj/scripts/tests/run-all-tests.sh"
val=$(detect_project_type "$WORK/bash-proj")
assert_eq "detect_project_type: bash project with run-all-tests.sh" "bash" "$val"

# Bash project with test-*.sh glob
mkdir -p "$WORK/bash-proj2/scripts/tests"
touch "$WORK/bash-proj2/scripts/tests/test-foo.sh"
val=$(detect_project_type "$WORK/bash-proj2")
assert_eq "detect_project_type: bash project with test-*.sh files" "bash" "$val"

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

# Test 1GB threshold: should also always pass on any real system
assert_exit "check_memory_available: threshold 1 always passes" 0 \
    check_memory_available 1

# Test that check_memory_available uses MB internally (not GB)
# Verify it doesn't use free -g (which truncates)
TESTS=$((TESTS + 1))
if grep -q 'free -g' "$SCRIPT_DIR/../lib/common.sh"; then
    echo "FAIL: check_memory_available should use free -m, not free -g"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: check_memory_available uses free -m (no free -g in common.sh)"
fi

# Test that check_memory_available returns exit 2 when free is unavailable
# Create a wrapper that hides the real free command
_test_no_free() {
    (
        # Prepend fake bin to PATH so awk is still available, but free outputs nothing
        local fake_bin
        fake_bin=$(mktemp -d)
        cat > "$fake_bin/free" <<'EOF'
#!/bin/bash
# Output nothing — simulates unavailability without breaking awk in PATH
EOF
        chmod +x "$fake_bin/free"
        PATH="$fake_bin:$PATH" check_memory_available 4
    )
}
assert_exit "check_memory_available: returns 2 when free unavailable" 2 \
    _test_no_free

# === detect_project_type nullglob safety (#24) ===

# Test that bash detection works even with nullglob set
mkdir -p "$WORK/bash-nullglob/scripts/tests"
touch "$WORK/bash-nullglob/scripts/tests/test-bar.sh"
val=$(shopt -s nullglob; detect_project_type "$WORK/bash-nullglob")
assert_eq "detect_project_type: bash detection works with nullglob set" "bash" "$val"

# Test that compgen -G is used instead of ls for glob detection
TESTS=$((TESTS + 1))
if grep -q 'compgen -G' "$SCRIPT_DIR/../lib/common.sh"; then
    echo "PASS: detect_project_type uses compgen -G (nullglob-safe)"
else
    echo "FAIL: detect_project_type should use compgen -G, not ls"
    FAILURES=$((FAILURES + 1))
fi

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
