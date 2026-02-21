#!/usr/bin/env bash
# run-plan-notify.sh — Telegram notification helpers for run-plan
#
# Functions:
#   format_success_message <plan_name> <batch_num> <test_count> <prev_count> <duration> <mode>
#   format_failure_message <plan_name> <batch_num> <test_count> <failing_count> <error> <action>
#   notify_success (same args as format_success_message) — format + send
#   notify_failure (same args as format_failure_message) — format + send
#   _load_telegram_env [env_file]  — load TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
#   _send_telegram <message>       — send via Telegram Bot API

format_success_message() {
    local plan_name="$1" batch_num="$2" test_count="$3" prev_count="$4" duration="$5" mode="$6"
    local delta=$(( test_count - prev_count ))

    printf '%s — Batch %s ✓\nTests: %s (↑%s)\nDuration: %s\nMode: %s' \
        "$plan_name" "$batch_num" "$test_count" "$delta" "$duration" "$mode"
}

format_failure_message() {
    local plan_name="$1" batch_num="$2" test_count="$3" failing_count="$4" error="$5" action="$6"

    printf '%s — Batch %s ✗\nTests: %s (%s failing)\nError: %s\nAction: %s' \
        "$plan_name" "$batch_num" "$test_count" "$failing_count" "$error" "$action"
}

_load_telegram_env() {
    local env_file="${1:-$HOME/.env}"

    if [[ ! -f "$env_file" ]]; then
        echo "WARNING: env file not found: $env_file" >&2
        return 1
    fi

    TELEGRAM_BOT_TOKEN=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$env_file" | head -1 | cut -d= -f2-)
    TELEGRAM_CHAT_ID=$(grep -E '^TELEGRAM_CHAT_ID=' "$env_file" | head -1 | cut -d= -f2-)

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

notify_success() {
    local msg
    msg=$(format_success_message "$@")
    _send_telegram "$msg"
}

notify_failure() {
    local msg
    msg=$(format_failure_message "$@")
    _send_telegram "$msg"
}
