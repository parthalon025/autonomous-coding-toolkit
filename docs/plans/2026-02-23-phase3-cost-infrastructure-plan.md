# Phase 3: Cost Infrastructure — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add per-batch cost tracking via JSONL session file parsing, prompt prefix/suffix splitting for cache optimization, and structured progress.txt format.

**Architecture:** Three new library files (`cost-tracking.sh`, `progress-writer.sh`, updated `run-plan-prompt.sh`) with integration into the headless execution loop, pipeline status display, and notification system. All cost data stored in `.run-plan-state.json` alongside existing test_counts and durations.

**Tech Stack:** Bash, jq, Claude CLI JSONL session files

---

## Batch 1: Per-Batch Cost Tracking (Tasks 1-7)

### Task 1: Write failing tests for cost extraction

**Files:**
- Create: `scripts/tests/test-cost-tracking.sh`

**Step 1: Write the test file**

```bash
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
assert_contains "extract: has cache_read_tokens" "$cost_json" "cache_read_tokens"
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
check_budget "$WORK" "1.00"
assert_exit "check_budget: under budget returns 0" 0 check_budget "$WORK" "1.00"

# --- Test: check_budget returns 1 when over budget ---
assert_exit "check_budget: over budget returns 1" 1 check_budget "$WORK" "0.05"

# --- Test: get_total_cost returns accumulated cost ---
total=$(get_total_cost "$WORK")
assert_eq "get_total_cost: returns accumulated" "0.0733" "$total"

report_results
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-cost-tracking.sh`
Expected: FAIL (source cost-tracking.sh not found)

**Step 3: Commit test file**

```bash
git add scripts/tests/test-cost-tracking.sh
git commit -m "test: add failing tests for cost-tracking.sh"
```

### Task 2: Implement cost-tracking.sh

**Files:**
- Create: `scripts/lib/cost-tracking.sh`

**Step 1: Write the implementation**

```bash
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
    # Fall back to aggregating individual message usage if no summary line
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
```

**Step 2: Run tests**

Run: `bash scripts/tests/test-cost-tracking.sh`
Expected: PASS (all assertions)

**Step 3: Commit**

```bash
git add scripts/lib/cost-tracking.sh
git commit -m "feat: add cost-tracking.sh — JSONL session file parsing for per-batch cost"
```

### Task 3: Update init_state to include costs schema

**Files:**
- Modify: `scripts/lib/run-plan-state.sh:25-38`

**Step 1: Write failing test (append to test-run-plan-state.sh)**

Add to the end of `scripts/tests/test-run-plan-state.sh` (before the results block):

```bash
# --- Test: init_state includes costs object ---
WORK_COST=$(mktemp -d)
trap 'rm -rf "$WORK" "$WORK2" "$WORK3" "$WORK4" "$WORK5" "$WORK6" "$WORK7" "$WORK_COST"' EXIT
init_state "$WORK_COST" "plan.md" "headless"

val=$(jq -r '.costs | type' "$WORK_COST/.run-plan-state.json")
assert_eq "init_state: has costs object" "object" "$val"

val=$(jq -r '.total_cost_usd' "$WORK_COST/.run-plan-state.json")
assert_eq "init_state: total_cost_usd starts at 0" "0" "$val"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-run-plan-state.sh`
Expected: FAIL on "has costs object" (currently no costs field in init_state)

**Step 3: Update init_state in run-plan-state.sh**

In `scripts/lib/run-plan-state.sh`, modify the `jq -n` call inside `init_state()` (lines 25-38) to add the `costs` and `total_cost_usd` fields:

```bash
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
```

**Step 4: Run tests**

Run: `bash scripts/tests/test-run-plan-state.sh`
Expected: ALL PASSED

**Step 5: Commit**

```bash
git add scripts/lib/run-plan-state.sh scripts/tests/test-run-plan-state.sh
git commit -m "feat: add costs and total_cost_usd to state schema"
```

### Task 4: Wire cost tracking into headless execution loop

**Files:**
- Modify: `scripts/run-plan.sh:48` (add source)
- Modify: `scripts/lib/run-plan-headless.sh:380-389` (capture session_id, record cost)
- Modify: `scripts/lib/run-plan-headless.sh:280-283` (capture session_id for sampling)

