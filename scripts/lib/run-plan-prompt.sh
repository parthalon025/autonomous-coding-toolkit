#!/usr/bin/env bash
# run-plan-prompt.sh — Build prompts for headless claude -p batch execution
#
# Requires run-plan-parser.sh to be sourced first (provides get_batch_title, get_batch_text)
#
# Functions:
#   build_batch_prompt <plan_file> <batch_num> <worktree> <python> <quality_gate_cmd> <prev_test_count>
#     -> self-contained prompt string for claude -p
#   generate_agents_md <plan_file> <worktree> <mode>
#     -> writes AGENTS.md to worktree for agent team awareness

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

    # Cross-batch context: recent commits
    recent_commits=$(git -C "$worktree" log --oneline -5 2>/dev/null || echo "(no commits)")

    # Cross-batch context: progress.txt tail
    progress_tail=""
    if [[ -f "$worktree/progress.txt" ]]; then
        progress_tail=$(tail -20 "$worktree/progress.txt" 2>/dev/null || true)
    fi

    # Cross-batch context: previous quality gate result
    prev_gate=""
    if [[ -f "$worktree/.run-plan-state.json" ]]; then
        prev_gate=$(jq -r '.last_quality_gate // empty' "$worktree/.run-plan-state.json" 2>/dev/null || true)
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

    # Cross-batch context: research warnings (from research JSON if present)
    local research_warnings=""
    # shellcheck disable=SC2086
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

# Build complete batch prompt by composing stable prefix and variable suffix.
# Args: <plan_file> <batch_num> <worktree> <python> <quality_gate_cmd> <prev_test_count>
# Backward compatible — same signature and output contract as before.
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
