#!/usr/bin/env bash
# Test cost tracking functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
source "$SCRIPT_DIR/../lib/run-plan-state.sh"
source "$SCRIPT_DIR/../lib/cost-tracking.sh"

# --- Setup ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create mock JSONL session directory
MOCK_SESSION_DIR="$WORK/.claude/projects/test-project"
mkdir -p "$MOCK_SESSION_DIR"

# Mock session JSONL with token usage data
MOCK_SESSION_ID="test-session-abc-123"
cat > "$MOCK_SESSION_DIR/${MOCK_SESSION_ID}.jsonl" << 'JSONL'
{"type":"summary","costUSD":0.0423,"durationMs":12345,"inputTokens":8500,"outputTokens":2100,"cacheReadTokens":3200,"cacheWriteTokens":1000,"model":"claude-sonnet-4-6"}
JSONL

# --- Test: find_session_jsonl locates file ---
result=$(find_session_jsonl "$MOCK_SESSION_ID" "$WORK/.claude")
assert_contains "find_session_jsonl: returns path" "$MOCK_SESSION_ID" "$result"

# --- Test: find_session_jsonl returns empty for missing session ---
result=$(find_session_jsonl "nonexistent-session" "$WORK/.claude")
assert_eq "find_session_jsonl: empty for missing" "" "$result"

# --- Test: extract_session_cost returns JSON with token fields ---
cost_json=$(extract_session_cost "$MOCK_SESSION_ID" "$WORK/.claude")
assert_contains "extract: has input_tokens" "input_tokens" "$cost_json"
assert_contains "extract: has output_tokens" "output_tokens" "$cost_json"
assert_contains "extract: has cache_read_tokens" "cache_read_tokens" "$cost_json"
assert_contains "extract: has estimated_cost_usd" "estimated_cost_usd" "$cost_json"

input_tokens=$(echo "$cost_json" | jq -r '.input_tokens')
assert_eq "extract: input_tokens value" "8500" "$input_tokens"

output_tokens=$(echo "$cost_json" | jq -r '.output_tokens')
assert_eq "extract: output_tokens value" "2100" "$output_tokens"

cache_read=$(echo "$cost_json" | jq -r '.cache_read_tokens')
assert_eq "extract: cache_read_tokens value" "3200" "$cache_read"

cost_usd=$(echo "$cost_json" | jq -r '.estimated_cost_usd')
assert_eq "extract: cost from JSONL summary" "0.0423" "$cost_usd"

# --- Test: extract_session_cost handles missing session ---
cost_json=$(extract_session_cost "nonexistent" "$WORK/.claude")
input_tokens=$(echo "$cost_json" | jq -r '.input_tokens')
assert_eq "extract: missing session returns 0 input_tokens" "0" "$input_tokens"

# --- Test: record_batch_cost writes to state ---
init_state "$WORK" "plan.md" "headless"
record_batch_cost "$WORK" 1 "$MOCK_SESSION_ID" "$WORK/.claude"

costs_batch_1=$(jq -r '.costs["1"].input_tokens' "$WORK/.run-plan-state.json")
assert_eq "record: batch 1 input_tokens in state" "8500" "$costs_batch_1"

cost_usd=$(jq -r '.costs["1"].estimated_cost_usd' "$WORK/.run-plan-state.json")
assert_eq "record: batch 1 cost_usd in state" "0.0423" "$cost_usd"

session_id=$(jq -r '.costs["1"].session_id' "$WORK/.run-plan-state.json")
assert_eq "record: batch 1 session_id in state" "$MOCK_SESSION_ID" "$session_id"

total_cost=$(jq -r '.total_cost_usd' "$WORK/.run-plan-state.json")
assert_eq "record: total_cost_usd updated" "0.0423" "$total_cost"

# --- Test: record_batch_cost accumulates across batches ---
MOCK_SESSION_ID_2="test-session-def-456"
cat > "$MOCK_SESSION_DIR/${MOCK_SESSION_ID_2}.jsonl" << 'JSONL'
{"type":"summary","costUSD":0.031,"durationMs":9000,"inputTokens":7200,"outputTokens":1800,"cacheReadTokens":5000,"cacheWriteTokens":500,"model":"claude-sonnet-4-6"}
JSONL

record_batch_cost "$WORK" 2 "$MOCK_SESSION_ID_2" "$WORK/.claude"

total_cost=$(jq -r '.total_cost_usd' "$WORK/.run-plan-state.json")
# 0.0423 + 0.031 = 0.0733
assert_eq "record: total_cost accumulates" "0.0733" "$total_cost"

# --- Test: check_budget returns 0 when under budget ---
assert_exit "check_budget: under budget returns 0" 0 check_budget "$WORK" "1.00"

# --- Test: check_budget returns 1 when over budget ---
assert_exit "check_budget: over budget returns 1" 1 check_budget "$WORK" "0.05"

# --- Test: get_total_cost returns accumulated cost ---
total=$(get_total_cost "$WORK")
assert_eq "get_total_cost: returns accumulated" "0.0733" "$total"

report_results
