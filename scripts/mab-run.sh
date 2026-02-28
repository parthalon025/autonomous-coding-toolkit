#!/usr/bin/env bash
# mab-run.sh — MAB orchestrator: worktrees, competing agents, judge, merge
#
# Usage:
#   mab-run.sh --plan <file> --batch <N> --work-unit <desc> --worktree <dir> [options]
#   mab-run.sh --init-data --worktree <dir>
#   mab-run.sh --help
#
# Options:
#   --plan <file>         Implementation plan file
#   --batch <N>           Batch number to execute
#   --work-unit <desc>    Work unit description
#   --worktree <dir>      Base worktree directory
#   --dry-run             Show planned actions without executing
#   --init-data           Initialize strategy-perf.json and mab-lessons.json
#   --prd <file>          PRD file path (optional)
#   --quality-gate <cmd>  Quality gate command
#   -h, --help            Show this help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# Source dependencies
source "$SCRIPT_DIR/lib/thompson-sampling.sh"
source "$SCRIPT_DIR/lib/mab-run-agents.sh"
source "$SCRIPT_DIR/lib/mab-run-data.sh"
if [[ -f "$SCRIPT_DIR/lib/run-plan-scoring.sh" ]]; then
    source "$SCRIPT_DIR/lib/run-plan-scoring.sh"
fi
if [[ -f "$SCRIPT_DIR/lib/run-plan-state.sh" ]]; then
    source "$SCRIPT_DIR/lib/run-plan-state.sh"
fi

# --- Defaults ---
MAB_PLAN=""
MAB_BATCH=""
MAB_WORK_UNIT=""
MAB_WORKTREE=""
MAB_DRY_RUN=false
MAB_INIT_DATA=false
MAB_PRD=""
MAB_QUALITY_GATE="scripts/quality-gate.sh --project-root ."
MAB_SOURCE_ONLY=false

# --- Usage ---
mab_usage() {
    cat <<'USAGE'
mab-run.sh — MAB orchestrator for competing agent strategies

Usage:
  mab-run.sh --plan <file> --batch <N> --work-unit <desc> --worktree <dir> [options]
  mab-run.sh --init-data --worktree <dir>

Runs two agents (superpowers + ralph) in parallel worktrees on the same work
unit. A judge agent evaluates both outputs. Quality gate override: if only one
agent passes, that agent wins regardless of judge verdict.

Options:
  --plan <file>         Implementation plan file
  --batch <N>           Batch number to execute
  --work-unit <desc>    Work unit description
  --worktree <dir>      Base worktree directory
  --dry-run             Show planned actions without executing
  --init-data           Initialize strategy-perf.json and mab-lessons.json
  --prd <file>          PRD file path (optional)
  --quality-gate <cmd>  Quality gate command
  -h, --help            Show this help
USAGE
}

# --- Argument parsing ---
parse_mab_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source-only)
                MAB_SOURCE_ONLY=true; shift ;;
            -h|--help)
                mab_usage; exit 0 ;;
            --plan)
                MAB_PLAN="$2"; shift 2 ;;
            --batch)
                MAB_BATCH="$2"; shift 2 ;;
            --work-unit)
                MAB_WORK_UNIT="$2"; shift 2 ;;
            --worktree)
                MAB_WORKTREE="$2"; shift 2 ;;
            --dry-run)
                MAB_DRY_RUN=true; shift ;;
            --init-data)
                MAB_INIT_DATA=true; shift ;;
            --prd)
                MAB_PRD="$2"; shift 2 ;;
            --quality-gate)
                MAB_QUALITY_GATE="$2"; shift 2 ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                mab_usage >&2
                exit 1 ;;
        esac
    done
}

