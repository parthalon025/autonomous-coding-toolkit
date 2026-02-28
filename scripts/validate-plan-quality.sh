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

# Source scoring functions
source "$SCRIPT_DIR/lib/validate-plan-quality-scorers.sh"

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
