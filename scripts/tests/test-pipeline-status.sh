#!/usr/bin/env bash
# Test pipeline-status.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_SCRIPT="$SCRIPT_DIR/../pipeline-status.sh"

FAILURES=0
TESTS=0

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

# --- Test: --help exits 0 ---
assert_exit "pipeline-status --help exits 0" 0 \
    bash "$STATUS_SCRIPT" --help

# --- Test: runs on empty directory ---
mkdir -p "$WORK/empty-proj"
cd "$WORK/empty-proj" && git init --quiet
output=$(bash "$STATUS_SCRIPT" "$WORK/empty-proj" 2>&1) || true
assert_contains "shows Pipeline Status header" "Pipeline Status" "$output"
assert_contains "shows no active run-plan" "No active run-plan" "$output"
assert_contains "shows no PRD" "No PRD found" "$output"

# --- Test: shows run-plan state when present ---
mkdir -p "$WORK/proj-with-state"
cd "$WORK/proj-with-state" && git init --quiet
cat > "$WORK/proj-with-state/.run-plan-state.json" <<'JSON'
{
  "plan_file": "docs/plans/test-plan.md",
  "mode": "headless",
  "current_batch": 2,
  "completed_batches": [1],
  "started_at": "2026-02-21T10:00:00Z",
  "last_quality_gate": {"passed": true, "test_count": 42}
}
JSON
output=$(bash "$STATUS_SCRIPT" "$WORK/proj-with-state" 2>&1) || true
assert_contains "shows plan file" "test-plan.md" "$output"
assert_contains "shows mode" "headless" "$output"
assert_contains "shows gate result" "passed=true" "$output"

# --- Test: shows PRD status when present ---
mkdir -p "$WORK/proj-with-state/tasks"
echo '[{"id":1,"passes":true},{"id":2,"passes":false},{"id":3,"passes":true}]' > "$WORK/proj-with-state/tasks/prd.json"
output=$(bash "$STATUS_SCRIPT" "$WORK/proj-with-state" 2>&1) || true
assert_contains "shows PRD counts" "2/3 passing" "$output"

# --- Test: shows routing decisions when log exists ---
mkdir -p "$WORK/proj-with-state/logs"
echo "[14:30:01] MODE: headless mode selected" > "$WORK/proj-with-state/logs/routing-decisions.log"
echo "[14:30:02] MODEL: batch 1 routed to sonnet" >> "$WORK/proj-with-state/logs/routing-decisions.log"
output=$(bash "$STATUS_SCRIPT" "$WORK/proj-with-state" 2>&1) || true
assert_contains "shows routing decisions header" "Routing Decisions" "$output"
assert_contains "shows routing log content" "headless mode selected" "$output"

# --- Test: no routing section when log missing ---
rm -f "$WORK/proj-with-state/logs/routing-decisions.log"
output=$(bash "$STATUS_SCRIPT" "$WORK/proj-with-state" 2>&1) || true
TESTS=$((TESTS + 1))
if echo "$output" | grep -qF "Routing Decisions"; then
    echo "FAIL: no routing section when log missing"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: no routing section when log missing"
fi

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
