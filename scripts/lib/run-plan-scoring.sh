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
