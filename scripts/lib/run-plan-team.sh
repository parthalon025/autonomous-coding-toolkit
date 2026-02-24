#!/usr/bin/env bash
# run-plan-team.sh — Team mode execution with parallel batch groups
#
# Analyzes plan dependency graph and executes batches in parallel groups.
# Each group's batches have all dependencies satisfied by prior groups.
# Headless version uses parallel `claude -p` processes.
#
# Requires sourced: run-plan-parser.sh, run-plan-routing.sh, run-plan-prompt.sh,
#   run-plan-quality-gate.sh, run-plan-state.sh, run-plan-context.sh, run-plan-scoring.sh
#
# Functions:
#   compute_parallel_groups <dep_graph_json> <start_batch> <end_batch> -> JSON [[1],[2,3],[4]]
#   run_mode_team  (uses globals: PLAN_FILE, WORKTREE, etc.)

# --- Compute parallel execution groups from dependency graph ---
# Takes a JSON dependency graph and batch range, returns JSON array of arrays.
# Each inner array is a group of batches that can run in parallel.
compute_parallel_groups() {
    local dep_graph="$1" start_batch="$2" end_batch="$3"

    # Collect all batch numbers in range
    local batches=()
    for ((b = start_batch; b <= end_batch; b++)); do
        batches+=("$b")
    done

    local completed=""
    local groups="["
    local first_group=true
    local remaining=${#batches[@]}

    while [[ "$remaining" -gt 0 ]]; do
        local group="["
        local first_in_group=true
        local new_completed=""
        local group_size=0

        for b in "${batches[@]}"; do
            # Skip already completed
            [[ "$completed" == *"|$b|"* ]] && continue

            # Check if all deps are satisfied (completed or outside range)
            local deps
            deps=$(echo "$dep_graph" | jq -r ".\"$b\"[]" 2>/dev/null || true)
            local all_met=true
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                local dep_num=$((dep + 0))
                # Deps outside our batch range are treated as satisfied
                if [[ "$dep_num" -ge "$start_batch" && "$dep_num" -le "$end_batch" ]]; then
                    if [[ "$completed" != *"|$dep|"* ]]; then
                        all_met=false
                        break
                    fi
                fi
            done <<< "$deps"

            if [[ "$all_met" == true ]]; then
                [[ "$first_in_group" != true ]] && group+=","
                group+="$b"
                first_in_group=false
                new_completed+="|$b|"
                group_size=$((group_size + 1))
                remaining=$((remaining - 1))
            fi
        done

        group+="]"
        completed+="$new_completed"

        if [[ "$group_size" -gt 0 ]]; then
            [[ "$first_group" != true ]] && groups+=","
            groups+="$group"
            first_group=false
        else
            break  # No progress — circular dependency or error
        fi
    done

    groups+="]"
    echo "$groups"
}

# --- Team mode execution (headless parallel) ---
run_mode_team() {
    # WARNING: Team mode uses a shared worktree. Concurrent git operations
    # (add, commit, stash) from parallel claude processes may conflict and
    # corrupt the staging area. Each batch in a group runs against the same
    # filesystem; the batches within a group are independent by design
    # (no shared files per the dependency graph), but git state is global.
    # For full isolation, run batches sequentially (headless mode) or ensure
    # batches in each parallel group touch strictly non-overlapping files.
    echo "WARNING: Team mode uses a shared worktree. Concurrent git operations may conflict." >&2

    local dep_graph
    dep_graph=$(build_dependency_graph "$PLAN_FILE")

    local groups
    groups=$(compute_parallel_groups "$dep_graph" "$START_BATCH" "$END_BATCH")
    local group_count
    group_count=$(echo "$groups" | jq 'length')

    mkdir -p "$WORKTREE/logs"

    # Initialize state if not resuming
    if [[ "$RESUME" != true ]]; then
        init_state "$WORKTREE" "$PLAN_FILE" "$MODE"
        if [[ "$START_BATCH" -gt 1 ]]; then
            for ((b = 1; b < START_BATCH; b++)); do
                complete_batch "$WORKTREE" "$b" 0
            done
        fi
    fi

    log_routing_decision "$WORKTREE" "MODE" "team mode selected ($group_count groups)"

    for ((g = 0; g < group_count; g++)); do
        local group_batches
        group_batches=$(echo "$groups" | jq -r ".[$g][]")
        local batch_count
        batch_count=$(echo "$group_batches" | wc -l)

        echo ""
        echo "================================================================"
        echo "  Group $((g+1))/$group_count: batches $(echo "$group_batches" | tr '\n' ',' | sed 's/,$//')"
        echo "  ($batch_count batches in parallel)"
        echo "================================================================"

        local pids=()
        local batch_logs=()
        local batch_list=()

        for batch in $group_batches; do
            local title
            title=$(get_batch_title "$PLAN_FILE" "$batch")
            local model
            model=$(classify_batch_model "$PLAN_FILE" "$batch")
            local log_file="$WORKTREE/logs/batch-${batch}-team.log"
            batch_logs+=("$log_file")
            batch_list+=("$batch")

            local prev_test_count
            prev_test_count=$(get_previous_test_count "$WORKTREE")

            local prompt
            prompt=$(build_batch_prompt "$PLAN_FILE" "$batch" "$WORKTREE" "$PYTHON" "$QUALITY_GATE_CMD" "$prev_test_count")

            log_routing_decision "$WORKTREE" "PARALLEL" "batch $batch ($title) [$model] in group $((g+1))"

            echo "  Starting batch $batch: $title ($model)..."
            CLAUDECODE='' claude -p "$prompt" \
                --model "$model" \
                --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
                --permission-mode bypassPermissions \
                > "$log_file" 2>&1 &
            pids+=($!)
        done

        # Wait for all batches in group
        local all_passed=true
        for i in "${!pids[@]}"; do
            local pid=${pids[$i]}
            local batch=${batch_list[$i]}
            wait "$pid" || true

            # Run quality gate
            local gate_exit=0
            run_quality_gate "$WORKTREE" "$QUALITY_GATE_CMD" "$batch" "0" || gate_exit=$?
            if [[ $gate_exit -eq 0 ]]; then
                echo "  Batch $batch PASSED"
                log_routing_decision "$WORKTREE" "GATE_PASS" "batch $batch passed quality gate"
            else
                echo "  Batch $batch FAILED quality gate"
                log_routing_decision "$WORKTREE" "GATE_FAIL" "batch $batch failed quality gate"
                all_passed=false
            fi
        done

        if [[ "$all_passed" != true ]]; then
            echo ""
            echo "Group $((g+1)) had failures. Stopping."
            exit 1
        fi
    done

    echo ""
    echo "================================================================"
    echo "  All groups complete ($group_count groups, batches $START_BATCH → $END_BATCH)"
    echo "================================================================"

    if [[ "$VERIFY" == true ]]; then
        echo ""
        echo "Running final verification..."
        run_quality_gate "$WORKTREE" "$QUALITY_GATE_CMD" "final" || {
            echo "FINAL VERIFICATION FAILED"
            exit 1
        }
    fi
}
