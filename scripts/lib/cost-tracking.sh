#!/usr/bin/env bash
# cost-tracking.sh — Per-batch cost tracking via Claude CLI JSONL session files
#
# Claude CLI stores session data in JSONL files at:
#   ~/.claude/projects/<project>/<session-id>.jsonl
# The last line with type "summary" contains token counts and cost.
#
# Functions:
#   find_session_jsonl <session_id> <claude_dir>  -> path to JSONL file (empty if not found)
#   extract_session_cost <session_id> <claude_dir> -> JSON: {input_tokens, output_tokens, cache_read_tokens, estimated_cost_usd, model, tracking_status}
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
        # Fix #39: tracking_status field distinguishes "broken tracking" from "true $0 cost"
        # Fix #36: use jq --arg to safely interpolate session_id (no JSON injection)
        echo "WARNING: cost-tracking: no JSONL file found for session $session_id" >&2
        jq -n --arg sid "$session_id" \
            '{input_tokens:0,output_tokens:0,cache_read_tokens:0,estimated_cost_usd:0,model:"unknown",session_id:$sid,tracking_status:"missing_file"}'
        return 0
    fi

    # Fix #35: || true prevents grep exit-1 from killing set -e callers when no summary line exists
    local summary
    summary=$(grep '"type":"summary"' "$jsonl_path" | tail -1 || true)

    if [[ -n "$summary" ]]; then
        # Fix #36: use jq --arg for session_id to prevent JSON injection
        # Fix #39: tracking_status:"found" confirms real data was retrieved
        echo "$summary" | jq -c --arg sid "$session_id" '{
            input_tokens: (.inputTokens // 0),
            output_tokens: (.outputTokens // 0),
            cache_read_tokens: (.cacheReadTokens // 0),
            estimated_cost_usd: (.costUSD // 0),
            model: (.model // "unknown"),
            session_id: $sid,
            tracking_status: "found"
        }'
    else
        # Fix #36: use jq --arg for session_id to prevent JSON injection
        # Fix #39: tracking_status:"no_summary" distinguishes from a real zero-cost session
        echo "WARNING: cost-tracking: JSONL file exists but has no summary line for session $session_id" >&2
        jq -n --arg sid "$session_id" \
            '{input_tokens:0,output_tokens:0,cache_read_tokens:0,estimated_cost_usd:0,model:"unknown",session_id:$sid,tracking_status:"no_summary"}'
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
    # Fix #37: trap ensures temp file is cleaned up even if jq fails
    trap 'rm -f "$tmp"' RETURN

    # Fix #41: (... | add) // 0 handles empty .costs object (add on [] returns null, not 0)
    jq --arg batch "$batch_num" --argjson cost "$cost_json" '
        .costs //= {} |
        .costs[$batch] = $cost |
        .total_cost_usd = (([.costs[].estimated_cost_usd] | add) // 0)
    ' "$sf" > "$tmp" && mv "$tmp" "$sf"
}

check_budget() {
    local worktree="$1" max_budget="$2"
    local sf="$worktree/.run-plan-state.json"

    if [[ ! -f "$sf" ]]; then
        return 0  # No state = no cost = under budget
    fi

    local total
    total=$(jq -r '.total_cost_usd // 0' "$sf" 2>/dev/null) || total=""

    # Fix #63: validate jq output is numeric — corrupted state must not bypass budget
    if [[ -z "$total" ]] || ! [[ "$total" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo "WARNING: cost-tracking: corrupted total_cost_usd='$total' in state file — treating as budget exceeded" >&2
        return 1
    fi

    # Fix #69: validate max_budget is numeric — prevent awk injection via CLI args
    if ! [[ "$max_budget" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo "ERROR: cost-tracking: invalid max_budget='$max_budget'" >&2
        return 1
    fi

    # Fix #40: check for bc; fall back to awk for float comparison if missing
    if ! command -v bc >/dev/null 2>&1; then
        echo "WARNING: cost-tracking: bc not found, using awk for budget comparison" >&2
        # Safe: both values validated as numeric above
        if awk "BEGIN {exit !(${total} > ${max_budget})}" 2>/dev/null; then
            echo "BUDGET EXCEEDED: \$${total} spent of \$${max_budget} limit" >&2
            return 1
        fi
        return 0
    fi

    # Compare using bc (bash can't do float comparison natively)
    if (( $(echo "$total > $max_budget" | bc -l) )); then
        echo "BUDGET EXCEEDED: \$${total} spent of \$${max_budget} limit" >&2
        return 1
    fi
    return 0
}

get_total_cost() {
    local worktree="$1"
    local sf="$worktree/.run-plan-state.json"

    if [[ ! -f "$sf" ]]; then
        echo "0"
        return 0
    fi

    local val
    val=$(jq -r '.total_cost_usd // 0' "$sf" 2>/dev/null) || val=""

    # Fix #63: validate output is numeric — don't silently return "0" on corrupted state
    if [[ -n "$val" ]] && [[ "$val" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        echo "$val"
    else
        echo "WARNING: cost-tracking: corrupted total_cost_usd='$val' in $sf" >&2
        echo "error"
        return 1
    fi
}
