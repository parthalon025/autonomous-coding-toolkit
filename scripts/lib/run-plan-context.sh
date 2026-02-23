#!/usr/bin/env bash
# run-plan-context.sh — Per-batch context assembler for run-plan
#
# Assembles relevant context for a batch agent within a token budget.
# Reads: state file, progress.txt, git log, context_refs, failure patterns.
# Outputs: markdown section for CLAUDE.md injection.
#
# Functions:
#   generate_batch_context <plan_file> <batch_num> <worktree> -> markdown string
#   record_failure_pattern <worktree> <batch_title> <failure_type> <winning_fix>

TOKEN_BUDGET_CHARS=10000  # ~2500 tokens

generate_batch_context() {
    local plan_file="$1" batch_num="$2" worktree="$3"
    local context=""
    local chars_used=0

    context+="## Run-Plan: Batch $batch_num"$'\n\n'

    # 1. Directives from state (highest priority)
    local state_file="$worktree/.run-plan-state.json"
    if [[ -f "$state_file" ]]; then
        local prev_test_count
        prev_test_count=$(jq -r '[.batches[].test_count // 0] | max' "$state_file" 2>/dev/null || echo "0")
        if [[ "$prev_test_count" -gt 0 ]]; then
            context+="**Directive:** tests must stay above $prev_test_count (current high water mark)"$'\n\n'
        fi

        # Prior batch summary (most recent 2 batches only)
        local start_batch=$(( batch_num - 2 ))
        [[ $start_batch -lt 1 ]] && start_batch=1
        for ((b = start_batch; b < batch_num; b++)); do
            local passed duration tests
            passed=$(jq -r ".batches[\"$b\"].passed // false" "$state_file" 2>/dev/null)
            tests=$(jq -r ".batches[\"$b\"].test_count // 0" "$state_file" 2>/dev/null)
            duration=$(jq -r ".batches[\"$b\"].duration // 0" "$state_file" 2>/dev/null)
            if [[ "$passed" == "true" ]]; then
                context+="Batch $b: PASSED ($tests tests, ${duration}s)"$'\n'
            fi
        done
        context+=$'\n'
    fi

    # 2. Failure patterns (cross-run learning)
    local patterns_file="$worktree/logs/failure-patterns.json"
    if [[ -f "$patterns_file" ]]; then
        local batch_title
        batch_title=$(get_batch_title "$plan_file" "$batch_num" 2>/dev/null || echo "")
        local title_lower
        title_lower=$(echo "$batch_title" | tr '[:upper:]' '[:lower:]')

        # Match failure patterns by batch title keywords
        local matches
        matches=$(jq -r --arg title "$title_lower" \
            '.[] | select(.batch_title_pattern as $p | $title | contains($p)) | "WARNING: Previously failed with \(.failure_type) (\(.frequency)x). Fix that worked: \(.winning_fix)"' \
            "$patterns_file" 2>/dev/null || true)
        if [[ -n "$matches" ]]; then
            context+="### Known Failure Patterns"$'\n'
            context+="$matches"$'\n\n'
        fi
    fi

    chars_used=${#context}

    # 3. Context refs file contents (if budget allows)
    local refs
    refs=$(get_batch_context_refs "$plan_file" "$batch_num" 2>/dev/null || true)
    if [[ -n "$refs" ]]; then
        local refs_section="### Referenced Files"$'\n'
        while IFS= read -r ref_file; do
            ref_file=$(echo "$ref_file" | xargs)  # trim whitespace
            [[ -z "$ref_file" ]] && continue
            local full_path="$worktree/$ref_file"
            if [[ -f "$full_path" ]]; then
                local file_content
                file_content=$(head -50 "$full_path" 2>/dev/null || true)
                local addition
                addition=$'\n'"**$ref_file:**"$'\n'"$file_content"$'\n'
                if [[ $(( chars_used + ${#refs_section} + ${#addition} )) -lt $TOKEN_BUDGET_CHARS ]]; then
                    refs_section+="$addition"
                fi
            fi
        done <<< "$refs"
        context+="$refs_section"$'\n'
    fi

    chars_used=${#context}

    # 4. Git log (if budget allows)
    if [[ $(( chars_used + 500 )) -lt $TOKEN_BUDGET_CHARS ]]; then
        local git_log
        git_log=$(cd "$worktree" && git log --oneline -5 2>/dev/null || true)
        if [[ -n "$git_log" ]]; then
            context+="### Recent Commits"$'\n'
            context+="$git_log"$'\n\n'
        fi
    fi

    chars_used=${#context}

    # 5. Progress.txt (if budget allows — structured read for last 2 batches, fallback to tail)
    if [[ $(( chars_used + 500 )) -lt $TOKEN_BUDGET_CHARS ]]; then
        local progress_file="$worktree/progress.txt"
        if [[ -f "$progress_file" ]]; then
            local progress=""
            if type read_batch_progress &>/dev/null; then
                # Structured read: last 2 batches
                local pb_start=$(( batch_num - 2 ))
                [[ $pb_start -lt 1 ]] && pb_start=1
                for ((pb = pb_start; pb < batch_num; pb++)); do
                    local pb_content
                    pb_content=$(read_batch_progress "$worktree" "$pb")
                    if [[ -n "$pb_content" ]]; then
                        progress+="$pb_content"$'\n'
                    fi
                done
            fi
            # Fallback: if structured read returned nothing, use tail
            if [[ -z "$progress" ]]; then
                progress=$(tail -10 "$progress_file" 2>/dev/null || true)
            fi
            if [[ -n "$progress" ]]; then
                context+="### Progress Notes"$'\n'
                context+="$progress"$'\n\n'
            fi
        fi
    fi

    echo "$context"
}

record_failure_pattern() {
    local worktree="$1" batch_title="$2" failure_type="$3" winning_fix="$4"
    local patterns_file="$worktree/logs/failure-patterns.json"
    local title_lower
    title_lower=$(echo "$batch_title" | tr '[:upper:]' '[:lower:]')

    mkdir -p "$(dirname "$patterns_file")"

    if [[ ! -f "$patterns_file" ]]; then
        echo "[]" > "$patterns_file"
    fi

    # Check if pattern already exists
    local existing
    existing=$(jq -r --arg t "$title_lower" --arg f "$failure_type" \
        '[.[] | select(.batch_title_pattern == $t and .failure_type == $f)] | length' \
        "$patterns_file" 2>/dev/null || echo "0")

    if [[ "$existing" -gt 0 ]]; then
        # Increment frequency
        local tmp
        tmp=$(mktemp)
        jq --arg t "$title_lower" --arg f "$failure_type" \
            '[.[] | if .batch_title_pattern == $t and .failure_type == $f then .frequency += 1 else . end]' \
            "$patterns_file" > "$tmp" && mv "$tmp" "$patterns_file"
    else
        # Add new pattern
        local tmp
        tmp=$(mktemp)
        jq --arg t "$title_lower" --arg f "$failure_type" --arg w "$winning_fix" \
            '. += [{"batch_title_pattern": $t, "failure_type": $f, "frequency": 1, "winning_fix": $w}]' \
            "$patterns_file" > "$tmp" && mv "$tmp" "$patterns_file"
    fi
}
