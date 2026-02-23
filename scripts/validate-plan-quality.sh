#!/usr/bin/env bash
# validate-plan-quality.sh — Score implementation plan quality on 8 dimensions
#
# Usage:
#   validate-plan-quality.sh <plan-file> [--min-score N] [--json]
#
# Returns score 0-100. Exit 0 if >= min-score (default: 60), exit 1 otherwise.
# Research basis: Plan quality has 3x the impact of execution quality (SWE-bench Pro, N=1865).
#
# Dimensions (weights):
#   1. Task granularity     — each task < 100 lines estimated       (15%)
#   2. Spec completeness    — each task has verification command     (20%)
#   3. Single outcome       — no mixed task types per batch          (10%)
#   4. Dependency ordering   — no forward references                  (10%)
#   5. File path specificity — all tasks name exact files             (15%)
#   6. Acceptance criteria   — each batch has at least one assert     (15%)
#   7. Batch size           — 1-5 tasks per batch                    (10%)
#   8. TDD structure        — test-before-implement pattern           (5%)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source parser for plan parsing functions
source "$SCRIPT_DIR/lib/run-plan-parser.sh"

# --- Defaults ---
PLAN_FILE=""
MIN_SCORE=60
JSON_OUTPUT=false

# --- Usage ---
usage() {
    cat <<'USAGE'
validate-plan-quality — Score implementation plan quality (0-100)

Usage:
  validate-plan-quality.sh <plan-file> [--min-score N] [--json]

Options:
  --min-score N   Minimum passing score (default: 60)
  --json          Output JSON report instead of text
  -h, --help      Show this help message

Dimensions scored:
  1. Task granularity (15%)   — tasks should be small (<100 lines each)
  2. Spec completeness (20%)  — tasks have verification commands
  3. Single outcome (10%)     — batches don't mix create/refactor/test
  4. Dependency ordering (10%) — no forward references to later batches
  5. File path specificity (15%) — tasks name exact file paths
  6. Acceptance criteria (15%) — batches have testable assertions
  7. Batch size (10%)          — 1-5 tasks per batch
  8. TDD structure (5%)        — test-before-implement ordering
USAGE
}

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --min-score) MIN_SCORE="$2"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        -*) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
        *) PLAN_FILE="$1"; shift ;;
    esac
done

if [[ -z "$PLAN_FILE" ]]; then
    echo "ERROR: Plan file required" >&2
    usage >&2
    exit 1
fi

if ! [[ "$MIN_SCORE" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --min-score must be a number, got: $MIN_SCORE" >&2
    exit 1
fi

if [[ ! -f "$PLAN_FILE" ]]; then
    echo "ERROR: Plan file not found: $PLAN_FILE" >&2
    exit 1
fi

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

# --- Scoring functions ---
# Each returns a score 0-100 for its dimension

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

# --- Main scoring ---
total_batches=$(count_batches "$PLAN_FILE")
if [[ "$total_batches" -eq 0 ]]; then
    echo "ERROR: No batches found in plan (expected '## Batch N:' headers)" >&2
    exit 1
fi

# Score each dimension
s_granularity=$(score_task_granularity "$PLAN_FILE")
s_spec=$(score_spec_completeness "$PLAN_FILE")
s_single=$(score_single_outcome "$PLAN_FILE")
s_deps=$(score_dependency_ordering "$PLAN_FILE")
s_paths=$(score_file_path_specificity "$PLAN_FILE")
s_criteria=$(score_acceptance_criteria "$PLAN_FILE")
s_batch_size=$(score_batch_size "$PLAN_FILE")
s_tdd=$(score_tdd_structure "$PLAN_FILE")

# Weighted total (weights sum to 100)
total=$(( (s_granularity * 15 + s_spec * 20 + s_single * 10 + s_deps * 10 + s_paths * 15 + s_criteria * 15 + s_batch_size * 10 + s_tdd * 5) / 100 ))

if [[ "$JSON_OUTPUT" == true ]]; then
    escaped_plan=$(printf '%s' "$PLAN_FILE" | jq -Rs '.')
    cat <<JSONEOF
{
  "plan_file": $escaped_plan,
  "total_batches": $total_batches,
  "score": $total,
  "min_score": $MIN_SCORE,
  "passed": $([ "$total" -ge "$MIN_SCORE" ] && echo "true" || echo "false"),
  "dimensions": {
    "task_granularity": {"score": $s_granularity, "weight": 15},
    "spec_completeness": {"score": $s_spec, "weight": 20},
    "single_outcome": {"score": $s_single, "weight": 10},
    "dependency_ordering": {"score": $s_deps, "weight": 10},
    "file_path_specificity": {"score": $s_paths, "weight": 15},
    "acceptance_criteria": {"score": $s_criteria, "weight": 15},
    "batch_size": {"score": $s_batch_size, "weight": 10},
    "tdd_structure": {"score": $s_tdd, "weight": 5}
  }
}
JSONEOF
else
    echo "Plan Quality Scorecard: $(basename "$PLAN_FILE")"
    echo "═══════════════════════════════════════════"
    printf "  %-25s %3d/100 (15%%)\n" "Task granularity" "$s_granularity"
    printf "  %-25s %3d/100 (20%%)\n" "Spec completeness" "$s_spec"
    printf "  %-25s %3d/100 (10%%)\n" "Single outcome" "$s_single"
    printf "  %-25s %3d/100 (10%%)\n" "Dependency ordering" "$s_deps"
    printf "  %-25s %3d/100 (15%%)\n" "File path specificity" "$s_paths"
    printf "  %-25s %3d/100 (15%%)\n" "Acceptance criteria" "$s_criteria"
    printf "  %-25s %3d/100 (10%%)\n" "Batch size" "$s_batch_size"
    printf "  %-25s %3d/100 ( 5%%)\n" "TDD structure" "$s_tdd"
    echo "═══════════════════════════════════════════"
    printf "  %-25s %3d/100 (min: %d)\n" "TOTAL" "$total" "$MIN_SCORE"
    echo ""
    if [[ "$total" -ge "$MIN_SCORE" ]]; then
        echo "PASSED"
    else
        echo "FAILED (score $total < min $MIN_SCORE)"
    fi
fi

if [[ "$total" -ge "$MIN_SCORE" ]]; then
    exit 0
else
    exit 1
fi