**Step 1: Source cost-tracking in run-plan.sh**

In `scripts/run-plan.sh`, after line 48 (`source "$SCRIPT_DIR/lib/run-plan-scoring.sh"`), add:

```bash
source "$SCRIPT_DIR/lib/cost-tracking.sh"
```

**Step 2: Modify main claude -p call to capture session_id**

In `scripts/lib/run-plan-headless.sh`, replace the main `claude -p` block (lines 380-385):

From:
```bash
            # Run claude headless (unset CLAUDECODE to allow nested invocation)
            local claude_exit=0
            CLAUDECODE='' claude -p "$full_prompt" \
                --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
                --permission-mode bypassPermissions \
                2>&1 | tee "$log_file" || claude_exit=$?
```

To:
```bash
            # Run claude headless (unset CLAUDECODE to allow nested invocation)
            # Use --output-format json to capture session_id for cost tracking
            local claude_exit=0
            local claude_json_output=""
            claude_json_output=$(CLAUDECODE='' claude -p "$full_prompt" \
                --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
                --permission-mode bypassPermissions \
                --output-format json \
                2>"$log_file.stderr") || claude_exit=$?

            # Extract session_id and result from JSON output
            local batch_session_id=""
            if [[ -n "$claude_json_output" ]]; then
                batch_session_id=$(echo "$claude_json_output" | jq -r '.session_id // empty' 2>/dev/null || true)
                # Write result text to log file (was previously done by tee)
                echo "$claude_json_output" | jq -r '.result // empty' 2>/dev/null > "$log_file" || true
                # Append stderr to log
                cat "$log_file.stderr" >> "$log_file" 2>/dev/null || true
            fi
            rm -f "$log_file.stderr"
```

**Step 3: Record cost after quality gate passes**

In `scripts/lib/run-plan-headless.sh`, inside the `if [[ $gate_exit -eq 0 ]]` block (after line 418), add cost recording:

```bash
                # Record cost for this batch
                if [[ -n "$batch_session_id" ]]; then
                    record_batch_cost "$WORKTREE" "$batch" "$batch_session_id" || \
                        echo "WARNING: Failed to record batch cost (non-fatal)" >&2
                fi
```

**Step 4: Wire --max-budget enforcement**

In `scripts/lib/run-plan-headless.sh`, at the top of the batch loop body (after the SAMPLE_COUNT reset around line 140), add budget check:

```bash
        # Budget enforcement
        if [[ -n "${MAX_BUDGET:-}" ]]; then
            if ! check_budget "$WORKTREE" "$MAX_BUDGET"; then
                echo "STOPPING: Budget limit reached (\$${MAX_BUDGET})"
                exit 1
            fi
        fi
```

**Step 5: Run make ci**

Run: `make ci`
Expected: ALL PASSED (no regression)

**Step 6: Commit**

```bash
git add scripts/run-plan.sh scripts/lib/run-plan-headless.sh
git commit -m "feat: wire cost tracking into headless loop — capture session_id, record per-batch cost"
```

### Task 5: Add cost section to pipeline-status.sh

**Files:**
- Modify: `scripts/pipeline-status.sh:38-43`
- Modify: `scripts/tests/test-pipeline-status.sh`

**Step 1: Read existing pipeline-status test**

Read: `scripts/tests/test-pipeline-status.sh` to understand test pattern.

**Step 2: Add cost display to pipeline-status.sh**

In `scripts/pipeline-status.sh`, after the "Last gate" line (line 42), before the `echo ""`, add:

```bash
    # Cost tracking
    total_cost=$(jq -r '.total_cost_usd // 0' "$STATE_FILE")
    if [[ "$total_cost" != "0" ]]; then
        echo "  Cost:      \$${total_cost}"
        # Per-batch breakdown
        jq -r '.costs // {} | to_entries[] | "    Batch \(.key): $\(.value.estimated_cost_usd // 0) (\(.value.input_tokens // 0) in / \(.value.output_tokens // 0) out)"' "$STATE_FILE" 2>/dev/null || true
    fi
```

**Step 3: Add --show-costs flag**

In `scripts/pipeline-status.sh`, add argument parsing at the top (after PROJECT_ROOT assignment):

