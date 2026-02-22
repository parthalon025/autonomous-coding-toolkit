#!/usr/bin/env bash
# run-plan-scoring.sh — Candidate scoring for parallel patch sampling
#
# Functions:
#   score_candidate <gate_passed> <test_count> <diff_lines> <lint_warnings> <lesson_violations> <ast_violations>
#   select_winner <scores_string>  -> index of highest score (0-based), -1 if all zero

score_candidate() {
    local gate_passed="${1:-0}"
    local test_count="${2:-0}"
    local diff_lines="${3:-1}"
    local lint_warnings="${4:-0}"
    local lesson_violations="${5:-0}"
    local ast_violations="${6:-0}"

    if [[ "$gate_passed" -ne 1 ]]; then
        echo 0
        return
    fi

    # Avoid division by zero
    [[ "$diff_lines" -lt 1 ]] && diff_lines=1

    local score=$(( (test_count * 10) + (10000 / (diff_lines + 1)) + (1000 / (lint_warnings + 1)) - (lesson_violations * 200) - (ast_violations * 100) ))

    # Floor at 1 (gate passed = always positive)
    [[ "$score" -lt 1 ]] && score=1
    echo "$score"
}

select_winner() {
    local scores_str="$1"
    local max_score=0
    local max_idx=-1
    local idx=0

    for score in $scores_str; do
        if [[ "$score" -gt "$max_score" ]]; then
            max_score="$score"
            max_idx=$idx
        fi
        idx=$((idx + 1))
    done

    echo "$max_idx"
}

# Classify a batch by its dominant action type.
# Returns: new-file | refactoring | integration | test-only | unknown
classify_batch_type() {
    local plan_file="$1" batch_num="$2"
    local batch_text title

    # Source parser if not already loaded
    type get_batch_text &>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/run-plan-parser.sh"

    batch_text=$(get_batch_text "$plan_file" "$batch_num" 2>/dev/null || true)
    title=$(get_batch_title "$plan_file" "$batch_num" 2>/dev/null || true)

    # Check title for integration keywords
    if echo "$title" | grep -qiE 'integrat|wir|connect|glue'; then
        echo "integration"
        return
    fi

    local creates modifies runs
    creates=$(echo "$batch_text" | grep -cE '^\s*-\s*Create:' || true)
    creates=${creates:-0}
    modifies=$(echo "$batch_text" | grep -cE '^\s*-\s*Modify:' || true)
    modifies=${modifies:-0}
    runs=$(echo "$batch_text" | grep -cE '^Run:' || true)
    runs=${runs:-0}

    # Test-only: only Run commands, no Create/Modify
    if [[ "$creates" -eq 0 && "$modifies" -eq 0 && "$runs" -gt 0 ]]; then
        echo "test-only"
        return
    fi

    # New file creation dominant
    if [[ "$creates" -gt "$modifies" ]]; then
        echo "new-file"
        return
    fi

    # Refactoring: modifications dominant
    if [[ "$modifies" -gt 0 ]]; then
        echo "refactoring"
        return
    fi

    echo "unknown"
}

# Get prompt variant suffixes for a batch type.
# Uses learned outcomes if available, otherwise defaults.
# Args: <batch_type> <outcomes_file> <count>
# Output: N lines, each a prompt suffix string
get_prompt_variants() {
    local batch_type="$1"
    local outcomes_file="$2"
    local count="${3:-3}"

    # Default variants per batch type
    local -A type_variants
    type_variants[new-file]="check all imports before running tests|write tests first then implement"
    type_variants[refactoring]="minimal change only|run tests after each edit"
    type_variants[integration]="trace end-to-end before declaring done|check every import and export"
    type_variants[test-only]="use real objects not mocks|focus on edge cases only"
    type_variants[unknown]="try a different approach|make the minimum possible change"

    local defaults="${type_variants[$batch_type]:-${type_variants[unknown]}}"

    # Slot 1: always vanilla
    echo "vanilla"

    # Check for learned winners
    local learned_variant=""
    if [[ -f "$outcomes_file" ]]; then
        learned_variant=$(jq -r --arg bt "$batch_type" \
            '[.[] | select(.batch_type == $bt and .won == true)] | sort_by(.score) | reverse | .[0].prompt_variant // empty' \
            "$outcomes_file" 2>/dev/null || true)
    fi

    # Slot 2: learned winner or first default
    local variant2="${learned_variant:-$(echo "$defaults" | cut -d'|' -f1)}"
    if [[ "$count" -ge 2 ]]; then
        echo "$variant2"
    fi

    # Slot 3+: remaining defaults (exploration)
    local slot=3
    IFS='|' read -ra parts <<< "$defaults"
    for part in "${parts[@]}"; do
        [[ "$slot" -gt "$count" ]] && break
        [[ "$part" == "$variant2" ]] && continue
        echo "$part"
        slot=$((slot + 1))
    done

    # Fill remaining slots with generic variants
    while [[ "$slot" -le "$count" ]]; do
        echo "try a fundamentally different approach"
        slot=$((slot + 1))
    done
}
