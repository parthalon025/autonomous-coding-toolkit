#!/usr/bin/env bash
# run-plan-headless.sh — Headless batch execution loop for run-plan
#
# Requires globals: WORKTREE, RESUME, START_BATCH, END_BATCH, NOTIFY,
#   PLAN_FILE, QUALITY_GATE_CMD, PYTHON, MAX_RETRIES, ON_FAILURE, VERIFY, MODE
# Requires libs: run-plan-parser, state, quality-gate, notify, prompt, scoring

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

    # Generate AGENTS.md for agent awareness
    generate_agents_md "$PLAN_FILE" "$WORKTREE" "$MODE"

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

        local batch_text
        batch_text=$(get_batch_text "$PLAN_FILE" "$batch")
        if [[ -z "$batch_text" ]]; then
            echo "  (empty batch -- skipping)"
            continue
        fi

        # Generate and inject per-batch context into CLAUDE.md
        # Guard all CLAUDE.md manipulation — failures here must not kill the run
        local batch_context="" _claude_md_existed=false _claude_md_backup=""
        batch_context=$(generate_batch_context "$PLAN_FILE" "$batch" "$WORKTREE" 2>/dev/null || true)
        if [[ -n "$batch_context" ]]; then
            {
                local claude_md="$WORKTREE/CLAUDE.md"
                if [[ -f "$claude_md" ]]; then
                    _claude_md_existed=true
                    _claude_md_backup=$(cat "$claude_md")
                fi
                # Remove previous run-plan context section if present
                if [[ -f "$claude_md" ]] && grep -q "^## Run-Plan:" "$claude_md"; then
                    local tmp
                    tmp=$(mktemp)
                    sed '/^## Run-Plan:/,/^## [^R]/{ /^## [^R]/!d; }' "$claude_md" > "$tmp"
                    sed -i '/^## Run-Plan:/d' "$tmp"
                    mv "$tmp" "$claude_md"
                fi
                # Append new context
                echo "" >> "$claude_md"
                echo "$batch_context" >> "$claude_md"
            } || echo "WARNING: Failed to inject batch context into CLAUDE.md (non-fatal)" >&2
        fi

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

            # Auto-sample on retry if configured
            if [[ "${SAMPLE_ON_RETRY:-false}" == "true" && "${SAMPLE_COUNT:-0}" -eq 0 && $attempt -ge 2 ]]; then
                SAMPLE_COUNT="${SAMPLE_DEFAULT_COUNT:-3}"
                echo "  Auto-enabling sampling ($SAMPLE_COUNT candidates) for retry"
            fi

            # Auto-sample on critical batches
            if [[ "${SAMPLE_ON_CRITICAL:-false}" == "true" && "${SAMPLE_COUNT:-0}" -eq 0 && $attempt -eq 1 ]]; then
                if is_critical_batch "$PLAN_FILE" "$batch"; then
                    SAMPLE_COUNT="${SAMPLE_DEFAULT_COUNT:-3}"
                    echo "  Auto-enabling sampling ($SAMPLE_COUNT candidates) for critical batch"
                fi
            fi

            # Memory guard for sampling
            if [[ "${SAMPLE_COUNT:-0}" -gt 0 ]]; then
                local avail_gb
                avail_gb=$(free -g 2>/dev/null | awk '/Mem:/{print $7}' || echo "0")
                local needed=$((SAMPLE_COUNT * ${SAMPLE_MIN_MEMORY_PER_GB:-4}))
                if [[ "$avail_gb" -lt "$needed" ]]; then
                    echo "  WARNING: Not enough memory for sampling (${avail_gb}G < ${needed}G needed). Falling back to single attempt."
                    SAMPLE_COUNT=0
                fi
            fi

            # If sampling enabled and this is a retry, use parallel candidates
            if [[ "${SAMPLE_COUNT:-0}" -gt 0 && $attempt -ge 2 ]]; then
                echo "  Sampling $SAMPLE_COUNT candidates for batch $batch..."
                local scores=""
                local candidate_logs=()

                # Save current state so we can reset between candidates
                (cd "$WORKTREE" && git stash -q 2>/dev/null || true)

                # Classify batch and get type-aware prompt variants
                local batch_type
                batch_type=$(classify_batch_type "$PLAN_FILE" "$batch")
                local variants
                variants=$(get_prompt_variants "$batch_type" "$WORKTREE/logs/sampling-outcomes.json" "$SAMPLE_COUNT")

                local c=0
                while IFS= read -r variant_name; do
                    local variant_suffix=""
                    if [[ "$variant_name" != "vanilla" ]]; then
                        variant_suffix=$'\nIMPORTANT: '"$variant_name"
                    fi

                    local candidate_log="$WORKTREE/logs/batch-${batch}-candidate-${c}.log"
                    candidate_logs+=("$candidate_log")

                    # Restore clean state for each candidate
                    (cd "$WORKTREE" && git checkout . 2>/dev/null && git stash pop -q 2>/dev/null || true)
                    (cd "$WORKTREE" && git stash -q 2>/dev/null || true)

                    CLAUDECODE='' claude -p "${prompt}${variant_suffix}" \
                        --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
                        --permission-mode bypassPermissions \
                        > "$candidate_log" 2>&1 || true

                    # Score this candidate
                    local gate_exit=0
                    run_quality_gate "$WORKTREE" "$QUALITY_GATE_CMD" "sample-$c" "0" || gate_exit=$?
                    local gate_passed=0
                    [[ $gate_exit -eq 0 ]] && gate_passed=1

                    local new_tests
                    new_tests=$(get_previous_test_count "$WORKTREE")
                    local diff_size
                    diff_size=$(cd "$WORKTREE" && git diff --stat HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1 || echo "100")

                    local score
                    score=$(score_candidate "$gate_passed" "${new_tests:-0}" "${diff_size:-100}" "0" "0" "0")
                    scores+="$score "

                    echo "  Candidate $c: score=$score (gate=$gate_passed, tests=${new_tests:-0})"

                    # If gate failed, reset for next candidate
                    if [[ $gate_passed -eq 0 ]]; then
                        (cd "$WORKTREE" && git checkout . 2>/dev/null || true)
                    else
                        # Stash the winning state so we can restore it
                        (cd "$WORKTREE" && git stash -q 2>/dev/null || true)
                    fi
                    c=$((c + 1))
                done <<< "$variants"

                # Pick winner
                local winner
                winner=$(select_winner "$scores")
                if [[ "$winner" -ge 0 ]]; then
                    echo "  Winner: candidate $winner (scores: $scores)"

                    # Restore winner's stashed state
                    (cd "$WORKTREE" && git stash pop -q 2>/dev/null || true)

                    # Log sampling outcome
                    local outcomes_file="$WORKTREE/logs/sampling-outcomes.json"
                    mkdir -p "$(dirname "$outcomes_file")"
                    [[ ! -f "$outcomes_file" ]] && echo "[]" > "$outcomes_file"

                    # Get the winning variant name from the variants list
                    local winning_variant
                    winning_variant=$(echo "$variants" | sed -n "$((winner + 1))p")
                    winning_variant="${winning_variant:-vanilla}"

                    jq --arg bt "$batch_type" --arg vn "$winning_variant" --arg sc "$(echo "$scores" | awk '{print $1}')" \
                        '. += [{"batch_type": $bt, "prompt_variant": $vn, "won": true, "score": ($sc | tonumber), "timestamp": now | tostring}]' \
                        "$outcomes_file" > "$outcomes_file.tmp" && mv "$outcomes_file.tmp" "$outcomes_file" || true

                    batch_passed=true
                    break
                else
                    echo "  No candidate passed quality gate"
                    # Restore clean state
                    (cd "$WORKTREE" && git stash pop -q 2>/dev/null || true)
                fi

                continue  # Skip normal retry path below
            fi

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
            CLAUDECODE='' claude -p "$full_prompt" \
                --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
                --permission-mode bypassPermissions \
                2>&1 | tee "$log_file" || claude_exit=$?

            if [[ $claude_exit -ne 0 ]]; then
                echo "WARNING: claude exited with code $claude_exit"
            fi

            # Restore CLAUDE.md to match HEAD (prevent git-clean failure)
            # The claude subprocess may have committed CLAUDE.md with injected context,
            # so restoring from backup creates a diff vs HEAD. Use git checkout instead.
            if [[ -n "$batch_context" ]]; then
                {
                    git -C "$WORKTREE" checkout -- CLAUDE.md 2>/dev/null
                } || echo "WARNING: Failed to restore CLAUDE.md (non-fatal)" >&2
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
                    {
                        local new_test_count
                        new_test_count=$(get_previous_test_count "$WORKTREE")
                        # Build summary from git log (commits in this batch)
                        local batch_summary=""
                        batch_summary=$(cd "$WORKTREE" && git log --oneline -5 2>/dev/null | head -3 | sed 's/^[a-f0-9]* /• /' | tr '\n' '; ' | sed 's/; $//') || true
                        notify_success "$plan_name" "$batch" "$END_BATCH" "$title" "$new_test_count" "$prev_test_count" "$duration" "$MODE" "$batch_summary"
                    } || echo "WARNING: Telegram notification failed (non-fatal)" >&2
                fi
                break
            else
                echo "Batch $batch FAILED on attempt $attempt (${duration})"

                if [[ "$NOTIFY" == true ]]; then
                    notify_failure "$plan_name" "$batch" "$END_BATCH" "$title" "0" "?" "Quality gate failed" "$ON_FAILURE" || echo "WARNING: Telegram notification failed (non-fatal)" >&2
                fi

                # Record failure pattern for cross-run learning
                {
                    local fail_type="quality gate failure"
                    if [[ -f "$log_file" ]]; then
                        fail_type=$(grep -oE "(FAIL|ERROR|FAILED).*" "$log_file" | head -1 | cut -c1-80 || echo "quality gate failure")
                        [[ -z "$fail_type" ]] && fail_type="quality gate failure"
                    fi
                    record_failure_pattern "$WORKTREE" "$title" "$fail_type" ""
                } || echo "WARNING: Failed to record failure pattern (non-fatal)" >&2

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