```bash
SHOW_COSTS=false
for arg in "$@"; do
    case "$arg" in
        --show-costs) SHOW_COSTS=true ;;
    esac
done
```

And add a detailed cost section at the end (before final separator):

```bash
# Detailed cost breakdown (only with --show-costs)
if [[ "$SHOW_COSTS" == true && -f "$STATE_FILE" ]]; then
    echo "--- Cost Details ---"
    jq -r '
        .costs // {} | to_entries | sort_by(.key | tonumber) |
        .[] | "  Batch \(.key): $\(.value.estimated_cost_usd) | \(.value.input_tokens) in | \(.value.output_tokens) out | cache: \(.value.cache_read_tokens) read | \(.value.model // "unknown")"
    ' "$STATE_FILE" 2>/dev/null || echo "  No cost data"
    total=$(jq -r '.total_cost_usd // 0' "$STATE_FILE")
    echo "  Total: \$${total}"
    echo ""
fi
```

**Step 4: Run tests**

Run: `bash scripts/tests/test-pipeline-status.sh`
Expected: ALL PASSED

**Step 5: Commit**

```bash
git add scripts/pipeline-status.sh
git commit -m "feat: add cost display to pipeline-status.sh with --show-costs flag"
```

### Task 6: Add cost to Telegram notifications

**Files:**
- Modify: `scripts/lib/run-plan-notify.sh:14-29`

**Step 1: Update format_success_message to accept cost parameter**

In `scripts/lib/run-plan-notify.sh`, modify `format_success_message` to add an optional 10th parameter for cost:

```bash
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
```

**Step 2: Update the notify_success call in run-plan-headless.sh**

In the success notification block (around line 428 of `run-plan-headless.sh`), pass cost as the 10th arg:

```bash
                        local batch_cost=""
                        batch_cost=$(jq -r ".costs[\"$batch\"].estimated_cost_usd // empty" "$WORKTREE/.run-plan-state.json" 2>/dev/null || true)
                        notify_success "$plan_name" "$batch" "$END_BATCH" "$title" "$new_test_count" "$prev_test_count" "$duration" "$MODE" "$batch_summary" "$batch_cost"
```

**Step 3: Run notification tests**

Run: `bash scripts/tests/test-run-plan-notify.sh`
Expected: ALL PASSED

**Step 4: Commit**

```bash
git add scripts/lib/run-plan-notify.sh scripts/lib/run-plan-headless.sh
git commit -m "feat: add cost to Telegram success notifications"
```

### Task 7: Run full CI and verify

**Step 1: Run make ci**

Run: `make ci`
Expected: ALL PASSED (40+ test files, 0 failures)

**Step 2: Commit any fixes if needed**

---

## Batch 2: Prompt Caching Structure (Tasks 8-11)

### Task 8: Write failing tests for prefix/suffix split

**Files:**
- Modify: `scripts/tests/test-run-plan-prompt.sh`

**Step 1: Add prefix/suffix tests to test-run-plan-prompt.sh**

Append before the results section:

```bash
# =============================================================================
# Stable prefix / variable suffix split tests
# =============================================================================

# --- Test: build_stable_prefix produces consistent output ---
prefix1=$(build_stable_prefix "$FIXTURE" "$WORKTREE" "/usr/bin/python3" "scripts/quality-gate.sh" 0)
prefix2=$(build_stable_prefix "$FIXTURE" "$WORKTREE" "/usr/bin/python3" "scripts/quality-gate.sh" 0)
assert_eq "stable prefix: identical across calls" "$prefix1" "$prefix2"

# --- Test: build_stable_prefix is different from build_variable_suffix ---
suffix1=$(build_variable_suffix "$FIXTURE" 1 "$WORKTREE" 0)
assert_not_contains "prefix does not contain batch tasks" "Task 1: Create Data Model" "$prefix1"
assert_contains "suffix contains batch tasks" "Task 1: Create Data Model" "$suffix1"

# --- Test: build_variable_suffix changes with batch number ---
suffix2=$(build_variable_suffix "$FIXTURE" 2 "$WORKTREE" 0)
assert_not_contains "suffix batch 2: no batch 1 tasks" "Create Data Model" "$suffix2"
assert_contains "suffix batch 2: has batch 2 tasks" "Wire Together" "$suffix2"

# --- Test: build_batch_prompt still works (backward compat) ---
full_prompt=$(build_batch_prompt "$FIXTURE" 1 "$WORKTREE" "/usr/bin/python3" "scripts/quality-gate.sh" 0)
assert_contains "full prompt: still has XML tags" "<batch_tasks>" "$full_prompt"
assert_contains "full prompt: still has requirements" "<requirements>" "$full_prompt"

# --- Test: prefix contains metadata, suffix contains batch-specific ---
assert_contains "prefix: has working directory" "$WORKTREE" "$prefix1"
assert_contains "prefix: has python path" "/usr/bin/python3" "$prefix1"
assert_contains "suffix: has <batch_tasks>" "<batch_tasks>" "$suffix1"
assert_contains "suffix: has <requirements>" "<requirements>" "$suffix1"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-run-plan-prompt.sh`
Expected: FAIL (build_stable_prefix not defined)

