#!/usr/bin/env bash
# cost-tracking.sh — Per-batch cost tracking via Claude CLI JSONL session files
#
# Claude CLI stores session data in JSONL files at:
#   ~/.claude/projects/<project>/<session-id>.jsonl
# The last line with type "summary" contains token counts and cost.
#
# Functions:
#   find_session_jsonl <session_id> <claude_dir>  -> path to JSONL file (empty if not found)
#   extract_session_cost <session_id> <claude_dir> -> JSON: {input_tokens, output_tokens, cache_read_tokens, estimated_cost_usd, model}
#   record_batch_cost <worktree> <batch_num> <session_id> [claude_dir]  -> updates .run-plan-state.json
#   check_budget <worktree> <max_budget_usd>  -> exits 0 if under, 1 if over
#   get_total_cost <worktree>  -> prints total_cost_usd from state

find_session_jsonl() {
    local session_id="$1" claude_dir="$2"
    local found=""
    # Search all project directories for the session JSONL
    while IFS= read -r -d '' f; do
        found="$f"
        break
    done < <(find "$claude_dir" -name "${session_id}.jsonl" -print0 2>/dev/null)
    echo "$found"
}

extract_session_cost() {
    local session_id="$1" claude_dir="$2"
    local jsonl_path
    jsonl_path=$(find_session_jsonl "$session_id" "$claude_dir")

    if [[ -z "$jsonl_path" || ! -f "$jsonl_path" ]]; then
        # Return zero-cost JSON for missing sessions
        echo '{"input_tokens":0,"output_tokens":0,"cache_read_tokens":0,"estimated_cost_usd":0,"model":"unknown","session_id":"'"$session_id"'"}'
        return 0
    fi

    # Extract the summary line (last line with type "summary")
    local summary
    summary=$(grep '"type":"summary"' "$jsonl_path" | tail -1)

    if [[ -n "$summary" ]]; then
        echo "$summary" | jq -c '{
            input_tokens: (.inputTokens // 0),
            output_tokens: (.outputTokens // 0),
            cache_read_tokens: (.cacheReadTokens // 0),
            estimated_cost_usd: (.costUSD // 0),
            model: (.model // "unknown"),
            session_id: "'"$session_id"'"
        }'
    else
        # No summary line — return zeros
        echo '{"input_tokens":0,"output_tokens":0,"cache_read_tokens":0,"estimated_cost_usd":0,"model":"unknown","session_id":"'"$session_id"'"}'
    fi
}

record_batch_cost() {
    local worktree="$1" batch_num="$2" session_id="$3"
    local claude_dir="${4:-$HOME/.claude}"
    local sf="$worktree/.run-plan-state.json"

    if [[ ! -f "$sf" ]]; then
        echo "WARNING: No state file at $sf" >&2
        return 1
    fi

    local cost_json
    cost_json=$(extract_session_cost "$session_id" "$claude_dir")

    local tmp
    tmp=$(mktemp)

    # Add cost entry for this batch and update total
    jq --arg batch "$batch_num" --argjson cost "$cost_json" '
        .costs //= {} |
        .costs[$batch] = $cost |
        .total_cost_usd = ([.costs[].estimated_cost_usd] | add)
    ' "$sf" > "$tmp" && mv "$tmp" "$sf"
}

check_budget() {
    local worktree="$1" max_budget="$2"
    local sf="$worktree/.run-plan-state.json"

    if [[ ! -f "$sf" ]]; then
        return 0  # No state = no cost = under budget
    fi

    local total
    total=$(jq -r '.total_cost_usd // 0' "$sf")

    # Compare using bc (bash can't do float comparison)
    if (( $(echo "$total > $max_budget" | bc -l 2>/dev/null || echo 0) )); then
        echo "BUDGET EXCEEDED: \$${total} spent of \$${max_budget} limit" >&2
        return 1
    fi
    return 0
}

get_total_cost() {
    local worktree="$1"
    local sf="$worktree/.run-plan-state.json"
    jq -r '.total_cost_usd // 0' "$sf" 2>/dev/null || echo "0"
}
