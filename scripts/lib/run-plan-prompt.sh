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

build_batch_prompt() {
    local plan_file="$1"
    local batch_num="$2"
    local worktree="$3"
    local python="$4"
    local quality_gate_cmd="$5"
    local prev_test_count="$6"

    local title branch batch_text recent_commits progress_tail prev_gate

    title=$(get_batch_title "$plan_file" "$batch_num")
    branch=$(git -C "$worktree" branch --show-current 2>/dev/null || echo "unknown")
    batch_text=$(get_batch_text "$plan_file" "$batch_num")

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

    # Build prompt: task at top, requirements at bottom (Lost in the Middle mitigation)
    # All sections wrapped in XML tags for structured parsing
    local prompt=""
    prompt+="You are implementing Batch ${batch_num}: ${title} from ${plan_file}."$'\n'
    prompt+=""$'\n'
    prompt+="Working directory: ${worktree}"$'\n'
    prompt+="Python: ${python}"$'\n'
    prompt+="Branch: ${branch}"$'\n'
    prompt+=""$'\n'

    # Task text at the top (highest priority — never lost in the middle)
    prompt+="<batch_tasks>"$'\n'
    prompt+="${batch_text}"$'\n'
    prompt+="</batch_tasks>"$'\n'

    # Prior context in the middle
    prompt+=""$'\n'
    prompt+="<prior_context>"$'\n'
    prompt+="Recent commits:"$'\n'
    prompt+="${recent_commits}"$'\n'
    if [[ -n "$progress_tail" ]]; then
        prompt+=""$'\n'
        prompt+="<prior_progress>"$'\n'
        prompt+="${progress_tail}"$'\n'
        prompt+="</prior_progress>"$'\n'
    fi
    if [[ -n "$prev_gate" && "$prev_gate" != "null" ]]; then
        prompt+=""$'\n'
        prompt+="Previous quality gate: ${prev_gate}"$'\n'
    fi
    prompt+="</prior_context>"$'\n'

    # Referenced files (if any)
    if [[ -n "$context_refs_content" ]]; then
        prompt+=""$'\n'
        prompt+="<referenced_files>"$'\n'
        prompt+="${context_refs_content}"$'\n'
        prompt+="</referenced_files>"$'\n'
    fi

    # Research warnings (if any)
    if [[ -n "$research_warnings" ]]; then
        prompt+=""$'\n'
        prompt+="<research_warnings>"$'\n'
        prompt+="${research_warnings}"$'\n'
        prompt+="</research_warnings>"$'\n'
    fi

    # Requirements at the bottom (anchored — recency bias helps)
    prompt+=""$'\n'
    prompt+="<requirements>"$'\n'
    prompt+="- TDD: write test -> verify fail -> implement -> verify pass -> commit each task"$'\n'
    prompt+="- After all tasks: run quality gate (${quality_gate_cmd})"$'\n'
    prompt+="- Update progress.txt with batch summary and commit"$'\n'
    prompt+="- All ${prev_test_count}+ tests must pass"$'\n'
    prompt+="</requirements>"$'\n'

    printf '%s' "$prompt"
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
