#!/usr/bin/env bash
# Test telegram.sh — ACT_ENV_FILE support
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Setup ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create a fake .env
cat > "$WORK/test.env" <<'ENV'
TELEGRAM_BOT_TOKEN=test-token-123
TELEGRAM_CHAT_ID=test-chat-456
ENV

# --- Test 1: ACT_ENV_FILE overrides default ---
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID 2>/dev/null || true
ACT_ENV_FILE="$WORK/test.env" source "$REPO_ROOT/scripts/lib/telegram.sh"
ACT_ENV_FILE="$WORK/test.env" _load_telegram_env
assert_eq "ACT_ENV_FILE loads token" "test-token-123" "$TELEGRAM_BOT_TOKEN"
assert_eq "ACT_ENV_FILE loads chat id" "test-chat-456" "$TELEGRAM_CHAT_ID"

# --- Test 2: Explicit argument still works ---
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID 2>/dev/null || true
_load_telegram_env "$WORK/test.env"
assert_eq "Explicit arg loads token" "test-token-123" "$TELEGRAM_BOT_TOKEN"

# --- Test 3: Missing file returns error ---
unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID 2>/dev/null || true
exit_code=0
_load_telegram_env "$WORK/nonexistent.env" 2>/dev/null || exit_code=$?
assert_eq "Missing env file returns 1" "1" "$exit_code"

report_results
