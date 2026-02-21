#!/usr/bin/env bash
# Test notification format functions (no actual Telegram sending)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-notify.sh"

FAILURES=0
TESTS=0

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        echo "  actual:              $haystack"
        FAILURES=$((FAILURES + 1))
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" == "$actual" ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    fi
}

# --- Test: format_success_message includes plan name ---
msg=$(format_success_message "my-feature" 3 10 "Context Assembler" 2003 1953 "4m12s" "headless" "")
assert_contains "success includes plan name" "my-feature" "$msg"

# --- Test: format_success_message includes batch X/Y ---
assert_contains "success includes batch X/Y" "Batch 3/10" "$msg"

# --- Test: format_success_message includes batch title ---
assert_contains "success includes batch title" "Context Assembler" "$msg"

# --- Test: format_success_message includes check mark ---
assert_contains "success includes check mark" "✓" "$msg"

# --- Test: format_success_message includes test count ---
assert_contains "success includes test count" "2003" "$msg"

# --- Test: format_success_message includes delta with up arrow ---
assert_contains "success includes delta" "↑50" "$msg"

# --- Test: format_success_message delta calculation: 2003 - 1953 = 50 ---
TESTS=$((TESTS + 1))
if [[ "$msg" == *"↑50"* ]] && [[ "$msg" != *"↑500"* ]]; then
    echo "PASS: delta is exactly 50"
else
    echo "FAIL: delta should be exactly 50 (2003 - 1953)"
    echo "  message: $msg"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: format_success_message includes duration ---
assert_contains "success includes duration" "4m12s" "$msg"

# --- Test: format_success_message includes mode ---
assert_contains "success includes mode" "headless" "$msg"

# --- Test: format_success_message with summary ---
msg=$(format_success_message "my-feature" 1 5 "Quick Fixes" 100 90 "2m30s" "headless" "Added 3 tests, fixed parser")
assert_contains "success includes summary" "Added 3 tests, fixed parser" "$msg"

# --- Test: format_failure_message includes plan name ---
msg=$(format_failure_message "my-feature" 2 8 "ast-grep Rules" 45 3 "pytest failed" "Fix test_auth.py")
assert_contains "failure includes plan name" "my-feature" "$msg"

# --- Test: format_failure_message includes batch X/Y ---
assert_contains "failure includes batch X/Y" "Batch 2/8" "$msg"

# --- Test: format_failure_message includes batch title ---
assert_contains "failure includes batch title" "ast-grep Rules" "$msg"

# --- Test: format_failure_message includes cross mark ---
assert_contains "failure includes cross mark" "✗" "$msg"

# --- Test: format_failure_message includes test count ---
assert_contains "failure includes test count" "45" "$msg"

# --- Test: format_failure_message includes failing count ---
assert_contains "failure includes failing count" "3 failing" "$msg"

# --- Test: format_failure_message includes error as Issue ---
assert_contains "failure includes issue text" "pytest failed" "$msg"

# --- Test: format_failure_message includes action ---
assert_contains "failure includes action" "Fix test_auth.py" "$msg"

# --- Test: _load_telegram_env warns on missing file ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

msg=$(_load_telegram_env "$WORK/.env-nonexistent" 2>&1 || true)
assert_contains "warns on missing env file" "warn" "$(echo "$msg" | tr '[:upper:]' '[:lower:]')"

# --- Test: _send_telegram warns on missing token ---
unset TELEGRAM_BOT_TOKEN 2>/dev/null || true
unset TELEGRAM_CHAT_ID 2>/dev/null || true
msg=$(_send_telegram "test message" 2>&1 || true)
assert_contains "send warns on missing credentials" "warn" "$(echo "$msg" | tr '[:upper:]' '[:lower:]')"

# --- Test: format_success_message with zero delta ---
msg=$(format_success_message "zero-delta" 1 1 "Single Batch" 100 100 "1m00s" "team" "")
assert_contains "zero delta shows ↑0" "↑0" "$msg"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
