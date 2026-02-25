#!/usr/bin/env bash
# telemetry.sh — Local telemetry capture, dashboard, export, and import
#
# Usage:
#   telemetry.sh record --project-root <dir> [--batch-number N] [--passed true|false] ...
#   telemetry.sh show --project-root <dir>
#   telemetry.sh export --project-root <dir>
#   telemetry.sh import --project-root <dir> <file>
#   telemetry.sh reset --project-root <dir> --yes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT=""
SUBCOMMAND=""

# --- Parse top-level ---
SUBCOMMAND="${1:-}"
shift || true

# Parse remaining args
BATCH_NUMBER=""
PASSED=""
STRATEGY=""
DURATION=""
COST=""
TEST_DELTA=""
LESSONS_TRIGGERED=""
PLAN_QUALITY=""
BATCH_TYPE=""
CONFIRM_YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
        --batch-number) BATCH_NUMBER="${2:-}"; shift 2 ;;
        --passed) PASSED="${2:-}"; shift 2 ;;
        --strategy) STRATEGY="${2:-}"; shift 2 ;;
        --duration) DURATION="${2:-}"; shift 2 ;;
        --cost) COST="${2:-}"; shift 2 ;;
        --test-delta) TEST_DELTA="${2:-}"; shift 2 ;;
        --lessons-triggered) LESSONS_TRIGGERED="${2:-}"; shift 2 ;;
        --plan-quality) PLAN_QUALITY="${2:-}"; shift 2 ;;
        --batch-type) BATCH_TYPE="${2:-}"; shift 2 ;;
        --yes) CONFIRM_YES=true; shift ;;
        --help|-h) echo "Usage: telemetry.sh <record|show|export|import|reset> --project-root <dir> [options]"; exit 0 ;;
        *)
            # Positional arg (for import file)
            if [[ -z "${IMPORT_FILE:-}" ]]; then
                IMPORT_FILE="$1"
            fi
            shift ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "telemetry: --project-root is required" >&2
    exit 1
fi

TELEMETRY_FILE="$PROJECT_ROOT/logs/telemetry.jsonl"

case "$SUBCOMMAND" in
    record)
        mkdir -p "$PROJECT_ROOT/logs"
        # Coerce numeric fields to prevent jq tonumber failures on empty strings
        BATCH_NUMBER="${BATCH_NUMBER:-0}"; BATCH_NUMBER="${BATCH_NUMBER:-0}"
        DURATION="${DURATION:-0}"; COST="${COST:-0}"; TEST_DELTA="${TEST_DELTA:-0}"
        jq -cn \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg bn "${BATCH_NUMBER:-0}" \
            --arg passed "${PASSED:-false}" \
            --arg strategy "${STRATEGY:-unknown}" \
            --arg duration "${DURATION:-0}" \
            --arg cost "${COST:-0}" \
            --arg td "${TEST_DELTA:-0}" \
            --arg lt "${LESSONS_TRIGGERED:-}" \
            --arg pq "${PLAN_QUALITY:-}" \
            --arg bt "${BATCH_TYPE:-unknown}" \
            --arg pt "$(detect_project_type "$PROJECT_ROOT")" \
            '{
                timestamp: $ts,
                project_type: $pt,
                batch_type: $bt,
                batch_number: ($bn | tonumber),
                passed_gate: ($passed == "true"),
                strategy: $strategy,
                duration_seconds: ($duration | tonumber),
                cost_usd: ($cost | tonumber),
                test_count_delta: ($td | tonumber),
                lessons_triggered: (if $lt == "" then [] else ($lt | split(",")) end),
                plan_quality_score: (if $pq == "" then null else ($pq | tonumber) end)
            }' >> "$TELEMETRY_FILE"
        echo "telemetry: recorded batch $BATCH_NUMBER"
        ;;

    show)
        echo "Autonomous Coding Toolkit — Telemetry Dashboard"
        echo "════════════════════════════════════════════════"
        echo ""

        if [[ ! -f "$TELEMETRY_FILE" ]] || [[ ! -s "$TELEMETRY_FILE" ]]; then
            echo "No telemetry data yet. Run some batches first."
            exit 0
        fi

        # Summary stats
        total=$(wc -l < "$TELEMETRY_FILE")
        passed=$(jq -s '[.[] | select(.passed_gate == true)] | length' "$TELEMETRY_FILE")
        total_cost=$(jq -s '[.[].cost_usd] | add // 0' "$TELEMETRY_FILE")
        total_duration=$(jq -s '[.[].duration_seconds] | add // 0' "$TELEMETRY_FILE")
        avg_cost=$(jq -s 'if length > 0 then ([.[].cost_usd] | add) / length else 0 end' "$TELEMETRY_FILE")

        echo "Runs: $total batches"
        if [[ "$total" -gt 0 ]]; then
            pct=$((passed * 100 / total))
            echo "Success rate: ${pct}% ($passed/$total passed gate on first attempt)"
        fi
        printf "Total cost: \$%.2f (\$%.2f/batch average)\n" "$total_cost" "$avg_cost"
        hours=$(awk "BEGIN {printf \"%.1f\", $total_duration / 3600}")
        echo "Total time: ${hours} hours"

        # Strategy performance
        echo ""
        echo "Strategy Performance:"
        jq -s '
            group_by(.strategy) | .[] |
            {
                strategy: .[0].strategy,
                wins: [.[] | select(.passed_gate == true)] | length,
                total: length
            } |
            "  \(.strategy): \(.wins)/\(.total) (\(if .total > 0 then (.wins * 100 / .total) else 0 end)% win rate)"
        ' "$TELEMETRY_FILE" 2>/dev/null || echo "  (no strategy data)"

        # Top lesson hits
        echo ""
        echo "Top Lesson Hits:"
        jq -s '
            [.[].lessons_triggered | arrays | .[]] |
            group_by(.) | map({lesson: .[0], count: length}) |
            sort_by(-.count) | .[:5] |
            .[] | "  \(.lesson): \(.count) hits"
        ' "$TELEMETRY_FILE" 2>/dev/null || echo "  (no lesson data)"
        ;;

    export)
        if [[ ! -f "$TELEMETRY_FILE" ]]; then
            echo "No telemetry data to export." >&2
            exit 1
        fi
        # Anonymize: remove timestamps precision, no file paths
        jq -s '
            [.[] | {
                project_type,
                batch_type,
                passed_gate,
                strategy,
                duration_seconds,
                cost_usd,
                test_count_delta,
                lessons_triggered,
                plan_quality_score
            }]
        ' "$TELEMETRY_FILE"
        ;;

    import)
        if [[ -z "${IMPORT_FILE:-}" || ! -f "${IMPORT_FILE:-}" ]]; then
            echo "telemetry: import requires a file argument" >&2
            exit 1
        fi
        echo "telemetry: import not yet implemented (planned for community sync)"
        ;;

    reset)
        if [[ "$CONFIRM_YES" != true ]]; then
            echo "telemetry: use --yes to confirm reset" >&2
            exit 1
        fi
        if [[ -f "$TELEMETRY_FILE" ]]; then
            > "$TELEMETRY_FILE"
            echo "telemetry: cleared $TELEMETRY_FILE"
        else
            echo "telemetry: no telemetry file to reset"
        fi
        ;;

    *)
        echo "Usage: telemetry.sh <record|show|export|import|reset> --project-root <dir>" >&2
        exit 1
        ;;
esac