**Step 3: Commit**

```bash
git add scripts/tests/test-run-plan-prompt.sh
git commit -m "test: add failing tests for prompt prefix/suffix split"
```

### Task 9: Implement prefix/suffix split in run-plan-prompt.sh

**Files:**
- Modify: `scripts/lib/run-plan-prompt.sh:12-127`

**Step 1: Add build_stable_prefix and build_variable_suffix functions**

Add these two new functions before the existing `build_batch_prompt` function. Then refactor `build_batch_prompt` to compose them.

```bash
# Build the stable portion of the prompt (identical across batches — enables API cache hits).
# Args: <plan_file> <worktree> <python> <quality_gate_cmd> <prev_test_count>
build_stable_prefix() {
    local plan_file="$1"
    local worktree="$2"
    local python="$3"
    local quality_gate_cmd="$4"
    local prev_test_count="$5"

    local branch
    branch=$(git -C "$worktree" branch --show-current 2>/dev/null || echo "unknown")

    local prefix=""
    prefix+="You are implementing batches from ${plan_file}."$'\n'
    prefix+=""$'\n'
    prefix+="Working directory: ${worktree}"$'\n'
    prefix+="Python: ${python}"$'\n'
    prefix+="Branch: ${branch}"$'\n'
    prefix+=""$'\n'
    prefix+="<requirements>"$'\n'
    prefix+="- TDD: write test -> verify fail -> implement -> verify pass -> commit each task"$'\n'
    prefix+="- After all tasks: run quality gate (${quality_gate_cmd})"$'\n'
    prefix+="- Update progress.txt with batch summary and commit"$'\n'
    prefix+="- All ${prev_test_count}+ tests must pass"$'\n'
    prefix+="</requirements>"$'\n'

    printf '%s' "$prefix"
}

# Build the variable portion of the prompt (changes each batch).
# Args: <plan_file> <batch_num> <worktree> <prev_test_count>
build_variable_suffix() {
    local plan_file="$1"
    local batch_num="$2"
    local worktree="$3"
    local prev_test_count="$4"

    local title batch_text
    title=$(get_batch_title "$plan_file" "$batch_num")
    batch_text=$(get_batch_text "$plan_file" "$batch_num")

    local recent_commits progress_tail prev_gate

    recent_commits=$(git -C "$worktree" log --oneline -5 2>/dev/null || echo "(no commits)")

    progress_tail=""
    if [[ -f "$worktree/progress.txt" ]]; then
        progress_tail=$(tail -20 "$worktree/progress.txt" 2>/dev/null || true)
    fi

    prev_gate=""
    if [[ -f "$worktree/.run-plan-state.json" ]]; then
        prev_gate=$(jq -r '.last_quality_gate // empty' "$worktree/.run-plan-state.json" 2>/dev/null || true)
    fi

    # Context refs
    local context_refs_content=""
    local refs
    refs=$(get_batch_context_refs "$plan_file" "$batch_num")
    if [[ -n "$refs" ]]; then
        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            if [[ -f "$worktree/$ref" ]]; then
                context_refs_content+="
--- $ref ---
$(head -100 "$worktree/$ref")
"
            fi
        done <<< "$refs"
    fi

    # Research warnings
    local research_warnings=""
    for rj in "$worktree"/tasks/research-*.json; do
        [[ -f "$rj" ]] || continue
        local warnings
        warnings=$(jq -r '.blocking_issues[]? // empty' "$rj" 2>/dev/null || true)
        if [[ -n "$warnings" ]]; then
            research_warnings+="$warnings"$'\n'
        fi
    done

    local suffix=""
    suffix+="Now implementing Batch ${batch_num}: ${title}"$'\n'
    suffix+=""$'\n'
    suffix+="<batch_tasks>"$'\n'
    suffix+="${batch_text}"$'\n'
    suffix+="</batch_tasks>"$'\n'

    suffix+=""$'\n'
    suffix+="<prior_context>"$'\n'
    suffix+="Recent commits:"$'\n'
    suffix+="${recent_commits}"$'\n'
    if [[ -n "$progress_tail" ]]; then
        suffix+=""$'\n'
        suffix+="<prior_progress>"$'\n'
        suffix+="${progress_tail}"$'\n'
        suffix+="</prior_progress>"$'\n'
    fi
    if [[ -n "$prev_gate" && "$prev_gate" != "null" ]]; then
        suffix+=""$'\n'
        suffix+="Previous quality gate: ${prev_gate}"$'\n'
    fi
    suffix+="</prior_context>"$'\n'

    if [[ -n "$context_refs_content" ]]; then
        suffix+=""$'\n'
        suffix+="<referenced_files>"$'\n'
        suffix+="${context_refs_content}"$'\n'
        suffix+="</referenced_files>"$'\n'
    fi

    if [[ -n "$research_warnings" ]]; then
        suffix+=""$'\n'
        suffix+="<research_warnings>"$'\n'
        suffix+="${research_warnings}"$'\n'
        suffix+="</research_warnings>"$'\n'
    fi

    printf '%s' "$suffix"
}
```

