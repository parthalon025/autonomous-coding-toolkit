#!/usr/bin/env bash
# mab-run.sh — MAB orchestrator: worktrees, competing agents, judge, merge
#
# Usage:
#   mab-run.sh --plan <file> --batch <N> --work-unit <desc> --worktree <dir> [options]
#   mab-run.sh --init-data --worktree <dir>
#   mab-run.sh --help
#
# Options:
#   --plan <file>         Implementation plan file
#   --batch <N>           Batch number to execute
#   --work-unit <desc>    Work unit description
#   --worktree <dir>      Base worktree directory
#   --dry-run             Show planned actions without executing
#   --init-data           Initialize strategy-perf.json and mab-lessons.json
#   --prd <file>          PRD file path (optional)
#   --quality-gate <cmd>  Quality gate command
#   -h, --help            Show this help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source dependencies
source "$SCRIPT_DIR/lib/thompson-sampling.sh"
if [[ -f "$SCRIPT_DIR/lib/run-plan-scoring.sh" ]]; then
    source "$SCRIPT_DIR/lib/run-plan-scoring.sh"
fi
if [[ -f "$SCRIPT_DIR/lib/run-plan-state.sh" ]]; then
    source "$SCRIPT_DIR/lib/run-plan-state.sh"
fi

# --- Defaults ---
MAB_PLAN=""
MAB_BATCH=""
MAB_WORK_UNIT=""
MAB_WORKTREE=""
MAB_DRY_RUN=false
MAB_INIT_DATA=false
MAB_PRD=""
MAB_QUALITY_GATE="scripts/quality-gate.sh --project-root ."
MAB_SOURCE_ONLY=false

# --- Usage ---
mab_usage() {
    cat <<'USAGE'
mab-run.sh — MAB orchestrator for competing agent strategies

Usage:
  mab-run.sh --plan <file> --batch <N> --work-unit <desc> --worktree <dir> [options]
  mab-run.sh --init-data --worktree <dir>

Runs two agents (superpowers + ralph) in parallel worktrees on the same work
unit. A judge agent evaluates both outputs. Quality gate override: if only one
agent passes, that agent wins regardless of judge verdict.

Options:
  --plan <file>         Implementation plan file
  --batch <N>           Batch number to execute
  --work-unit <desc>    Work unit description
  --worktree <dir>      Base worktree directory
  --dry-run             Show planned actions without executing
  --init-data           Initialize strategy-perf.json and mab-lessons.json
  --prd <file>          PRD file path (optional)
  --quality-gate <cmd>  Quality gate command
  -h, --help            Show this help
USAGE
}

# --- Argument parsing ---
parse_mab_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source-only)
                MAB_SOURCE_ONLY=true; shift ;;
            -h|--help)
                mab_usage; exit 0 ;;
            --plan)
                MAB_PLAN="$2"; shift 2 ;;
            --batch)
                MAB_BATCH="$2"; shift 2 ;;
            --work-unit)
                MAB_WORK_UNIT="$2"; shift 2 ;;
            --worktree)
                MAB_WORKTREE="$2"; shift 2 ;;
            --dry-run)
                MAB_DRY_RUN=true; shift ;;
            --init-data)
                MAB_INIT_DATA=true; shift ;;
            --prd)
                MAB_PRD="$2"; shift 2 ;;
            --quality-gate)
                MAB_QUALITY_GATE="$2"; shift 2 ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                mab_usage >&2
                exit 1 ;;
        esac
    done
}

