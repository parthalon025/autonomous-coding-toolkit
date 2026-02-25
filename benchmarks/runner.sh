#!/usr/bin/env bash
# runner.sh — Benchmark orchestrator for the Autonomous Coding Toolkit
#
# Usage:
#   runner.sh run [task-name]      Run all or one benchmark
#   runner.sh compare <a> <b>      Compare two result files
#   runner.sh list                 List available benchmarks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TASKS_DIR="$SCRIPT_DIR/tasks"
RESULTS_DIR="${BENCHMARK_RESULTS_DIR:-$SCRIPT_DIR/results}"

usage() {
    cat <<'USAGE'
Usage: runner.sh <run|compare|list> [options]

Commands:
  run [name]        Run all benchmarks, or a specific one by directory name
  compare <a> <b>   Compare two result JSON files
  list              List available benchmark tasks

Options:
  --help, -h        Show this help

Results are saved to benchmarks/results/ (gitignored).
USAGE
    exit 0
}

SUBCOMMAND="${1:-}"
shift || true

case "$SUBCOMMAND" in
    list)
        echo "Available benchmarks:"
        for task_dir in "$TASKS_DIR"/*/; do
            [[ -d "$task_dir" ]] || continue
            name=$(basename "$task_dir")
            desc=""
            if [[ -f "$task_dir/task.md" ]]; then
                desc=$(head -1 "$task_dir/task.md" | sed 's/^# //')
            fi
            echo "  $name — $desc"
        done
        ;;

    run)
        TARGET="${1:-all}"
        mkdir -p "$RESULTS_DIR"
        timestamp=$(date -u +%Y%m%dT%H%M%SZ)

        run_benchmark() {
            local task_dir="$1"
            local name=$(basename "$task_dir")
            echo "=== Benchmark: $name ==="

            if [[ ! -f "$task_dir/rubric.sh" ]]; then
                echo "  SKIP: no rubric.sh found"
                return
            fi

            local score=0
            local total=0
            local pass=0

            # Run rubric — each line of output is "PASS: desc" or "FAIL: desc"
            while IFS= read -r line; do
                total=$((total + 1))
                if [[ "$line" == PASS:* ]]; then
                    pass=$((pass + 1))
                fi
                echo "  $line"
            done < <(bash "$task_dir/rubric.sh" 2>&1 || true)

            if [[ $total -gt 0 ]]; then
                score=$((pass * 100 / total))
            fi
            echo "  Score: ${score}% ($pass/$total)"
            echo ""

            # Write result
            jq -n --arg name "$name" --argjson score "$score" \
                --argjson pass "$pass" --argjson total "$total" \
                --arg ts "$timestamp" \
                '{name: $name, score: $score, passed: $pass, total: $total, timestamp: $ts}' \
                >> "$RESULTS_DIR/$timestamp.jsonl"
        }

        if [[ "$TARGET" == "all" ]]; then
            for task_dir in "$TASKS_DIR"/*/; do
                [[ -d "$task_dir" ]] || continue
                run_benchmark "$task_dir"
            done
        else
            if [[ -d "$TASKS_DIR/$TARGET" ]]; then
                run_benchmark "$TASKS_DIR/$TARGET"
            else
                echo "Benchmark not found: $TARGET" >&2
                echo "Run 'runner.sh list' to see available benchmarks." >&2
                exit 1
            fi
        fi

        echo "Results saved to: $RESULTS_DIR/$timestamp.jsonl"
        ;;

    compare)
        FILE_A="${1:-}"
        FILE_B="${2:-}"
        if [[ -z "$FILE_A" || -z "$FILE_B" ]]; then
            echo "Usage: runner.sh compare <result-a.jsonl> <result-b.jsonl>" >&2
            exit 1
        fi
        if [[ ! -f "$FILE_A" || ! -f "$FILE_B" ]]; then
            echo "One or both files not found." >&2
            exit 1
        fi

        echo "Benchmark Comparison"
        echo "═════════════════════════════════════"
        printf "%-25s %8s %8s %8s\n" "Task" "Before" "After" "Delta"
        echo "─────────────────────────────────────────────"

        jq -s '
            [.[0], .[1]] | transpose | .[] |
            select(.[0] != null and .[1] != null) |
            "\(.[0].name)|\(.[0].score)|\(.[1].score)|\(.[1].score - .[0].score)"
        ' <(jq -s '.' "$FILE_A") <(jq -s '.' "$FILE_B") 2>/dev/null | \
        while IFS='|' read -r name before after delta; do
            sign=""
            [[ "$delta" -gt 0 ]] && sign="+"
            printf "%-25s %7s%% %7s%% %7s%%\n" "$name" "$before" "$after" "${sign}${delta}"
        done

        echo "═════════════════════════════════════"
        ;;

    help|--help|-h|"")
        usage
        ;;

    *)
        echo "Unknown command: $SUBCOMMAND" >&2
        usage
        ;;
esac