Then refactor `build_batch_prompt` to compose the two:

```bash
build_batch_prompt() {
    local plan_file="$1"
    local batch_num="$2"
    local worktree="$3"
    local python="$4"
    local quality_gate_cmd="$5"
    local prev_test_count="$6"

    local prefix suffix
    prefix=$(build_stable_prefix "$plan_file" "$worktree" "$python" "$quality_gate_cmd" "$prev_test_count")
    suffix=$(build_variable_suffix "$plan_file" "$batch_num" "$worktree" "$prev_test_count")

    printf '%s\n%s' "$prefix" "$suffix"
}
```

**Step 2: Run tests**

Run: `bash scripts/tests/test-run-plan-prompt.sh`
Expected: ALL PASSED (existing tests still pass + new prefix/suffix tests pass)

**Step 3: Commit**

```bash
git add scripts/lib/run-plan-prompt.sh
git commit -m "feat: split build_batch_prompt into stable prefix and variable suffix"
```

### Task 10: Write prefix to disk for reuse

**Files:**
- Modify: `scripts/lib/run-plan-headless.sh`

**Step 1: Cache prefix file at start of batch loop**

In `run_mode_headless()`, just before the batch `for` loop (around line 138), add:

```bash
    # Build and cache stable prompt prefix (reused across batches for API cache hits)
    local prev_test_count_initial
    prev_test_count_initial=$(get_previous_test_count "$WORKTREE")
    local stable_prefix
    stable_prefix=$(build_stable_prefix "$PLAN_FILE" "$WORKTREE" "$PYTHON" "$QUALITY_GATE_CMD" "$prev_test_count_initial")
    echo "$stable_prefix" > "$WORKTREE/.run-plan-prefix.txt"
```

**Step 2: Add .run-plan-prefix.txt to .gitignore if not already**

Check if `.gitignore` already covers it (likely via `.run-plan-*` pattern). If not, add it.

**Step 3: Commit**

```bash
git add scripts/lib/run-plan-headless.sh
git commit -m "feat: cache stable prompt prefix to disk for API cache optimization"
```

### Task 11: Run full CI

**Step 1: Run make ci**

Run: `make ci`
Expected: ALL PASSED

**Step 2: Commit any fixes**

---

## Batch 3: Structured progress.txt (Tasks 12-16)

### Task 12: Write failing tests for progress-writer.sh

**Files:**
- Create: `scripts/tests/test-progress-writer.sh`

**Step 1: Write the test file**

