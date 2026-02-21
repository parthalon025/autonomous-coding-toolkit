#!/usr/bin/env bash
# run-plan-headless.sh — Headless batch execution loop for run-plan
#
# Extracted from run-plan.sh to keep the main script under 300 lines.
#
# Requires these globals set before calling:
#   WORKTREE, RESUME, START_BATCH, END_BATCH, NOTIFY, PLAN_FILE,
#   QUALITY_GATE_CMD, PYTHON, MAX_RETRIES, ON_FAILURE, VERIFY, MODE
#
# Requires these libs sourced:
#   run-plan-parser.sh, run-plan-state.sh, run-plan-quality-gate.sh,
#   run-plan-notify.sh, run-plan-prompt.sh

run_mode_headless() {
    mkdir -p "$WORKTREE/logs"

    # Initialize state if not resuming
    if [[ "$RESUME" != true ]]; then
        init_state "$WORKTREE" "$PLAN_FILE" "$MODE"

        # Mark earlier batches as completed (if --start-batch > 1)
        if [[ "$START_BATCH" -gt 1 ]]; then
            for ((b = 1; b < START_BATCH; b++)); do
                complete_batch "$WORKTREE" "$b" 0
            done
        fi
    fi

    # Load telegram credentials if notifications enabled
    if [[ "$NOTIFY" == true ]]; then
        _load_telegram_env || echo "WARNING: Telegram notifications unavailable" >&2
    fi

    local plan_name
    plan_name=$(basename "$PLAN_FILE" .md)

    for ((batch = START_BATCH; batch <= END_BATCH; batch++)); do
        local title
        title=$(get_batch_title "$PLAN_FILE" "$batch")
        echo ""
        echo "================================================================"
        echo "  Batch $batch: $title"
        echo "================================================================"

        local prev_test_count
        prev_test_count=$(get_previous_test_count "$WORKTREE")

        local prompt
        prompt=$(build_batch_prompt "$PLAN_FILE" "$batch" "$WORKTREE" "$PYTHON" "$QUALITY_GATE_CMD" "$prev_test_count")

        local max_attempts=$((MAX_RETRIES + 1))
        local attempt=0
        local batch_passed=false

        while [[ $attempt -lt $max_attempts ]]; do
            attempt=$((attempt + 1))
            local log_file="$WORKTREE/logs/batch-${batch}-attempt-${attempt}.log"
            local batch_start
            batch_start=$(date +%s)

            echo ""
            echo "--- Attempt $attempt of $max_attempts ---"

            # Build escalation context for retries
            local full_prompt="$prompt"
            if [[ $attempt -eq 2 ]]; then
                local prev_log="$WORKTREE/logs/batch-${batch}-attempt-$((attempt - 1)).log"
                full_prompt="$prompt

IMPORTANT: Previous attempt failed. Review the quality gate output and fix the issues.
The previous attempt log is available at: $prev_log"
            elif [[ $attempt -ge 3 ]]; then
                local prev_log="$WORKTREE/logs/batch-${batch}-attempt-$((attempt - 1)).log"
                local log_digest=""
                if [[ -f "$prev_log" ]]; then
                    log_digest=$("$SCRIPT_DIR/../failure-digest.sh" "$prev_log" 2>/dev/null || tail -50 "$prev_log" 2>/dev/null || true)
                fi
                full_prompt="$prompt

IMPORTANT: Previous attempts failed ($((attempt - 1)) so far). This is attempt $attempt.
Failure digest from previous attempt:
\`\`\`
$log_digest
\`\`\`
Focus on fixing the root cause. Check test output carefully."
            fi

            # Run claude headless (unset CLAUDECODE to allow nested invocation)
            local claude_exit=0
            CLAUDECODE= claude -p "$full_prompt" \
                --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
                --permission-mode bypassPermissions \
                2>&1 | tee "$log_file" || claude_exit=$?

            if [[ $claude_exit -ne 0 ]]; then
                echo "WARNING: claude exited with code $claude_exit"
            fi

            # Compute duration before quality gate (includes claude time, not gate time)
            local batch_end
            batch_end=$(date +%s)
            local duration_secs="$((batch_end - batch_start))"
            local duration="${duration_secs}s"

            # Run quality gate (passes duration for state tracking)
            local gate_exit=0
            run_quality_gate "$WORKTREE" "$QUALITY_GATE_CMD" "$batch" "$duration_secs" || gate_exit=$?

            if [[ $gate_exit -eq 0 ]]; then
                echo "Batch $batch PASSED (${duration})"
                batch_passed=true

                if [[ "$NOTIFY" == true ]]; then
                    local new_test_count
                    new_test_count=$(get_previous_test_count "$WORKTREE")
                    notify_success "$plan_name" "$batch" "$new_test_count" "$prev_test_count" "$duration" "$MODE" || true
                fi
                break
            else
                echo "Batch $batch FAILED on attempt $attempt (${duration})"

                if [[ "$NOTIFY" == true ]]; then
                    notify_failure "$plan_name" "$batch" "0" "?" "Quality gate failed" "$ON_FAILURE" || true
                fi

                # Handle failure mode
                if [[ "$ON_FAILURE" == "stop" ]]; then
                    echo "STOPPING: --on-failure=stop. Fix issues and use --resume to continue."
                    exit 1
                elif [[ "$ON_FAILURE" == "skip" ]]; then
                    echo "SKIPPING: Batch $batch failed, moving to next batch."
                    break
                elif [[ "$ON_FAILURE" == "retry" ]]; then
                    if [[ $attempt -ge $max_attempts ]]; then
                        echo "EXHAUSTED: All $max_attempts attempts failed for batch $batch."
                        echo "STOPPING: No more retries."
                        exit 1
                    fi
                    echo "RETRYING: Attempt $((attempt + 1)) of $max_attempts..."
                fi
            fi
        done

        if [[ "$batch_passed" != true && "$ON_FAILURE" != "skip" ]]; then
            echo "Batch $batch never passed. Exiting."
            exit 1
        fi
    done

    echo ""
    echo "================================================================"
    echo "  All batches complete ($START_BATCH → $END_BATCH)"
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
