#!/usr/bin/env bash
# run-plan.sh — Execute implementation plans via headless Claude batches
#
# Usage:
#   run-plan.sh <plan-file> [options]
#   run-plan.sh --resume [options]
#
# Modes:
#   headless     (default) — bash loop calling claude -p per batch
#   team         — prints launch command for Claude agent team mode
#   competitive  — prints launch command for competitive agent mode
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Signal handling ---
# Log unexpected exits for diagnostics (silent death prevention)
_run_plan_exit_code=0
_run_plan_exit_logged=false
_log_exit() {
    local code=${1:-$?}
    [[ "$_run_plan_exit_logged" == true ]] && return
    _run_plan_exit_logged=true
    if [[ $code -ne 0 ]]; then
        echo "" >&2
        echo "run-plan: EXIT with code $code at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >&2
        # Print last few lines of bash call stack
        local i
        for ((i = 0; i < ${#FUNCNAME[@]}; i++)); do
            echo "  ${BASH_SOURCE[$i]:-unknown}:${BASH_LINENO[$i]:-?} in ${FUNCNAME[$i]:-main}" >&2
        done
    fi
}
trap '_log_exit $?' EXIT

# Ignore HUP and PIPE so background execution survives terminal disconnect
# and broken pipe from task manager stdout (confirmed root cause: exit 141 = SIGPIPE)
trap '' HUP PIPE

# Source all lib functions
source "$SCRIPT_DIR/lib/run-plan-parser.sh"
source "$SCRIPT_DIR/lib/run-plan-state.sh"
source "$SCRIPT_DIR/lib/run-plan-quality-gate.sh"
source "$SCRIPT_DIR/lib/run-plan-notify.sh"
source "$SCRIPT_DIR/lib/run-plan-prompt.sh"
source "$SCRIPT_DIR/lib/progress-writer.sh"
source "$SCRIPT_DIR/lib/run-plan-headless.sh"
source "$SCRIPT_DIR/lib/run-plan-context.sh"
source "$SCRIPT_DIR/lib/progress-writer.sh"
source "$SCRIPT_DIR/lib/run-plan-scoring.sh"
source "$SCRIPT_DIR/lib/cost-tracking.sh"
source "$SCRIPT_DIR/lib/run-plan-team.sh"

# --- Defaults ---
PLAN_FILE=""
MODE="headless"
START_BATCH=""
END_BATCH=""
WORKTREE="$(pwd)"
PYTHON="python3"
QUALITY_GATE_CMD="scripts/quality-gate.sh --project-root ."
ON_FAILURE="stop"
MAX_RETRIES=2
COMPETITIVE_BATCHES=""
SAMPLE_COUNT=0  # 0 = disabled
NOTIFY=false
VERIFY=false
RESUME=false
SKIP_PLAN_QUALITY=false
SKIP_ECHO_BACK=false
MAX_BUDGET=""

# --- Usage ---
usage() {
    cat <<'USAGE'
run-plan — Execute implementation plans via headless Claude batches

Usage:
  run-plan.sh <plan-file> [options]
  run-plan.sh --resume [options]

Options:
  --mode <headless|team|competitive>   Execution mode (default: headless)
  --start-batch N                      First batch to execute
  --end-batch N                        Last batch to execute
  --worktree <path>                    Working directory (default: cwd)
  --python <path>                      Python interpreter (default: python3)
  --quality-gate <cmd>                 Quality gate command
                                       (default: "scripts/quality-gate.sh --project-root .")
  --on-failure <stop|skip|retry>       Failure handling (default: stop)
  --max-retries N                      Max retries per batch (default: 2)
  --competitive-batches N,N,...        Batches for competitive mode
  --sample N                           Parallel patch sampling (N candidates, default 3)
  --no-sample                          Disable sampling (default)
  --notify                             Send Telegram notifications
  --verify                             Run verification after all batches
  --skip-plan-quality                  Skip plan quality scorecard check
  --skip-echo-back                     Skip spec echo-back verification
  --resume                             Resume from saved state
  --max-budget <dollars>               Budget cap (reserved for future use)
  -h, --help                           Show this help message

Modes:
  headless      Bash loop calling claude -p per batch (runs locally)
  team          Multi-agent team mode (prints Claude launch command)
  competitive   Competitive agent mode (prints Claude launch command)

Examples:
  run-plan.sh docs/plans/2026-02-20-feature.md
  run-plan.sh docs/plans/2026-02-20-feature.md --mode headless --start-batch 2
  run-plan.sh --resume --worktree /path/to/worktree
  run-plan.sh docs/plans/feature.md --on-failure retry --max-retries 3 --notify
USAGE
}

# --- Argument parsing ---
# shellcheck disable=SC2034  # Globals consumed by sourced lib scripts
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --mode)
                MODE="$2"; shift 2
                ;;
            --start-batch)
                START_BATCH="$2"; shift 2
                ;;
            --end-batch)
                END_BATCH="$2"; shift 2
                ;;
            --worktree)
                WORKTREE="$2"; shift 2
                ;;
            --python)
                PYTHON="$2"; shift 2
                ;;
            --quality-gate)
                QUALITY_GATE_CMD="$2"; shift 2
                ;;
            --on-failure)
                ON_FAILURE="$2"; shift 2
                ;;
            --max-retries)
                MAX_RETRIES="$2"; shift 2
                ;;
            --competitive-batches)
                COMPETITIVE_BATCHES="$2"; shift 2
                ;;
            --sample)
                SAMPLE_COUNT="${2:-3}"; shift 2
                ;;
            --no-sample)
                SAMPLE_COUNT=0; shift
                ;;
            --notify)
                NOTIFY=true; shift
                ;;
            --verify)
                VERIFY=true; shift
                ;;
            --skip-plan-quality)
                SKIP_PLAN_QUALITY=true; shift
                ;;
            --skip-echo-back)
                SKIP_ECHO_BACK=true; shift
                ;;
            --resume)
                RESUME=true; shift
                ;;
            --max-budget)
                MAX_BUDGET="$2"; shift 2
                ;;
            -*)
                echo "ERROR: Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
            *)
                # Positional arg = plan file
                if [[ -z "$PLAN_FILE" ]]; then
                    PLAN_FILE="$1"
                else
                    echo "ERROR: Unexpected argument: $1" >&2
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# --- Validation ---
validate_args() {
    # Resume mode: load state file
    if [[ "$RESUME" == true ]]; then
        local state_file="$WORKTREE/.run-plan-state.json"
        if [[ ! -f "$state_file" ]]; then
            echo "ERROR: No state file found at $state_file" >&2
            echo "Cannot resume without a previous run." >&2
            exit 1
        fi
        # Load defaults from state
        if [[ -z "$PLAN_FILE" ]]; then
            PLAN_FILE=$(read_state_field "$WORKTREE" "plan_file")
        fi
        if [[ -z "$MODE" || "$MODE" == "headless" ]]; then
            local saved_mode
            saved_mode=$(read_state_field "$WORKTREE" "mode")
            if [[ -n "$saved_mode" && "$saved_mode" != "null" ]]; then
                MODE="$saved_mode"
            fi
        fi
        if [[ -z "$START_BATCH" ]]; then
            START_BATCH=$(read_state_field "$WORKTREE" "current_batch")
        fi
    fi

    # Must have a plan file
    if [[ -z "$PLAN_FILE" ]]; then
        echo "ERROR: No plan file specified. Use: run-plan.sh <plan-file> or --resume" >&2
        exit 1
    fi

    # Plan file must exist
    if [[ ! -f "$PLAN_FILE" ]]; then
        echo "ERROR: Plan file not found: $PLAN_FILE" >&2
        exit 1
    fi

    # Validate mode
    case "$MODE" in
        headless|team|competitive) ;;
        *)
            echo "ERROR: Invalid mode: $MODE (must be headless, team, or competitive)" >&2
            exit 1
            ;;
    esac

    # Validate on-failure
    case "$ON_FAILURE" in
        stop|skip|retry) ;;
        *)
            echo "ERROR: Invalid --on-failure: $ON_FAILURE (must be stop, skip, or retry)" >&2
            exit 1
            ;;
    esac

    # Set batch range defaults
    local total
    total=$(count_batches "$PLAN_FILE")
    if [[ -z "$START_BATCH" ]]; then
        START_BATCH=1
    fi
    if [[ -z "$END_BATCH" ]]; then
        END_BATCH="$total"
    fi
}

