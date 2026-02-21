#!/usr/bin/env bash
# run-plan-notify.sh — Telegram notification helpers for run-plan
#
# Functions:
#   format_success_message <plan_name> <batch_num> <test_count> <prev_count> <duration> <mode>
#   format_failure_message <plan_name> <batch_num> <test_count> <failing_count> <error> <action>
#   notify_success (same args as format_success_message) — format + send
#   notify_failure (same args as format_failure_message) — format + send

# Source shared telegram functions
_NOTIFY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_NOTIFY_SCRIPT_DIR/telegram.sh"

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
