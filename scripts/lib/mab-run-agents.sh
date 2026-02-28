#!/usr/bin/env bash
# mab-run-agents.sh — MAB worktree and agent execution helpers
#
# Functions:
#   create_mab_worktrees <base_worktree> <batch>    -> "<wt_a> <wt_b>"
#   run_agents_parallel <wt_a> <wt_b> <prompt_a> <prompt_b>
#   run_gate_on_agent <agent_wt> <agent_name>
#   invoke_judge <wt_a> <wt_b> <gate_a_log> <gate_b_log>
#   merge_winner <winner> <wt_a> <wt_b>
#   cleanup_mab_worktrees <base_worktree> <batch>
#
# Requires: MAB_WORKTREE, MAB_BATCH, MAB_WORK_UNIT, MAB_PLAN, MAB_QUALITY_GATE
#           SCRIPT_DIR to be set by the sourcing script.

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

    # Kill children on interrupt, clean up worktrees
    trap 'kill "$pid_a" "$pid_b" 2>/dev/null; wait "$pid_a" "$pid_b" 2>/dev/null; echo "MAB agents interrupted" >&2' INT TERM

    # Wait for both
    local exit_a=0 exit_b=0
    wait $pid_a || exit_a=$?
    wait $pid_b || exit_b=$?

    # Clear the interrupt trap
    trap - INT TERM

    echo "  Agent A exited: $exit_a | Agent B exited: $exit_b"
    echo "$exit_a $exit_b"
}

# --- Run quality gate on an agent worktree ---
run_gate_on_agent() {
    local agent_wt="$1" agent_name="$2"
    local gate_exit=0
    (cd "$agent_wt" && bash -c "$MAB_QUALITY_GATE") > "$MAB_WORKTREE/logs/mab-gate-${agent_name}.log" 2>&1 || gate_exit=$?
    echo "  Gate $agent_name: exit=$gate_exit"
    return $gate_exit
}

# --- Invoke judge ---
invoke_judge() {
    local wt_a="$1" wt_b="$2" gate_a_log="$3" gate_b_log="$4"
    local judge_template
    judge_template=$(cat "$SCRIPT_DIR/prompts/judge-agent.md")

    local diff_a diff_b gate_a_text gate_b_text
    diff_a=$(cd "$wt_a" && git diff HEAD 2>/dev/null | head -500) || diff_a="(no diff)"
    diff_b=$(cd "$wt_b" && git diff HEAD 2>/dev/null | head -500) || diff_b="(no diff)"
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
    local judge_exit=0
    judge_output=$(CLAUDECODE='' claude -p "$judge_prompt" \
        --allowedTools "" \
        --permission-mode bypassPermissions \
        2>"$MAB_WORKTREE/logs/mab-judge-stderr.log") || judge_exit=$?
    if [[ $judge_exit -ne 0 ]]; then
        echo "WARNING: judge failed (exit $judge_exit), defaulting to tie" >&2
    fi

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

# --- Merge winner branch ---
merge_winner() {
    local winner="$1" wt_a="$2" wt_b="$3"

    local winner_wt
    if [[ "$winner" == "agent-a" ]]; then
        winner_wt="$wt_a"
    elif [[ "$winner" == "agent-b" ]]; then
        winner_wt="$wt_b"
    else
        echo "ERROR: merge_winner called with unexpected winner='$winner'" >&2
        return 1
    fi

    # Commit winner's changes in their worktree
    (cd "$winner_wt" && git add -u && git commit -m "mab: $winner batch $MAB_BATCH — $MAB_WORK_UNIT" --allow-empty 2>/dev/null) || true

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
        (cd "$MAB_WORKTREE" && git add -u && git commit -m "mab: $winner batch $MAB_BATCH (manual merge)" --allow-empty 2>/dev/null) || true
    }
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
