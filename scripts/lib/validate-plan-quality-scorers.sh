#!/usr/bin/env bash
# validate-plan-quality-scorers.sh — Scoring functions for validate-plan-quality.sh
#
# Each function takes a plan file path and returns a score 0-100.
#
# Functions:
#   score_task_granularity <plan_file>
#   score_spec_completeness <plan_file>
#   score_single_outcome <plan_file>
#   score_dependency_ordering <plan_file>
#   score_file_path_specificity <plan_file>
#   score_acceptance_criteria <plan_file>
#   score_batch_size <plan_file>
#   score_tdd_structure <plan_file>
#
# Requires: count_batches, get_batch_text, get_batch_task_count from run-plan-parser.sh

# --- Helpers ---
# Safe grep -c that works with pipefail (avoids the 0\n0 double-output bug).
# Reads from stdin. Distinguishes "no matches" (exit 1) from "grep error" (exit 2+).
_count_matches() {
    local pattern="$1"
    local result exit_code=0
    result=$(grep -ciE "$pattern" 2>&1) || exit_code=$?
    if [[ $exit_code -le 1 ]]; then
        # 0 = matches found, 1 = no matches (both normal)
        echo "${result:-0}"
    else
        echo "WARNING: grep failed (exit $exit_code) for pattern: $pattern" >&2
        echo "0"
    fi
}

score_task_granularity() {
    local plan_file="$1"
    local total_batches task_count total_tasks=0 batches_with_big_tasks=0
    total_batches=$(count_batches "$plan_file")
    [[ "$total_batches" -eq 0 ]] && { echo 0; return; }

    for ((b = 1; b <= total_batches; b++)); do
        local text
        text=$(get_batch_text "$plan_file" "$b")
        task_count=$(echo "$text" | _count_matches '^### Task [0-9]+')
        total_tasks=$((total_tasks + task_count))

        # Estimate: if batch text > 200 lines and has tasks, tasks are probably too big
        local line_count
        line_count=$(echo "$text" | wc -l)
        if [[ "$task_count" -gt 0 ]]; then
            local avg_lines=$(( line_count / task_count ))
            if [[ "$avg_lines" -gt 100 ]]; then
                batches_with_big_tasks=$((batches_with_big_tasks + 1))
            fi
        fi
    done

    if [[ "$total_batches" -eq 0 ]]; then
        echo 0
    elif [[ "$batches_with_big_tasks" -eq 0 ]]; then
        echo 100
    else
        local pct=$(( 100 - (batches_with_big_tasks * 100 / total_batches) ))
        echo "$pct"
    fi
}

score_spec_completeness() {
    local plan_file="$1"
    local total_batches tasks_with_verify=0 total_tasks=0
    total_batches=$(count_batches "$plan_file")
    [[ "$total_batches" -eq 0 ]] && { echo 0; return; }

    for ((b = 1; b <= total_batches; b++)); do
        local text
        text=$(get_batch_text "$plan_file" "$b")
        local task_count
        task_count=$(echo "$text" | _count_matches '^### Task [0-9]+')
        total_tasks=$((total_tasks + task_count))

        # Count tasks that mention verification patterns
        local verify_count
        verify_count=$(echo "$text" | _count_matches '(verify|assert|test|check|confirm|expect|should)')
        # Approximate: if verify mentions >= task count, all tasks are specified
        if [[ "$task_count" -gt 0 && "$verify_count" -ge "$task_count" ]]; then
            tasks_with_verify=$((tasks_with_verify + task_count))
        elif [[ "$task_count" -gt 0 ]]; then
            # Partial credit
            tasks_with_verify=$((tasks_with_verify + verify_count))
        fi
    done

    if [[ "$total_tasks" -eq 0 ]]; then
        echo 0
    else
        local pct=$(( tasks_with_verify * 100 / total_tasks ))
        [[ "$pct" -gt 100 ]] && pct=100
        echo "$pct"
    fi
}

score_single_outcome() {
    local plan_file="$1"
    local total_batches mixed_batches=0
    total_batches=$(count_batches "$plan_file")
    [[ "$total_batches" -eq 0 ]] && { echo 0; return; }

    for ((b = 1; b <= total_batches; b++)); do
        local text
        text=$(get_batch_text "$plan_file" "$b")
        # Detect mixed types: creation + refactoring in same batch
        local has_create has_refactor
        has_create=$(echo "$text" | _count_matches '(create|add|new|implement)')
        has_refactor=$(echo "$text" | _count_matches '(refactor|rename|move|extract|reorganize)')

        # Mixed = has significant refactoring alongside significant creation
        if [[ "$has_create" -ge 2 && "$has_refactor" -ge 2 ]]; then
            mixed_batches=$((mixed_batches + 1))
        fi
    done

    if [[ "$mixed_batches" -eq 0 ]]; then
        echo 100
    else
        local pct=$(( 100 - (mixed_batches * 100 / total_batches) ))
        [[ "$pct" -lt 0 ]] && pct=0
        echo "$pct"
    fi
}