# --- Validation ---
validate_mab_args() {
    if [[ "$MAB_INIT_DATA" == true ]]; then
        if [[ -z "$MAB_WORKTREE" ]]; then
            echo "ERROR: --init-data requires --worktree" >&2
            exit 1
        fi
        return
    fi

    if [[ -z "$MAB_PLAN" || ! -f "$MAB_PLAN" ]]; then
        echo "ERROR: --plan file required and must exist" >&2
        exit 1
    fi

    if [[ -z "$MAB_BATCH" ]]; then
        echo "ERROR: --batch required" >&2
        exit 1
    fi

    # Validate batch is numeric
    if ! [[ "$MAB_BATCH" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --batch must be a number (got: $MAB_BATCH)" >&2
        exit 1
    fi

    if [[ -z "$MAB_WORK_UNIT" ]]; then
        echo "ERROR: --work-unit required" >&2
        exit 1
    fi

    if [[ -z "$MAB_WORKTREE" ]]; then
        echo "ERROR: --worktree required" >&2
        exit 1
    fi
}

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

# --- Create MAB worktrees ---
create_mab_worktrees() {
    local base_worktree="$1" batch="$2"
    local branch_a="mab-agent-a-batch-${batch}"
    local branch_b="mab-agent-b-batch-${batch}"
    local wt_a="$base_worktree/.mab-worktrees/agent-a"
    local wt_b="$base_worktree/.mab-worktrees/agent-b"

    mkdir -p "$base_worktree/.mab-worktrees"

    # Clean up any leftover worktrees from previous runs
    git -C "$base_worktree" worktree remove "$wt_a" --force 2>/dev/null || true
    git -C "$base_worktree" worktree remove "$wt_b" --force 2>/dev/null || true
    git -C "$base_worktree" branch -D "$branch_a" 2>/dev/null || true
    git -C "$base_worktree" branch -D "$branch_b" 2>/dev/null || true

    git -C "$base_worktree" worktree add "$wt_a" -b "$branch_a" HEAD 2>/dev/null
    git -C "$base_worktree" worktree add "$wt_b" -b "$branch_b" HEAD 2>/dev/null

    echo "$wt_a $wt_b"
}

# --- Run agents in parallel ---
run_agents_parallel() {
    local wt_a="$1" wt_b="$2" prompt_a="$3" prompt_b="$4"
    local log_a="$MAB_WORKTREE/logs/mab-batch-${MAB_BATCH}-agent-a.log"
    local log_b="$MAB_WORKTREE/logs/mab-batch-${MAB_BATCH}-agent-b.log"

    mkdir -p "$MAB_WORKTREE/logs"

    echo "  Running Agent A (superpowers) in $wt_a..."
    (cd "$wt_a" && CLAUDECODE='' claude -p "$prompt_a" \
        --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
        --permission-mode bypassPermissions \
        > "$log_a" 2>&1) &
    local pid_a=$!

    echo "  Running Agent B (ralph) in $wt_b..."
    (cd "$wt_b" && CLAUDECODE='' claude -p "$prompt_b" \
        --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
        --permission-mode bypassPermissions \
        > "$log_b" 2>&1) &
    local pid_b=$!

    # Wait for both
    local exit_a=0 exit_b=0
    wait $pid_a || exit_a=$?
    wait $pid_b || exit_b=$?

    echo "  Agent A exited: $exit_a | Agent B exited: $exit_b"
    echo "$exit_a $exit_b"
}

# --- Run quality gate on an agent worktree ---
run_gate_on_agent() {
    local agent_wt="$1" agent_name="$2"
    local gate_exit=0
    (cd "$agent_wt" && eval "$MAB_QUALITY_GATE") > "$MAB_WORKTREE/logs/mab-gate-${agent_name}.log" 2>&1 || gate_exit=$?
    echo "  Gate $agent_name: exit=$gate_exit"
    return $gate_exit
}

# --- Invoke judge ---
invoke_judge() {
    local wt_a="$1" wt_b="$2" gate_a_log="$3" gate_b_log="$4"
    local judge_template
    judge_template=$(cat "$SCRIPT_DIR/prompts/judge-agent.md")

    local diff_a diff_b gate_a_text gate_b_text
    diff_a=$(cd "$wt_a" && git diff HEAD 2>/dev/null | head -500 || echo "(no diff)")
    diff_b=$(cd "$wt_b" && git diff HEAD 2>/dev/null | head -500 || echo "(no diff)")
    gate_a_text=$(cat "$gate_a_log" 2>/dev/null | tail -50 || echo "(no gate output)")
    gate_b_text=$(cat "$gate_b_log" 2>/dev/null | tail -50 || echo "(no gate output)")

    local design_doc=""
    if [[ -n "$MAB_PLAN" && -f "$MAB_PLAN" ]]; then
        design_doc=$(head -100 "$MAB_PLAN")
    fi

    local judge_prompt="$judge_template"
    judge_prompt="${judge_prompt//\{WORK_UNIT_DESCRIPTION\}/$MAB_WORK_UNIT}"
    judge_prompt="${judge_prompt//\{DIFF_A\}/$diff_a}"
    judge_prompt="${judge_prompt//\{DIFF_B\}/$diff_b}"
    judge_prompt="${judge_prompt//\{GATE_A\}/$gate_a_text}"
    judge_prompt="${judge_prompt//\{GATE_B\}/$gate_b_text}"
    judge_prompt="${judge_prompt//\{DESIGN_DOC\}/$design_doc}"

    local judge_output
    judge_output=$(CLAUDECODE='' claude -p "$judge_prompt" \
        --allowedTools "" \
        --permission-mode bypassPermissions \
        2>"$MAB_WORKTREE/logs/mab-judge-stderr.log") || true

    echo "$judge_output" > "$MAB_WORKTREE/logs/mab-judge-output.log"

    # Parse winner from judge output
    local winner
    winner=$(echo "$judge_output" | grep -oE 'WINNER:\s*(agent-[ab]|tie)' | sed 's/WINNER:\s*//' | head -1 || echo "tie")
    winner="${winner:-tie}"

    # Parse lesson
    local lesson
    lesson=$(echo "$judge_output" | grep -oE 'LESSON:\s*.*' | sed 's/LESSON:\s*//' | head -1 || echo "")

    echo "$winner|$lesson"
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

# --- Merge winner branch ---
merge_winner() {
    local winner="$1" wt_a="$2" wt_b="$3"

    local winner_wt
    if [[ "$winner" == "agent-a" ]]; then
        winner_wt="$wt_a"
    else
        winner_wt="$wt_b"
    fi

    # Commit winner's changes in their worktree
    (cd "$winner_wt" && git add -A && git commit -m "mab: $winner batch $MAB_BATCH — $MAB_WORK_UNIT" --allow-empty 2>/dev/null) || true

    # Cherry-pick into base worktree
    local winner_commit
    winner_commit=$(cd "$winner_wt" && git rev-parse HEAD)

    (cd "$MAB_WORKTREE" && git cherry-pick "$winner_commit" --no-edit 2>/dev/null) || {
        echo "WARNING: Cherry-pick failed, attempting manual merge" >&2
        (cd "$MAB_WORKTREE" && git cherry-pick --abort 2>/dev/null || true)
        # Fallback: copy files from winner worktree
        (cd "$winner_wt" && git diff HEAD~1 --name-only 2>/dev/null | while IFS= read -r f; do
            mkdir -p "$MAB_WORKTREE/$(dirname "$f")"
            cp "$winner_wt/$f" "$MAB_WORKTREE/$f" 2>/dev/null || true
        done)
        (cd "$MAB_WORKTREE" && git add -A && git commit -m "mab: $winner batch $MAB_BATCH (manual merge)" --allow-empty 2>/dev/null) || true
    }
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
                [.[] | if .pattern == $p then .occurrences += 1 | .last_seen = now | tostring else . end]
            else
                . + [{"pattern": $p, "context": $ctx, "winner": $w, "occurrences": 1, "last_seen": (now | tostring), "promoted": false}]
            end
        ' "$lessons_file" > "$tmp" && mv "$tmp" "$lessons_file"
    fi

    # Log the run
    local run_log="$MAB_WORKTREE/logs/mab-runs.log"
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] batch=$MAB_BATCH type=$batch_type winner=$winner lesson=\"$lesson\"" >> "$run_log"
}

# --- Cleanup worktrees ---
cleanup_mab_worktrees() {
    local base_worktree="$1" batch="$2"
    local branch_a="mab-agent-a-batch-${batch}"
    local branch_b="mab-agent-b-batch-${batch}"
    local wt_a="$base_worktree/.mab-worktrees/agent-a"
    local wt_b="$base_worktree/.mab-worktrees/agent-b"

    git -C "$base_worktree" worktree remove "$wt_a" --force 2>/dev/null || true
    git -C "$base_worktree" worktree remove "$wt_b" --force 2>/dev/null || true
    git -C "$base_worktree" branch -D "$branch_a" 2>/dev/null || true
    git -C "$base_worktree" branch -D "$branch_b" 2>/dev/null || true
    rm -rf "$base_worktree/.mab-worktrees" 2>/dev/null || true
}

# --- Main orchestration ---
run_mab() {
    local perf_file="$MAB_WORKTREE/logs/strategy-perf.json"
    [[ ! -f "$perf_file" ]] && init_strategy_perf "$perf_file"

    local lessons_file="$MAB_WORKTREE/logs/mab-lessons.json"
    [[ ! -f "$lessons_file" ]] && echo "[]" > "$lessons_file"

    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  MAB Run — Batch $MAB_BATCH"
    echo "║  Work: $MAB_WORK_UNIT"
    echo "╚══════════════════════════════════════════════════════╝"

    if [[ "$MAB_DRY_RUN" == true ]]; then
        echo ""
        echo "=== DRY RUN ==="
        echo "  Plan: $MAB_PLAN"
        echo "  Batch: $MAB_BATCH"
        echo "  Work unit: $MAB_WORK_UNIT"
        echo "  Worktree: $MAB_WORKTREE"
        echo "  Quality gate: $MAB_QUALITY_GATE"
        echo ""
        echo "  Would create worktrees:"
        echo "    agent-a: $MAB_WORKTREE/.mab-worktrees/agent-a"
        echo "    agent-b: $MAB_WORKTREE/.mab-worktrees/agent-b"
        echo ""
        echo "  Would run agents in parallel, invoke judge, merge winner."
        echo "=== END DRY RUN ==="
        return 0
    fi

    # Load MAB lessons for injection
    local mab_lessons_text=""
    if [[ -f "$lessons_file" ]]; then
        mab_lessons_text=$(jq -r '
            sort_by(-.occurrences // 0) | .[0:5] | .[] |
            "- \(.pattern) (\(.context // "general")): winner=\(.winner // "unknown")"
        ' "$lessons_file" 2>/dev/null || echo "No lessons yet.")
    fi
    [[ -z "$mab_lessons_text" ]] && mab_lessons_text="No lessons yet."

    # Resolve paths
    local prd_path="${MAB_PRD:-tasks/prd.json}"
    local arch_map_path="docs/ARCHITECTURE-MAP.json"

    # Assemble prompts
    local prompt_a_template prompt_b_template
    prompt_a_template=$(cat "$SCRIPT_DIR/prompts/agent-a-superpowers.md")
    prompt_b_template=$(cat "$SCRIPT_DIR/prompts/agent-b-ralph.md")

    local prompt_a prompt_b
    prompt_a=$(assemble_agent_prompt "$prompt_a_template" "$MAB_WORK_UNIT" "$prd_path" "$arch_map_path" "$mab_lessons_text" "$MAB_QUALITY_GATE")
    prompt_b=$(assemble_agent_prompt "$prompt_b_template" "$MAB_WORK_UNIT" "$prd_path" "$arch_map_path" "$mab_lessons_text" "$MAB_QUALITY_GATE")

    # Create worktrees
    echo ""
    echo "--- Creating worktrees ---"
    local worktrees
    worktrees=$(create_mab_worktrees "$MAB_WORKTREE" "$MAB_BATCH")
    local wt_a wt_b
    wt_a=$(echo "$worktrees" | awk '{print $1}')
    wt_b=$(echo "$worktrees" | awk '{print $2}')
    echo "  Agent A: $wt_a"
    echo "  Agent B: $wt_b"

    # Run agents in parallel
    echo ""
    echo "--- Running agents ---"
    run_agents_parallel "$wt_a" "$wt_b" "$prompt_a" "$prompt_b" || true

    # Run quality gates
    echo ""
    echo "--- Quality gates ---"
    local gate_a=0 gate_b=0
    run_gate_on_agent "$wt_a" "agent-a" || gate_a=$?
    run_gate_on_agent "$wt_b" "agent-b" || gate_b=$?

    # Invoke judge (only if both agents ran)
    echo ""
    echo "--- Judge evaluation ---"
    local judge_result judge_winner judge_lesson
    judge_result=$(invoke_judge "$wt_a" "$wt_b" \
        "$MAB_WORKTREE/logs/mab-gate-agent-a.log" \
        "$MAB_WORKTREE/logs/mab-gate-agent-b.log")
    judge_winner=$(echo "$judge_result" | cut -d'|' -f1)
    judge_lesson=$(echo "$judge_result" | cut -d'|' -f2-)
    echo "  Judge verdict: $judge_winner"

    # Apply gate override
    local final_winner
    final_winner=$(select_winner_with_gate_override "$gate_a" "$gate_b" "$judge_winner")
    echo "  Final winner: $final_winner (gate override applied)"

    # Human calibration
    final_winner=$(prompt_human_calibration "$final_winner" "$perf_file")

    if [[ "$final_winner" == "none" || "$final_winner" == "tie" ]]; then
        echo "  No winner — both agents failed or tie with no override."
        cleanup_mab_worktrees "$MAB_WORKTREE" "$MAB_BATCH"
        return 1
    fi

    # Merge winner
    echo ""
    echo "--- Merging winner ($final_winner) ---"
    merge_winner "$final_winner" "$wt_a" "$wt_b"

    # Classify batch type for data recording
    local batch_type="unknown"
    if type classify_batch_type &>/dev/null && [[ -n "$MAB_PLAN" ]]; then
        batch_type=$(classify_batch_type "$MAB_PLAN" "$MAB_BATCH" 2>/dev/null || echo "unknown")
    fi

    # Update data
    update_mab_data "$final_winner" "$judge_lesson" "$batch_type"

    # Cleanup
    echo ""
    echo "--- Cleanup ---"
    cleanup_mab_worktrees "$MAB_WORKTREE" "$MAB_BATCH"

    echo ""
    echo "MAB batch $MAB_BATCH complete. Winner: $final_winner"
}

# --- Entry point ---
parse_mab_args "$@"

# --source-only: export functions for testing, don't execute
if [[ "$MAB_SOURCE_ONLY" == true ]]; then
    return 0 2>/dev/null || exit 0
fi

validate_mab_args

if [[ "$MAB_INIT_DATA" == true ]]; then
    mkdir -p "$MAB_WORKTREE/logs"
    init_strategy_perf "$MAB_WORKTREE/logs/strategy-perf.json"
    echo "[]" > "$MAB_WORKTREE/logs/mab-lessons.json"
    echo "Initialized MAB data files in $MAB_WORKTREE/logs/"
    exit 0
fi

run_mab
