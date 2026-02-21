#!/usr/bin/env bash
# Test telegram.sh shared library
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/telegram.sh"

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

# === _load_telegram_env tests ===

# Missing file
assert_exit "_load_telegram_env: missing file returns 1" 1 \
    _load_telegram_env "$WORK/nonexistent"

# File without keys
echo "SOME_OTHER_KEY=value" > "$WORK/empty.env"
assert_exit "_load_telegram_env: missing keys returns 1" 1 \
    _load_telegram_env "$WORK/empty.env"

# File with both keys
cat > "$WORK/valid.env" << 'ENVFILE'
TELEGRAM_BOT_TOKEN=test-token-123
TELEGRAM_CHAT_ID=test-chat-456
ENVFILE
assert_exit "_load_telegram_env: valid file returns 0" 0 \
    _load_telegram_env "$WORK/valid.env"
assert_eq "_load_telegram_env: token loaded" "test-token-123" "$TELEGRAM_BOT_TOKEN"
assert_eq "_load_telegram_env: chat_id loaded" "test-chat-456" "$TELEGRAM_CHAT_ID"

# === _send_telegram without credentials ===

unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
assert_exit "_send_telegram: no creds returns 0 (skip)" 0 \
    _send_telegram "test message"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
