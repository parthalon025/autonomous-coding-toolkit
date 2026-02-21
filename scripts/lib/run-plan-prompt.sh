#!/usr/bin/env bash
# run-plan-prompt.sh — Build prompts for headless claude -p batch execution
#
# Requires run-plan-parser.sh to be sourced first (provides get_batch_title, get_batch_text)
#
# Functions:
#   build_batch_prompt <plan_file> <batch_num> <worktree> <python> <quality_gate_cmd> <prev_test_count>
#     -> self-contained prompt string for claude -p

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

    cat <<PROMPT
You are implementing Batch ${batch_num}: ${title} from ${plan_file}.

Working directory: ${worktree}
Python: ${python}
Branch: ${branch}

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

Requirements:
- TDD: write test -> verify fail -> implement -> verify pass -> commit each task
- After all tasks: run quality gate (${quality_gate_cmd})
- Update progress.txt with batch summary and commit
- All ${prev_test_count}+ tests must pass
PROMPT
}