# --- Validation ---
validate_mab_args() {
    if [[ "$MAB_INIT_DATA" == true ]]; then
        if [[ -z "$MAB_WORKTREE" ]]; then
            echo "ERROR: --init-data requires --worktree" >&2
            exit 1
        fi
        return
    fi

    if [[ -z "$MAB_PLAN" || ! -f "$MAB_PLAN" ]]; then
        echo "ERROR: --plan file required and must exist" >&2
        exit 1
    fi

    if [[ -z "$MAB_BATCH" ]]; then
        echo "ERROR: --batch required" >&2
        exit 1
    fi

    # Validate batch is numeric
    if ! [[ "$MAB_BATCH" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --batch must be a number (got: $MAB_BATCH)" >&2
        exit 1
    fi

    if [[ -z "$MAB_WORK_UNIT" ]]; then
        echo "ERROR: --work-unit required" >&2
        exit 1
    fi

    if [[ -z "$MAB_WORKTREE" ]]; then
        echo "ERROR: --worktree required" >&2
        exit 1
    fi
}

# --- Main orchestration ---
run_mab() {
    local perf_file="$MAB_WORKTREE/logs/strategy-perf.json"
    [[ ! -f "$perf_file" ]] && init_strategy_perf "$perf_file"

    local lessons_file="$MAB_WORKTREE/logs/mab-lessons.json"
    [[ ! -f "$lessons_file" ]] && echo "[]" > "$lessons_file"

    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  MAB Run — Batch $MAB_BATCH"
    echo "║  Work: $MAB_WORK_UNIT"
    echo "╚══════════════════════════════════════════════════════╝"

    if [[ "$MAB_DRY_RUN" == true ]]; then
        echo ""
        echo "=== DRY RUN ==="
        echo "  Plan: $MAB_PLAN"
        echo "  Batch: $MAB_BATCH"
        echo "  Work unit: $MAB_WORK_UNIT"
        echo "  Worktree: $MAB_WORKTREE"
        echo "  Quality gate: $MAB_QUALITY_GATE"
        echo ""
        echo "  Would create worktrees:"
        echo "    agent-a: $MAB_WORKTREE/.mab-worktrees/agent-a"
        echo "    agent-b: $MAB_WORKTREE/.mab-worktrees/agent-b"
        echo ""
        echo "  Would run agents in parallel, invoke judge, merge winner."
        echo "=== END DRY RUN ==="
        return 0
    fi

    # Load MAB lessons for injection
    local mab_lessons_text=""
    if [[ -f "$lessons_file" ]]; then
        mab_lessons_text=$(jq -r '
            sort_by(-.occurrences // 0) | .[0:5] | .[] |
            "- \(.pattern) (\(.context // "general")): winner=\(.winner // "unknown")"
        ' "$lessons_file" 2>/dev/null || echo "No lessons yet.")
    fi
    [[ -z "$mab_lessons_text" ]] && mab_lessons_text="No lessons yet."

    # Resolve paths
    local prd_path="${MAB_PRD:-tasks/prd.json}"
    local arch_map_path="docs/ARCHITECTURE-MAP.json"

    # Assemble prompts
    local prompt_a_template prompt_b_template
    prompt_a_template=$(cat "$SCRIPT_DIR/prompts/agent-a-superpowers.md")
    prompt_b_template=$(cat "$SCRIPT_DIR/prompts/agent-b-ralph.md")

    local prompt_a prompt_b
    prompt_a=$(assemble_agent_prompt "$prompt_a_template" "$MAB_WORK_UNIT" "$prd_path" "$arch_map_path" "$mab_lessons_text" "$MAB_QUALITY_GATE")
    prompt_b=$(assemble_agent_prompt "$prompt_b_template" "$MAB_WORK_UNIT" "$prd_path" "$arch_map_path" "$mab_lessons_text" "$MAB_QUALITY_GATE")

    # Create worktrees
    echo ""
    echo "--- Creating worktrees ---"
    local worktrees
    worktrees=$(create_mab_worktrees "$MAB_WORKTREE" "$MAB_BATCH")
    local wt_a wt_b
    wt_a=$(echo "$worktrees" | awk '{print $1}')
    wt_b=$(echo "$worktrees" | awk '{print $2}')
    echo "  Agent A: $wt_a"
    echo "  Agent B: $wt_b"

    # Run agents in parallel
    echo ""
    echo "--- Running agents ---"
    run_agents_parallel "$wt_a" "$wt_b" "$prompt_a" "$prompt_b" || true

    # Run quality gates
    echo ""
    echo "--- Quality gates ---"
    # Capture gate exit codes without disabling set -e inside functions (SC2310)
    local gate_a gate_b
    set +e; run_gate_on_agent "$wt_a" "agent-a"; gate_a=$?; set -e
    set +e; run_gate_on_agent "$wt_b" "agent-b"; gate_b=$?; set -e

    # Invoke judge (only if both agents ran)
    echo ""
    echo "--- Judge evaluation ---"
    local judge_result judge_winner judge_lesson
    judge_result=$(invoke_judge "$wt_a" "$wt_b" \
        "$MAB_WORKTREE/logs/mab-gate-agent-a.log" \
        "$MAB_WORKTREE/logs/mab-gate-agent-b.log")
    judge_winner=$(echo "$judge_result" | cut -d'|' -f1)
    judge_lesson=$(echo "$judge_result" | cut -d'|' -f2-)
    echo "  Judge verdict: $judge_winner"

    # Apply gate override
    local final_winner
    final_winner=$(select_winner_with_gate_override "$gate_a" "$gate_b" "$judge_winner")
    echo "  Final winner: $final_winner (gate override applied)"

    # Human calibration
    final_winner=$(prompt_human_calibration "$final_winner" "$perf_file")

    if [[ "$final_winner" == "none" || "$final_winner" == "tie" ]]; then
        echo "  No winner — both agents failed or tie with no override."
        cleanup_mab_worktrees "$MAB_WORKTREE" "$MAB_BATCH"
        return 1
    fi

    # Merge winner
    echo ""
    echo "--- Merging winner ($final_winner) ---"
    merge_winner "$final_winner" "$wt_a" "$wt_b"

    # Classify batch type for data recording
    local batch_type="unknown"
    if type classify_batch_type &>/dev/null && [[ -n "$MAB_PLAN" ]]; then
        batch_type=$(classify_batch_type "$MAB_PLAN" "$MAB_BATCH" 2>/dev/null || echo "unknown")
    fi

    # Update data
    update_mab_data "$final_winner" "$judge_lesson" "$batch_type"

    # Cleanup
    echo ""
    echo "--- Cleanup ---"
    cleanup_mab_worktrees "$MAB_WORKTREE" "$MAB_BATCH"

    echo ""
    echo "MAB batch $MAB_BATCH complete. Winner: $final_winner"
}

# --- Entry point ---
parse_mab_args "$@"

# --source-only: export functions for testing, don't execute
if [[ "$MAB_SOURCE_ONLY" == true ]]; then
    return 0 2>/dev/null || exit 0
fi

validate_mab_args

if [[ "$MAB_INIT_DATA" == true ]]; then
    mkdir -p "$MAB_WORKTREE/logs"
    init_strategy_perf "$MAB_WORKTREE/logs/strategy-perf.json"
    echo "[]" > "$MAB_WORKTREE/logs/mab-lessons.json"
    echo "Initialized MAB data files in $MAB_WORKTREE/logs/"
    exit 0
fi

run_mab
