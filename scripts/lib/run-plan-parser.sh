#!/usr/bin/env bash
# run-plan-parser.sh — Parse markdown plan files into batch/task structures
#
# Plan format:
#   ## Batch N: Title          <- batch boundary
#   ### Task M: Name           <- task within batch
#   [full text...]             <- extracted verbatim
#
# Functions:
#   count_batches <plan_file>                -> number of batches
#   get_batch_title <plan_file> <batch_num>  -> batch title text
#   get_batch_text <plan_file> <batch_num>   -> full batch content (tasks + text)
#   get_batch_task_count <plan_file> <batch_num> -> number of tasks in batch
#   is_critical_batch <plan_file> <batch_num>    -> exit 0 if tagged CRITICAL

count_batches() {
    local plan_file="$1"
    local count
    count=$(grep -cE '^## Batch [0-9]+' "$plan_file" 2>/dev/null || true)
    echo "${count:-0}"
}

get_batch_title() {
    local plan_file="$1" batch_num="$2"
    local line
    line=$(grep -E "^## Batch ${batch_num}:" "$plan_file" 2>/dev/null | head -1)
    if [[ -z "$line" ]]; then
        echo ""
        return
    fi
    # Strip "## Batch N: " prefix using bash parameter expansion
    echo "${line#\#\# Batch ${batch_num}: }"
}

get_batch_text() {
    local plan_file="$1" batch_num="$2"
    # Extract everything after "## Batch N" up to the next "## Batch" or EOF
    # Uses POSIX-compatible awk: $3 + 0 extracts batch number
    awk -v batch="$batch_num" '
        /^## Batch [0-9]+/ {
            n = $3 + 0
            if (n == batch) { printing = 1; next }
            else if (printing) { exit }
        }
        printing { print }
    ' "$plan_file"
}

get_batch_task_count() {
    local plan_file="$1" batch_num="$2"
    local text count
    text=$(get_batch_text "$plan_file" "$batch_num")
    if [[ -z "$text" ]]; then
        echo "0"
        return
    fi
    count=$(echo "$text" | grep -cE '^### Task [0-9]+' 2>/dev/null || true)
    echo "${count:-0}"
}

is_critical_batch() {
    local plan_file="$1" batch_num="$2"
    local header
    header=$(grep -E "^## Batch ${batch_num}:" "$plan_file" 2>/dev/null | head -1)
    [[ "$header" == *"CRITICAL"* ]]
}