```bash
#!/usr/bin/env bash
# Test structured progress writer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
source "$SCRIPT_DIR/../lib/progress-writer.sh"

# --- Setup ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --- Test: write_batch_progress creates file with header ---
write_batch_progress "$WORK" 1 "Foundation"
assert_contains "creates progress.txt" "Batch 1" "$(cat "$WORK/progress.txt")"
assert_contains "has batch title" "Foundation" "$(cat "$WORK/progress.txt")"

# --- Test: append_progress_section adds to current batch ---
append_progress_section "$WORK" "Files Modified" "- src/models.py (created)"
assert_contains "has Files Modified section" "### Files Modified" "$(cat "$WORK/progress.txt")"
assert_contains "has file entry" "src/models.py (created)" "$(cat "$WORK/progress.txt")"

# --- Test: append_progress_section adds Decisions ---
append_progress_section "$WORK" "Decisions" "- Used jq for JSON parsing: lightweight, no deps"
assert_contains "has Decisions section" "### Decisions" "$(cat "$WORK/progress.txt")"

# --- Test: append_progress_section adds State ---
append_progress_section "$WORK" "State" "- Tests: 42 passing\n- Duration: 120s\n- Cost: \$0.42"
assert_contains "has State section" "### State" "$(cat "$WORK/progress.txt")"
assert_contains "has test count" "42 passing" "$(cat "$WORK/progress.txt")"

# --- Test: write_batch_progress for second batch appends ---
write_batch_progress "$WORK" 2 "Integration"
assert_contains "has batch 2 header" "Batch 2" "$(cat "$WORK/progress.txt")"
assert_contains "batch 1 still present" "Batch 1" "$(cat "$WORK/progress.txt")"

# --- Test: read_batch_progress extracts single batch ---
result=$(read_batch_progress "$WORK" 1)
assert_contains "read batch 1: has title" "Foundation" "$result"
assert_contains "read batch 1: has files section" "src/models.py" "$result"
assert_not_contains "read batch 1: no batch 2 content" "Integration" "$result"

# --- Test: read_batch_progress for nonexistent batch returns empty ---
result=$(read_batch_progress "$WORK" 99)
assert_eq "read batch 99: empty" "" "$result"

# --- Test: read_batch_progress for batch 2 ---
append_progress_section "$WORK" "Files Modified" "- src/api.py (created)"
result=$(read_batch_progress "$WORK" 2)
assert_contains "read batch 2: has title" "Integration" "$result"
assert_contains "read batch 2: has api.py" "src/api.py" "$result"

report_results
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-progress-writer.sh`
Expected: FAIL (source progress-writer.sh not found)

**Step 3: Commit**

```bash
git add scripts/tests/test-progress-writer.sh
git commit -m "test: add failing tests for progress-writer.sh"
```

### Task 13: Implement progress-writer.sh

**Files:**
- Create: `scripts/lib/progress-writer.sh`

**Step 1: Write the implementation**

```bash
#!/usr/bin/env bash
# progress-writer.sh — Structured progress.txt writer
#
# Replaces freeform progress.txt with defined sections per batch.
#
# Functions:
#   write_batch_progress <worktree> <batch_num> <title>  -> writes batch header
#   append_progress_section <worktree> <section> <content>  -> appends to current batch
#   read_batch_progress <worktree> <batch_num>  -> extracts single batch's content

write_batch_progress() {
    local worktree="$1" batch_num="$2" title="$3"
    local progress_file="$worktree/progress.txt"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    {
        echo ""
        echo "## Batch ${batch_num}: ${title} (${timestamp})"
    } >> "$progress_file"
}

append_progress_section() {
    local worktree="$1" section="$2" content="$3"
    local progress_file="$worktree/progress.txt"

    {
        echo "### ${section}"
        echo -e "$content"
        echo ""
    } >> "$progress_file"
}

read_batch_progress() {
    local worktree="$1" batch_num="$2"
    local progress_file="$worktree/progress.txt"

    if [[ ! -f "$progress_file" ]]; then
        return 0
    fi

    # Extract content between "## Batch N:" and the next "## Batch" or EOF
    awk -v batch="$batch_num" '
        /^## Batch / {
            if (found) exit
            if ($3 == batch":") found=1
        }
        found { print }
    ' "$progress_file"
}
```

