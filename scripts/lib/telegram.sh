#!/usr/bin/env bash
# telegram.sh — Shared Telegram notification helpers
#
# Functions:
#   _load_telegram_env [env_file]  -> load TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
#   _send_telegram <message>       -> send via Telegram Bot API

_load_telegram_env() {
    local env_file="${1:-$HOME/.env}"

    if [[ ! -f "$env_file" ]]; then
        echo "WARNING: env file not found: $env_file" >&2
        return 1
    fi

    # Extract values and strip surrounding single or double quotes (#7).
    # .env files may store values as TELEGRAM_BOT_TOKEN="abc123" or
    # TELEGRAM_BOT_TOKEN='abc123' — the cut captures the raw quoted string.
    TELEGRAM_BOT_TOKEN=$(grep -E '^(export )?TELEGRAM_BOT_TOKEN=' "$env_file" | head -1 | sed 's/^export //' | cut -d= -f2- | sed "s/^['\"]//; s/['\"]$//")
    TELEGRAM_CHAT_ID=$(grep -E '^(export )?TELEGRAM_CHAT_ID=' "$env_file" | head -1 | sed 's/^export //' | cut -d= -f2- | sed "s/^['\"]//; s/['\"]$//")

    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        echo "WARNING: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not found in $env_file" >&2
        return 1
    fi

    export TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
}

_send_telegram() {
    local message="$1"

    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        echo "WARNING: Telegram credentials not set — skipping notification" >&2
        return 0
    fi

    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

    curl -s -X POST "$url" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message" \
        -d parse_mode="Markdown" \
        --max-time 10 > /dev/null 2>&1 || {
        echo "WARNING: Failed to send Telegram notification" >&2
        return 0
    }
}