# --- Banner ---
print_banner() {
    local total
    total=$(count_batches "$PLAN_FILE")
    local plan_display
    plan_display=$(basename "$PLAN_FILE")

    cat <<BANNER
╔══════════════════════════════════════════════════════╗
║  run-plan — $MODE mode
║  Plan: $plan_display
║  Batches: $START_BATCH → $END_BATCH (of $total)
║  Worktree: $WORKTREE
╚══════════════════════════════════════════════════════╝
BANNER
}

# --- Mode stubs ---
run_mode_competitive() {
    echo "Competitive mode requires a Claude session with agent teams enabled."
    echo ""
    echo "Launch command:"
    echo "  CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude -p \"/run-plan $PLAN_FILE --mode competitive --start-batch $START_BATCH --end-batch $END_BATCH --worktree $WORKTREE\" --allowedTools '*' --permission-mode bypassPermissions"
}

# --- Main ---
main() {
    parse_args "$@"
    validate_args
    print_banner

    # Plan quality gate (skip on resume or explicit flag)
    if [[ "$SKIP_PLAN_QUALITY" != true && "$RESUME" != true ]]; then
        echo ""
        echo "Running plan quality check..."
        if ! bash "$SCRIPT_DIR/validate-plan-quality.sh" "$PLAN_FILE" --min-score 60; then
            echo ""
            echo "Plan quality below threshold. Use --skip-plan-quality to override."
            exit 1
        fi
        echo ""
    fi

    case "$MODE" in
        headless)
            run_mode_headless
            ;;
        team)
            run_mode_team
            ;;
        competitive)
            run_mode_competitive
            ;;
    esac
}

main "$@"