**Step 2: Run tests**

Run: `bash scripts/tests/test-progress-writer.sh`
Expected: ALL PASSED

**Step 3: Commit**

```bash
git add scripts/lib/progress-writer.sh
git commit -m "feat: add progress-writer.sh — structured progress.txt format"
```

### Task 14: Source progress-writer in run-plan.sh

**Files:**
- Modify: `scripts/run-plan.sh`

**Step 1: Add source line**

In `scripts/run-plan.sh`, after the cost-tracking source line, add:

```bash
source "$SCRIPT_DIR/lib/progress-writer.sh"
```

**Step 2: Commit**

```bash
git add scripts/run-plan.sh
git commit -m "chore: source progress-writer.sh in run-plan.sh"
```

### Task 15: Update run-plan-context.sh to use read_batch_progress

**Files:**
- Modify: `scripts/lib/run-plan-context.sh:102-113`

**Step 1: Replace tail-based progress reading**

In `scripts/lib/run-plan-context.sh`, replace the progress.txt section (lines 102-113):

From:
```bash
    # 5. Progress.txt (if budget allows, last 10 lines)
    if [[ $(( chars_used + 500 )) -lt $TOKEN_BUDGET_CHARS ]]; then
        local progress_file="$worktree/progress.txt"
        if [[ -f "$progress_file" ]]; then
            local progress
            progress=$(tail -10 "$progress_file" 2>/dev/null || true)
            if [[ -n "$progress" ]]; then
                context+="### Progress Notes"$'\n'
                context+="$progress"$'\n\n'
            fi
        fi
    fi
```

To:
```bash
    # 5. Progress.txt — structured batch progress (last 2 batches)
    if [[ $(( chars_used + 500 )) -lt $TOKEN_BUDGET_CHARS ]]; then
        if [[ -f "$worktree/progress.txt" ]]; then
            # Try structured read first, fall back to tail
            local progress=""
            if type read_batch_progress &>/dev/null; then
                local start_batch=$(( batch_num - 2 ))
                [[ $start_batch -lt 1 ]] && start_batch=1
                for ((b = start_batch; b < batch_num; b++)); do
                    local bp
                    bp=$(read_batch_progress "$worktree" "$b" 2>/dev/null || true)
                    [[ -n "$bp" ]] && progress+="$bp"$'\n'
                done
            fi
            # Fallback to tail if no structured content
            if [[ -z "$progress" ]]; then
                progress=$(tail -10 "$worktree/progress.txt" 2>/dev/null || true)
            fi
            if [[ -n "$progress" ]]; then
                context+="### Progress Notes"$'\n'
                context+="$progress"$'\n\n'
            fi
        fi
    fi
```

**Step 2: Run context tests**

Run: `bash scripts/tests/test-run-plan-context.sh`
Expected: ALL PASSED

**Step 3: Commit**

```bash
git add scripts/lib/run-plan-context.sh
git commit -m "feat: use structured read_batch_progress in context injection"
```

### Task 16: Run full CI and final verification

**Step 1: Run make ci**

Run: `make ci`
Expected: ALL PASSED (42+ test files including 2 new ones, 0 failures)

**Step 2: Verify test count increased**

Run: `make ci 2>&1 | grep -E "TOTAL|PASSED|FAILED"`
Expected: TOTAL ≥ 42, PASSED = TOTAL, FAILED = 0

**Step 3: Commit any remaining fixes**

```bash
git add -A
git commit -m "fix: address any CI issues from Phase 3 integration"
```

---

## Summary

| Batch | Tasks | New Files | Modified Files |
|-------|-------|-----------|----------------|
| 1: Cost Tracking | 1-7 | `cost-tracking.sh`, `test-cost-tracking.sh` | `run-plan-state.sh`, `run-plan-headless.sh`, `run-plan.sh`, `pipeline-status.sh`, `run-plan-notify.sh` |
| 2: Prompt Caching | 8-11 | — | `run-plan-prompt.sh`, `run-plan-headless.sh`, `test-run-plan-prompt.sh` |
| 3: Structured Progress | 12-16 | `progress-writer.sh`, `test-progress-writer.sh` | `run-plan.sh`, `run-plan-context.sh` |
