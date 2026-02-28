#!/usr/bin/env bash
# mab-run-data.sh — MAB prompt assembly, calibration, and data persistence helpers
#
# Functions:
#   assemble_agent_prompt <template> <work_unit> <prd_path> <arch_map> <lessons> <gate_cmd>
#   select_winner_with_gate_override <gate_a_exit> <gate_b_exit> <judge_winner>
#   prompt_human_calibration <winner> <perf_file>
#   update_mab_data <winner> <lesson> <batch_type>
#
# Requires: MAB_WORKTREE, MAB_BATCH to be set by the sourcing script.

# --- Template substitution ---
# Replaces {PLACEHOLDER} tokens in a prompt template with actual values.
#
# Args: <template> <work_unit> <prd_path> <arch_map_path> <mab_lessons> <quality_gate_cmd>
# Output: substituted string
assemble_agent_prompt() {
    local template="$1"
    local work_unit="$2"
    local prd_path="${3:-}"
    local arch_map_path="${4:-}"
    local mab_lessons="${5:-}"
    local quality_gate_cmd="${6:-}"

    local result="$template"
    result="${result//\{WORK_UNIT_DESCRIPTION\}/$work_unit}"
    result="${result//\{PRD_PATH\}/$prd_path}"
    result="${result//\{ARCH_MAP_PATH\}/$arch_map_path}"
    result="${result//\{MAB_LESSONS\}/$mab_lessons}"
    result="${result//\{QUALITY_GATE_CMD\}/$quality_gate_cmd}"

    echo "$result"
}

# --- Gate override logic ---
# If only one agent passes the quality gate, that agent wins regardless of judge.
#
# Args: <gate_a_exit> <gate_b_exit> <judge_winner>
# Output: "agent-a" | "agent-b" | "none" | <judge_winner>
select_winner_with_gate_override() {
    local gate_a="$1" gate_b="$2" judge_winner="$3"

    local a_passed=false b_passed=false
    [[ "$gate_a" -eq 0 ]] && a_passed=true
    [[ "$gate_b" -eq 0 ]] && b_passed=true

    if [[ "$a_passed" == true && "$b_passed" == false ]]; then
        echo "agent-a"
    elif [[ "$a_passed" == false && "$b_passed" == true ]]; then
        echo "agent-b"
    elif [[ "$a_passed" == false && "$b_passed" == false ]]; then
        echo "none"
    else
        # Both passed — use judge verdict
        echo "$judge_winner"
    fi
}

# --- Human calibration prompt ---
prompt_human_calibration() {
    local winner="$1" perf_file="$2"

    local cal_count cal_complete
    cal_count=$(jq -r '.calibration_count // 0' "$perf_file" 2>/dev/null || echo "0")
    cal_complete=$(jq -r '.calibration_complete // false' "$perf_file" 2>/dev/null || echo "false")

    if [[ "$cal_complete" == "true" ]]; then
        echo "$winner"
        return
    fi

    # Only prompt if stdin is a tty
    if [[ -t 0 ]]; then
        echo ""
        echo "  [CALIBRATION $((cal_count + 1))/10] Judge picked: $winner"
        echo "  [y] Accept  [a] Override → agent-a  [b] Override → agent-b  [n] Skip"
        read -r -p "  Choice: " choice < /dev/tty
        case "$choice" in
            y|Y) ;; # Accept judge verdict
            a|A) winner="agent-a" ;;
            b|B) winner="agent-b" ;;
            n|N) winner="none" ;;
        esac
    else
        echo "  [CALIBRATION] headless-auto-approved: $winner"
    fi

    # Increment calibration count
    local tmp
    tmp=$(mktemp)
    local new_count=$((cal_count + 1))
    if [[ "$new_count" -ge 10 ]]; then
        jq ".calibration_count = $new_count | .calibration_complete = true" "$perf_file" > "$tmp" && mv "$tmp" "$perf_file"
    else
        jq ".calibration_count = $new_count" "$perf_file" > "$tmp" && mv "$tmp" "$perf_file"
    fi

    echo "$winner"
}

# --- Update MAB data files ---
update_mab_data() {
    local winner="$1" lesson="$2" batch_type="$3"
    local perf_file="$MAB_WORKTREE/logs/strategy-perf.json"
    local lessons_file="$MAB_WORKTREE/logs/mab-lessons.json"

    # Update strategy performance
    local winner_strategy
    if [[ "$winner" == "agent-a" ]]; then
        winner_strategy="superpowers"
    else
        winner_strategy="ralph"
    fi
    update_strategy_perf "$perf_file" "$batch_type" "$winner_strategy"

    # Record lesson if present
    if [[ -n "$lesson" ]]; then
        if [[ ! -f "$lessons_file" ]]; then
            echo "[]" > "$lessons_file"
        fi

        local tmp
        tmp=$(mktemp)
        jq --arg p "$lesson" --arg ctx "$batch_type" --arg w "$winner_strategy" '
            # Check if pattern already exists
            if [.[] | select(.pattern == $p)] | length > 0 then
                [.[] | if .pattern == $p then .occurrences += 1 | .last_seen = (now | tostring) else . end]
            else
                . + [{"pattern": $p, "context": $ctx, "winner": $w, "occurrences": 1, "last_seen": (now | tostring), "promoted": false}]
            end
        ' "$lessons_file" > "$tmp" && mv "$tmp" "$lessons_file"
    fi

    # Log the run
    local run_log="$MAB_WORKTREE/logs/mab-runs.log"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] batch=$MAB_BATCH type=$batch_type winner=$winner lesson=\"$lesson\"" >> "$run_log"
}
