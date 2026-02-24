#!/usr/bin/env bash
# Tests for policy-check.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_CHECK="$SCRIPT_DIR/../policy-check.sh"
PASS=0 FAIL=0 TOTAL=0

assert() {
    local desc="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo "PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $desc (expected=$expected, actual=$actual)"
        FAIL=$((FAIL + 1))
    fi
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Test 1: --help exits 0
exit_code=0
output=$("$POLICY_CHECK" --help 2>&1) || exit_code=$?
assert "--help: exit 0" "0" "$exit_code"
echo "$output" | grep -q "USAGE"
assert "--help: shows usage" "0" "$?"

# Test 2: Missing project dir exits 1
exit_code=0
"$POLICY_CHECK" --project-root "$tmpdir/nonexistent" > /dev/null 2>&1 || exit_code=$?
assert "missing dir: exit 1" "1" "$exit_code"

# Test 3: Clean bash project (with strict mode)
mkdir -p "$tmpdir/clean-bash"
cat > "$tmpdir/clean-bash/example.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
echo "hello"
SCRIPT
exit_code=0
output=$("$POLICY_CHECK" --project-root "$tmpdir/clean-bash" 2>&1) || exit_code=$?
assert "clean bash: exit 0" "0" "$exit_code"
echo "$output" | grep -q "no violations"
assert "clean bash: clean output" "0" "$?"

# Test 4: Bash script missing strict mode (advisory)
mkdir -p "$tmpdir/bad-bash"
cat > "$tmpdir/bad-bash/bad.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "no strict mode"
SCRIPT
exit_code=0
output=$("$POLICY_CHECK" --project-root "$tmpdir/bad-bash" 2>&1) || exit_code=$?
assert "bad bash advisory: exit 0" "0" "$exit_code"
echo "$output" | grep -q "missing strict mode"
assert "bad bash advisory: shows violation" "0" "$?"

# Test 5: Bash script missing strict mode (strict mode)
exit_code=0
"$POLICY_CHECK" --project-root "$tmpdir/bad-bash" --strict > /dev/null 2>&1 || exit_code=$?
assert "bad bash strict: exit 1" "1" "$exit_code"

# Test 6: Python project with sqlite but no closing()
mkdir -p "$tmpdir/bad-python"
touch "$tmpdir/bad-python/requirements.txt"
cat > "$tmpdir/bad-python/db.py" <<'PYCODE'
import sqlite3
conn = sqlite3.connect("test.db")
cursor = conn.execute("SELECT 1")
conn.close()
PYCODE
exit_code=0
output=$("$POLICY_CHECK" --project-root "$tmpdir/bad-python" 2>&1) || exit_code=$?
assert "python sqlite no closing: exit 0 (advisory)" "0" "$exit_code"
echo "$output" | grep -q "closing"
assert "python sqlite: shows violation" "0" "$?"

# Test 7: Python project with closing() (clean)
mkdir -p "$tmpdir/good-python"
touch "$tmpdir/good-python/requirements.txt"
cat > "$tmpdir/good-python/db.py" <<'PYCODE'
import sqlite3
from contextlib import closing
with closing(sqlite3.connect("test.db")) as conn:
    cursor = conn.execute("SELECT 1")
PYCODE
exit_code=0
output=$("$POLICY_CHECK" --project-root "$tmpdir/good-python" 2>&1) || exit_code=$?
assert "python sqlite with closing: exit 0" "0" "$exit_code"

# Test 8: Empty directory (no language detected)
mkdir -p "$tmpdir/empty"
exit_code=0
output=$("$POLICY_CHECK" --project-root "$tmpdir/empty" 2>&1) || exit_code=$?
assert "empty dir: exit 0" "0" "$exit_code"

# Test 9: Test file with hardcoded count
mkdir -p "$tmpdir/bad-tests"
cat > "$tmpdir/bad-tests/test-example.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
count=42
assert "test count" -eq 42
SCRIPT
exit_code=0
output=$("$POLICY_CHECK" --project-root "$tmpdir/bad-tests" 2>&1) || exit_code=$?
assert "hardcoded count: exit 0 (advisory)" "0" "$exit_code"

# Test 10: Strict mode with no violations
exit_code=0
output=$("$POLICY_CHECK" --project-root "$tmpdir/clean-bash" --strict 2>&1) || exit_code=$?
assert "strict clean: exit 0" "0" "$exit_code"

echo ""
echo "Results: $PASS/$TOTAL passed"
if [[ $FAIL -gt 0 ]]; then
    echo "FAILURES: $FAIL"
    exit 1
fi
echo "ALL PASSED"
