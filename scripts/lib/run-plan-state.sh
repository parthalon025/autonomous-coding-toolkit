#!/usr/bin/env bash
# run-plan-state.sh — Track batch progress in a JSON state file
#
# State file: <worktree>/.run-plan-state.json
# Requires: jq
#
# Functions:
#   init_state <worktree> <plan_file> <mode>           -> create state file
#   read_state_field <worktree> <field>                 -> read top-level field
#   complete_batch <worktree> <batch_num> <test_count> [duration]  -> mark batch done
#   get_previous_test_count <worktree>                  -> last completed batch's test count (0 if none, -1 if missing)
#   set_quality_gate <worktree> <batch_num> <passed> <test_count> -> record quality gate result

_state_file() {
    echo "$1/.run-plan-state.json"
}

init_state() {
    local worktree="$1" plan_file="$2" mode="$3"
    local sf
    sf=$(_state_file "$worktree")
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq -n \
        --arg plan_file "$plan_file" \
        --arg mode "$mode" \
        --arg started_at "$now" \
        '{
            plan_file: $plan_file,
            mode: $mode,
            current_batch: 1,
            completed_batches: [],
            test_counts: {},
            durations: {},
            costs: {},
            total_cost_usd: 0,
            started_at: $started_at,
            last_quality_gate: null
        }' > "$sf"
}

read_state_field() {
    local worktree="$1" field="$2"
    local sf
    sf=$(_state_file "$worktree")
    jq -c -r --arg f "$field" '.[$f]' "$sf"
}

complete_batch() {
    local worktree="$1" batch_num="$2" test_count="$3" duration="${4:-0}"
    local sf tmp
    sf=$(_state_file "$worktree")
    tmp=$(mktemp)

    # batch_num may be non-numeric (e.g. 'final'), so use --arg and convert in jq.
    # current_batch is only meaningful for numeric batch sequences — it tracks
    # the next expected numeric batch. Non-numeric batches (like 'final') are
    # recorded in completed_batches and test_counts but do not advance current_batch.
    if [[ "$batch_num" =~ ^[0-9]+$ ]]; then
        jq \
            --argjson batch "$batch_num" \
            --argjson tc "$test_count" \
            --argjson dur "$duration" \
            '
            .completed_batches += [$batch] |
            .current_batch = ($batch + 1) |
            .test_counts[($batch | tostring)] = $tc |
            .durations[($batch | tostring)] = $dur
            ' "$sf" > "$tmp" && mv "$tmp" "$sf"
    else
        jq \
            --arg batch "$batch_num" \
            --argjson tc "$test_count" \
            --argjson dur "$duration" \
            '
            .completed_batches += [$batch] |
            .test_counts[$batch] = $tc |
            .durations[$batch] = $dur
            ' "$sf" > "$tmp" && mv "$tmp" "$sf"
    fi
}

get_previous_test_count() {
    local worktree="$1"
    local sf
    sf=$(_state_file "$worktree")

    jq -r '
        if (.completed_batches | length) == 0 then "0"
        else (.test_counts[(.completed_batches | last | tostring)] // -1) | tostring
        end
    ' "$sf"
}

set_quality_gate() {
    local worktree="$1" batch_num="$2" passed="$3" test_count="$4"
    local sf tmp now
    sf=$(_state_file "$worktree")
    tmp=$(mktemp)
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Normalize passed to a JSON boolean so --argjson never receives an
    # unexpected value (#8). Callers pass "true"/"false" conventionally, but
    # "1"/"0" or "yes"/"no" would crash jq with --argjson.
    if [[ "$passed" == "true" || "$passed" == "1" || "$passed" == "yes" ]]; then
        passed="true"
    else
        passed="false"
    fi

    # batch_num may be non-numeric (e.g. 'final'), so use --arg and convert in jq
    if [[ "$batch_num" =~ ^[0-9]+$ ]]; then
        jq \
            --argjson batch "$batch_num" \
            --argjson passed "$passed" \
            --argjson tc "$test_count" \
            --arg ts "$now" \
            '
            .last_quality_gate = {
                batch: $batch,
                passed: $passed,
                test_count: $tc,
                timestamp: $ts
            }
            ' "$sf" > "$tmp" && mv "$tmp" "$sf"
    else
        jq \
            --arg batch "$batch_num" \
            --argjson passed "$passed" \
            --argjson tc "$test_count" \
            --arg ts "$now" \
            '
            .last_quality_gate = {
                batch: $batch,
                passed: $passed,
                test_count: $tc,
                timestamp: $ts
            }
            ' "$sf" > "$tmp" && mv "$tmp" "$sf"
    fi
}
