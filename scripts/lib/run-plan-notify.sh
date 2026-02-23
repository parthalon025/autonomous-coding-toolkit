#!/usr/bin/env bash
# run-plan-notify.sh — Telegram notification helpers for run-plan
#
# Functions:
#   format_success_message <plan_name> <batch_num> <total_batches> <batch_title> <test_count> <prev_count> <duration> <mode> [summary]
#   format_failure_message <plan_name> <batch_num> <total_batches> <batch_title> <test_count> <failing_count> <error> <action>
#   notify_success (same args as format_success_message) — format + send
#   notify_failure (same args as format_failure_message) — format + send

# Source shared telegram functions
_NOTIFY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_NOTIFY_SCRIPT_DIR/telegram.sh"

format_success_message() {
    local plan_name="$1" batch_num="$2" total_batches="$3" batch_title="$4"
    local test_count="$5" prev_count="$6" duration="$7" mode="$8"
    local summary="${9:-}" cost="${10:-}"
    local delta=$(( test_count - prev_count ))

    local msg
    msg=$(printf '%s — Batch %s/%s ✓\n*%s*\nTests: %s (↑%s) | %s | %s' \
        "$plan_name" "$batch_num" "$total_batches" "$batch_title" \
        "$test_count" "$delta" "$duration" "$mode")

    if [[ -n "$cost" && "$cost" != "0" ]]; then
        msg+=" | \$${cost}"
    fi

    if [[ -n "$summary" ]]; then
        msg+=$'\n'"$summary"
    fi

    echo "$msg"
}

format_failure_message() {
    local plan_name="$1" batch_num="$2" total_batches="$3" batch_title="$4"
    local test_count="$5" failing_count="$6" error="$7" action="$8"

    printf '%s — Batch %s/%s ✗\n*%s*\nTests: %s (%s failing)\nIssue: %s\nAction: %s' \
        "$plan_name" "$batch_num" "$total_batches" "$batch_title" \
        "$test_count" "$failing_count" "$error" "$action"
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
