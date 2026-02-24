#!/usr/bin/env bash
# run-plan-prompt.sh — Build prompts for headless claude -p batch execution
#
# Requires run-plan-parser.sh to be sourced first (provides get_batch_title, get_batch_text)
#
# Functions:
#   build_stable_prefix <plan_file> <worktree> <python> <quality_gate_cmd>
#     -> stable portion of the prompt (plan identity, worktree, python, branch, TDD rules)
#     -> safe to cache across batches; does NOT include prev_test_count or other per-batch data
#   build_variable_suffix <plan_file> <batch_num> <worktree> <prev_test_count>
#     -> per-batch portion of the prompt (tasks, commits, progress, gate results, test count)
#   build_batch_prompt <plan_file> <batch_num> <worktree> <python> <quality_gate_cmd> <prev_test_count>
#     -> full self-contained prompt (stable prefix + variable suffix) for claude -p
#   generate_agents_md <plan_file> <worktree> <mode>
#     -> writes AGENTS.md to worktree for agent team awareness

# build_stable_prefix — assemble the stable (batch-invariant) portion of a batch prompt.
#
# Stability contract: output depends only on plan_file path, worktree path, python path,
# quality_gate_cmd, and the git branch name. None of these change between batches in a
# normal run, so the result may be cached and reused across batches.
#
# NOTE: prev_test_count intentionally excluded — it changes each batch. It belongs in
# build_variable_suffix (see issue #48).
#
# Args: <plan_file> <worktree> <python> <quality_gate_cmd>
build_stable_prefix() {
    local plan_file="$1"
    local worktree="$2"
    local python="$3"
    local quality_gate_cmd="$4"

    local branch

    # #46: Check worktree exists before calling git. Log a warning if git fails so
    # the caller knows the branch name is unreliable rather than silently caching "unknown".
    if [[ ! -d "$worktree" ]]; then
        echo "WARNING: worktree directory does not exist: $worktree" >&2
        branch="unknown"
    else
        branch=$(git -C "$worktree" branch --show-current 2>/dev/null) || {
            echo "WARNING: git branch failed for worktree: $worktree — using 'unknown'" >&2
            branch="unknown"
        }
        # git can succeed but print nothing (detached HEAD)
        [[ -z "$branch" ]] && branch="unknown"
    fi

    cat <<PREFIX
Working directory: ${worktree}
Python: ${python}
Branch: ${branch}

Requirements:
- TDD: write test -> verify fail -> implement -> verify pass -> commit each task
- After all tasks: run quality gate (${quality_gate_cmd})
- Update progress.txt with batch summary and commit
PREFIX
}

# build_variable_suffix — assemble the per-batch (variable) portion of a batch prompt.
#
# Contains everything that can differ between batches: batch number, title, task text,
# recent commits, progress tail, previous quality gate result, context refs, and the
# current prev_test_count (which increases after each batch).
#
# Args: <plan_file> <batch_num> <worktree> <prev_test_count>
build_variable_suffix() {
    local plan_file="$1"
    local batch_num="$2"
    local worktree="$3"
    local prev_test_count="$4"

    local title batch_text recent_commits progress_tail prev_gate

    title=$(get_batch_title "$plan_file" "$batch_num")
    batch_text=$(get_batch_text "$plan_file" "$batch_num")

    # Cross-batch context: recent commits
    recent_commits=$(git -C "$worktree" log --oneline -5 2>/dev/null || echo "(no commits)")

    # Cross-batch context: progress.txt tail
    # #50: File existence is already checked before calling tail.
    # Remove 2>/dev/null || true — permission errors on a confirmed-existing file should
    # propagate so the caller sees the real error rather than silently getting no progress.
    progress_tail=""
    if [[ -f "$worktree/progress.txt" ]]; then
        progress_tail=$(tail -20 "$worktree/progress.txt")
    fi

    # Cross-batch context: previous quality gate result
    # #47: Distinguish "no state file / no key" (expected) from "corrupted JSON" (error).
    # jq returns exit 5 on parse failure. Check exit code and warn on corruption so the
    # caller knows prev_gate is empty due to an error, not just an absent first batch.
    prev_gate=""
    if [[ -f "$worktree/.run-plan-state.json" ]]; then
        local jq_exit=0
        prev_gate=$(jq -r '.last_quality_gate // empty' "$worktree/.run-plan-state.json" 2>/dev/null) || jq_exit=$?
        if [[ $jq_exit -ne 0 ]]; then
            echo "WARNING: .run-plan-state.json is corrupted (jq exit $jq_exit) — proceeding without previous gate context" >&2
            prev_gate=""
        fi
    fi

    # Cross-batch context: referenced files from context_refs
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

    cat <<SUFFIX
You are implementing Batch ${batch_num}: ${title} from ${plan_file}.

Tasks in this batch:
${batch_text}

Recent commits:
${recent_commits}
$(if [[ -n "$progress_tail" ]]; then
echo "
Previous progress:
${progress_tail}"
fi)
$(if [[ -n "$prev_gate" && "$prev_gate" != "null" ]]; then
echo "
Previous quality gate: ${prev_gate}"
fi)
$(if [[ -n "$context_refs_content" ]]; then
echo "
Referenced files from prior batches:
${context_refs_content}"
fi)
- All ${prev_test_count}+ tests must pass
SUFFIX
}

# build_batch_prompt — full prompt for a single batch (stable prefix + variable suffix).
#
# Callers that run multiple batches should prefer calling build_stable_prefix once and
# caching the result, then calling build_variable_suffix per batch — see run-plan-headless.sh.
# This function is a convenience wrapper for single-batch callers and tests.
#
# Args: <plan_file> <batch_num> <worktree> <python> <quality_gate_cmd> <prev_test_count>
build_batch_prompt() {
    local plan_file="$1"
    local batch_num="$2"
    local worktree="$3"
    local python="$4"
    local quality_gate_cmd="$5"
    local prev_test_count="$6"

    local stable_prefix variable_suffix
    stable_prefix=$(build_stable_prefix "$plan_file" "$worktree" "$python" "$quality_gate_cmd")
    variable_suffix=$(build_variable_suffix "$plan_file" "$batch_num" "$worktree" "$prev_test_count")

    printf '%s\n\n%s\n' "$variable_suffix" "$stable_prefix"
}

# Generate AGENTS.md in the worktree for agent team awareness.
# Args: <plan_file> <worktree> <mode>
generate_agents_md() {
    local plan_file="$1" worktree="$2" mode="${3:-headless}"

    # Source parser if needed
    type count_batches &>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/run-plan-parser.sh"

    local total_batches
    total_batches=$(count_batches "$plan_file")

    local batch_info=""
    for ((b = 1; b <= total_batches; b++)); do
        local title
        title=$(get_batch_title "$plan_file" "$b")
        [[ -z "$title" ]] && continue
        batch_info+="| $b | $title |"$'\n'
    done

    cat > "$worktree/AGENTS.md" << EOF
# Agent Configuration

**Plan:** $(basename "$plan_file")
**Mode:** $mode
**Total:** $total_batches batches

## Tools Allowed

Bash, Read, Write, Edit, Grep, Glob

## Permission Mode

bypassPermissions

## Batches

| # | Title |
|---|-------|
${batch_info}
## Guidelines

- Run quality gate after each batch
- Commit after passing gate
- Append discoveries to progress.txt
- Do not modify files outside your batch scope
EOF
}
