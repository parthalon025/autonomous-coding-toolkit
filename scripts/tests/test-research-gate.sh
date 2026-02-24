#!/usr/bin/env bash
# Tests for research-gate.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$SCRIPT_DIR/../research-gate.sh"
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

# Test 1: No blocking issues → exit 0
cat > "$tmpdir/clear.json" <<'EOF'
{
  "feature": "test-feature",
  "blocking_issues": [],
  "warnings": [],
  "confidence_ratings": {"approach": "high"}
}
EOF
output=$("$GATE" "$tmpdir/clear.json" 2>&1) || true
exit_code=$?
assert "no blockers: exit 0" "0" "$exit_code"
echo "$output" | grep -q "clear"
assert "no blockers: says clear" "0" "$?"

# Test 2: All resolved blocking issues → exit 0
cat > "$tmpdir/resolved.json" <<'EOF'
{
  "feature": "test-feature",
  "blocking_issues": [
    {"issue": "missing dep", "resolved": true, "resolution": "installed"}
  ],
  "warnings": []
}
EOF
exit_code=0
"$GATE" "$tmpdir/resolved.json" > /dev/null 2>&1 || exit_code=$?
assert "resolved blockers: exit 0" "0" "$exit_code"

# Test 3: Unresolved blocking issues → exit 1
cat > "$tmpdir/blocked.json" <<'EOF'
{
  "feature": "test-feature",
  "blocking_issues": [
    {"issue": "no viable auth library", "resolved": false, "resolution": "evaluate alternatives"}
  ],
  "warnings": []
}
EOF
exit_code=0
"$GATE" "$tmpdir/blocked.json" > /dev/null 2>&1 || exit_code=$?
assert "unresolved blockers: exit 1" "1" "$exit_code"

# Test 4: --force overrides blockers → exit 0
exit_code=0
output=$("$GATE" "$tmpdir/blocked.json" --force 2>&1) || exit_code=$?
assert "--force: exit 0" "0" "$exit_code"
assert "--force: shows warning" "1" "$(echo "$output" | grep -c "WARNING.*force")"

# Test 5: Missing file → exit 1
exit_code=0
"$GATE" "$tmpdir/nonexistent.json" > /dev/null 2>&1 || exit_code=$?
assert "missing file: exit 1" "1" "$exit_code"

# Test 6: Invalid JSON → exit 1
echo "not json" > "$tmpdir/invalid.json"
exit_code=0
"$GATE" "$tmpdir/invalid.json" > /dev/null 2>&1 || exit_code=$?
assert "invalid JSON: exit 1" "1" "$exit_code"

# Test 7: --help → exit 0
exit_code=0
output=$("$GATE" --help 2>&1) || exit_code=$?
assert "--help: exit 0" "0" "$exit_code"
assert "--help: shows usage" "1" "$(echo "$output" | grep -c "USAGE")"

# Test 8: Warnings present but no blockers → exit 0
cat > "$tmpdir/warnings.json" <<'EOF'
{
  "feature": "test-feature",
  "blocking_issues": [],
  "warnings": ["deprecated API", "performance concern"]
}
EOF
exit_code=0
output=$("$GATE" "$tmpdir/warnings.json" 2>&1) || exit_code=$?
assert "warnings only: exit 0" "0" "$exit_code"
assert "warnings only: shows warning count" "1" "$(echo "$output" | grep -c "2 warning")"

# Test 9: No args → exit 1
exit_code=0
"$GATE" > /dev/null 2>&1 || exit_code=$?
assert "no args: exit 1" "1" "$exit_code"

# Test 10: Multiple unresolved + some resolved → exit 1
cat > "$tmpdir/mixed.json" <<'EOF'
{
  "feature": "test-feature",
  "blocking_issues": [
    {"issue": "resolved one", "resolved": true},
    {"issue": "still blocked", "resolved": false},
    {"issue": "also blocked", "resolved": false}
  ],
  "warnings": []
}
EOF
exit_code=0
output=$("$GATE" "$tmpdir/mixed.json" 2>&1) || exit_code=$?
assert "mixed blockers: exit 1" "1" "$exit_code"
assert "mixed blockers: shows count 2" "1" "$(echo "$output" | grep -c "2 unresolved")"

echo ""
echo "Results: $PASS/$TOTAL passed"
if [[ $FAIL -gt 0 ]]; then
    echo "FAILURES: $FAIL"
    exit 1
fi
echo "ALL PASSED"