score_dependency_ordering() {
    local plan_file="$1"
    local total_batches forward_refs=0
    total_batches=$(count_batches "$plan_file")
    [[ "$total_batches" -eq 0 ]] && { echo 0; return; }

    for ((b = 1; b <= total_batches; b++)); do
        local text
        text=$(get_batch_text "$plan_file" "$b")
        # Check for references to later batches
        for ((future = b + 1; future <= total_batches; future++)); do
            if echo "$text" | grep -qE "(Batch ${future}|batch ${future})" 2>/dev/null; then
                forward_refs=$((forward_refs + 1))
                break
            fi
        done
    done

    if [[ "$forward_refs" -eq 0 ]]; then
        echo 100
    else
        local pct=$(( 100 - (forward_refs * 100 / total_batches) ))
        [[ "$pct" -lt 0 ]] && pct=0
        echo "$pct"
    fi
}

score_file_path_specificity() {
    local plan_file="$1"
    local total_batches batches_with_paths=0
    total_batches=$(count_batches "$plan_file")
    [[ "$total_batches" -eq 0 ]] && { echo 0; return; }

    for ((b = 1; b <= total_batches; b++)); do
        local text
        text=$(get_batch_text "$plan_file" "$b")
        # Check for file path patterns (backtick-wrapped paths or **Files:** sections)
        local path_count
        path_count=$(echo "$text" | _count_matches '(`[a-zA-Z0-9_./-]+\.[a-zA-Z]+`|\*\*Files:\*\*)')
        if [[ "$path_count" -gt 0 ]]; then
            batches_with_paths=$((batches_with_paths + 1))
        fi
    done

    echo $(( batches_with_paths * 100 / total_batches ))
}

score_acceptance_criteria() {
    local plan_file="$1"
    local total_batches batches_with_criteria=0
    total_batches=$(count_batches "$plan_file")
    [[ "$total_batches" -eq 0 ]] && { echo 0; return; }

    for ((b = 1; b <= total_batches; b++)); do
        local text
        text=$(get_batch_text "$plan_file" "$b")
        # Look for acceptance criteria patterns
        local criteria_count
        criteria_count=$(echo "$text" | _count_matches '(assert|expect|should|must|test.*pass|verify that|confirm)')
        if [[ "$criteria_count" -gt 0 ]]; then
            batches_with_criteria=$((batches_with_criteria + 1))
        fi
    done

    echo $(( batches_with_criteria * 100 / total_batches ))
}

score_batch_size() {
    local plan_file="$1"
    local total_batches good_batches=0
    total_batches=$(count_batches "$plan_file")
    [[ "$total_batches" -eq 0 ]] && { echo 0; return; }

    for ((b = 1; b <= total_batches; b++)); do
        local task_count
        task_count=$(get_batch_task_count "$plan_file" "$b")
        # Ideal: 1-5 tasks per batch
        if [[ "$task_count" -ge 1 && "$task_count" -le 5 ]]; then
            good_batches=$((good_batches + 1))
        fi
    done

    echo $(( good_batches * 100 / total_batches ))
}

score_tdd_structure() {
    local plan_file="$1"
    local total_batches tdd_batches=0
    total_batches=$(count_batches "$plan_file")
    [[ "$total_batches" -eq 0 ]] && { echo 0; return; }

    for ((b = 1; b <= total_batches; b++)); do
        local text
        text=$(get_batch_text "$plan_file" "$b")
        # Look for TDD patterns: explicit TDD language or test file references before source
        if echo "$text" | grep -qiE '(write.*test.*before|test.*first|failing test|red.green|TDD)' 2>/dev/null; then
            tdd_batches=$((tdd_batches + 1))
        elif echo "$text" | grep -qiE 'Test:.*test.*\.(py|js|ts|sh)' 2>/dev/null; then
            tdd_batches=$((tdd_batches + 1))
        fi
    done

    echo $(( tdd_batches * 100 / total_batches ))
}
