#!/usr/bin/env bash
# run-plan-headless.sh — Headless batch execution loop for run-plan
#
# Requires globals: WORKTREE, RESUME, START_BATCH, END_BATCH, NOTIFY,
#   PLAN_FILE, QUALITY_GATE_CMD, PYTHON, MAX_RETRIES, ON_FAILURE, VERIFY, MODE,
#   SKIP_ECHO_BACK, STRICT_ECHO_BACK
# Requires libs: run-plan-parser, state, quality-gate, notify, prompt, scoring
#
# Echo-back gate behavior (--strict-echo-back / --skip-echo-back):
#   Default: NON-BLOCKING — prints a WARNING if agent echo-back looks wrong, then continues.
#   --skip-echo-back: disables the echo-back check entirely (no prompt, no warning).
#   --strict-echo-back: makes the echo-back check BLOCKING — returns 1 on mismatch, aborting the batch.

# Echo-back gate: ask agent to restate the batch intent, check for gross misalignment.
# Behavior controlled by SKIP_ECHO_BACK and STRICT_ECHO_BACK globals.
# Non-blocking by default (warns only). --strict-echo-back makes it blocking.
# Args: <batch_text> <log_file>
# Returns: 0 always (non-blocking default), or 1 on mismatch with --strict-echo-back
_echo_back_check() {
    local batch_text="$1"
    local log_file="$2"

    # --skip-echo-back: disabled entirely
    if [[ "${SKIP_ECHO_BACK:-false}" == "true" ]]; then
        return 0
    fi

    # Log file must exist to read agent output
    if [[ ! -f "$log_file" ]]; then
        return 0
    fi

    # Extract first paragraph of batch_text as the expected intent keywords
    local expected_keywords
    expected_keywords=$(echo "$batch_text" | head -5 | grep -oE '\b[A-Za-z]{4,}\b' | sort -u | head -10 | tr '\n' '|' | sed 's/|$//' || true)

    if [[ -z "$expected_keywords" ]]; then
        return 0
    fi

    # Check if log output contains any of the expected keywords (basic alignment check)
    local found_any=false
    local keyword
    while IFS= read -r keyword; do
        [[ -z "$keyword" ]] && continue
        if grep -qi "$keyword" "$log_file" 2>/dev/null; then
            found_any=true
            break
        fi
    done <<< "$(echo "$expected_keywords" | tr '|' '\n')"

    if [[ "$found_any" == "false" ]]; then
        echo "WARNING: Echo-back check: agent output may not address the batch intent (keywords not found: $expected_keywords)" >&2
        # --strict-echo-back: blocking — return 1 to abort batch
        if [[ "${STRICT_ECHO_BACK:-false}" == "true" ]]; then
            echo "ERROR: --strict-echo-back is set. Aborting batch due to spec misalignment." >&2
            return 1
        fi
        # Default: non-blocking, proceeding anyway
    fi

    return 0
}

# echo_back_check — Verify agent understands the batch spec before execution
# Args: <batch_text> <log_dir> <batch_num> [claude_cmd]
# Returns: 0 if restatement matches spec, 1 if mismatch after retry
# The optional claude_cmd parameter allows test injection of a mock.
echo_back_check() {
    local batch_text="$1"
    local log_dir="$2"
    local batch_num="$3"
    local claude_cmd="${4:-claude}"

    local echo_prompt restatement verify_prompt verdict
    local echo_log="$log_dir/batch-${batch_num}-echo-back.log"

    # Step 1: Ask the agent to restate the batch spec
    echo_prompt="Before implementing, restate in one paragraph what this batch must accomplish. Do not write any code. Just describe the goal and key deliverables.

The batch specification is:
${batch_text}"

    local claude_exit=0
    restatement=$(CLAUDECODE='' "$claude_cmd" -p "$echo_prompt" \
        --allowedTools "" \
        --permission-mode bypassPermissions \
        2>"$echo_log") || claude_exit=$?

    if [[ $claude_exit -ne 0 ]]; then
        echo "  Echo-back: claude failed (exit $claude_exit) — see $echo_log" >&2
        return 0
    fi

    if [[ -z "$restatement" ]]; then
        echo "  Echo-back: no restatement received (skipping check)" >&2
        return 0
    fi

    # Extract first paragraph (up to first blank line)
    restatement=$(echo "$restatement" | awk '/^$/{exit} {print}')

    # Step 2: Lightweight comparison via haiku
    verify_prompt="Compare these two texts. Does the RESTATEMENT accurately capture the key goals of the ORIGINAL SPEC? Answer YES or NO followed by a brief reason.

ORIGINAL SPEC:
${batch_text}

RESTATEMENT:
${restatement}"

    verdict=$(CLAUDECODE='' "$claude_cmd" -p "$verify_prompt" \
        --model haiku \
        --allowedTools "" \
        --permission-mode bypassPermissions \
        2>>"$echo_log") || true

    if echo "$verdict" | grep -qi "YES"; then
        echo "  Echo-back: PASSED (spec understood)"
        return 0
    fi

    # Step 3: Retry once with clarified prompt
    echo "  Echo-back: MISMATCH — retrying with clarified prompt" >&2
    local reason
    reason=$(echo "$verdict" | head -2)

    local retry_prompt="Your previous restatement did not match the spec. The reviewer said: ${reason}

Re-read the specification carefully and restate in one paragraph what this batch must accomplish:
${batch_text}"

    local retry_restatement
    retry_restatement=$(CLAUDECODE='' "$claude_cmd" -p "$retry_prompt" \
        --allowedTools "" \
        --permission-mode bypassPermissions \
        2>>"$echo_log") || true

    retry_restatement=$(echo "$retry_restatement" | awk '/^$/{exit} {print}')

    local retry_verify="Compare these two texts. Does the RESTATEMENT accurately capture the key goals of the ORIGINAL SPEC? Answer YES or NO followed by a brief reason.

ORIGINAL SPEC:
${batch_text}

RESTATEMENT:
${retry_restatement}"

    local retry_verdict
    retry_verdict=$(CLAUDECODE='' "$claude_cmd" -p "$retry_verify" \
        --model haiku \
        --allowedTools "" \
        --permission-mode bypassPermissions \
        2>>"$echo_log") || true

    if echo "$retry_verdict" | grep -qi "YES"; then
        echo "  Echo-back: PASSED on retry (spec understood)"
        return 0
    fi

    echo "  Echo-back: FAILED after retry (spec not understood)" >&2
    return 1
}

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

    # Build the stable prefix ONCE before the batch loop and cache it to disk.
    # The stable prefix contains plan identity, worktree path, python, branch, and TDD rules —
    # none of which change between batches. prev_test_count is intentionally excluded because
    # it increases after each batch; it lives in the variable suffix (#48).
    #
    # #45: Check that the write succeeded. A silent failure here would leave all subsequent
    # batches with a missing/stale prefix file — fail fast instead.
    local stable_prefix
    stable_prefix=$(build_stable_prefix "$PLAN_FILE" "$WORKTREE" "$PYTHON" "$QUALITY_GATE_CMD")
    echo "$stable_prefix" > "$WORKTREE/.run-plan-prefix.txt" || {
        echo "ERROR: Failed to write prefix file $WORKTREE/.run-plan-prefix.txt" >&2
        exit 1
    }

    # Preserve user's --sample value before batch loop so per-batch reset doesn't clobber it (#16/#28)
    local SAMPLE_DEFAULT=${SAMPLE_COUNT:-0}

    for ((batch = START_BATCH; batch <= END_BATCH; batch++)); do
        # Reset sampling count each batch — prevents leak from prior batch's retry/critical trigger (#16/#28)
        SAMPLE_COUNT=$SAMPLE_DEFAULT

        # Budget enforcement
        if [[ -n "${MAX_BUDGET:-}" ]]; then
            if ! check_budget "$WORKTREE" "$MAX_BUDGET"; then
                echo "STOPPING: Budget limit reached (\$${MAX_BUDGET})"
                exit 1
            fi
        fi

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

        # Declare batch_passed before MAB routing — the MAB `continue` path
        # skips the retry loop where it was originally declared (#4A review).
        local batch_passed=false

        # MAB routing (when --mab flag set)
        if [[ "${MAB:-false}" == "true" ]]; then
            local batch_type_for_route
            batch_type_for_route=$(classify_batch_type "$PLAN_FILE" "$batch")
            local perf_file="$WORKTREE/logs/strategy-perf.json"
            [[ ! -f "$perf_file" ]] && init_strategy_perf "$perf_file"

            local mab_route
            mab_route=$(thompson_route "$batch_type_for_route" "$perf_file")
            echo "  [MAB] type=$batch_type_for_route → route=$mab_route"

            if [[ "$mab_route" == "mab" ]]; then
                local mab_exit=0
                "$SCRIPT_DIR/../mab-run.sh" \
                    --plan "$PLAN_FILE" --batch "$batch" \
                    --work-unit "$title" --worktree "$WORKTREE" \
                    --quality-gate "$QUALITY_GATE_CMD" || mab_exit=$?

                if [[ $mab_exit -eq 0 ]]; then
                    local new_tc; new_tc=$(get_previous_test_count "$WORKTREE")
                    complete_batch "$WORKTREE" "$batch" "$new_tc"
                    batch_passed=true
                else
                    echo "MAB batch $batch failed (exit $mab_exit)"
                fi
                # Skip normal headless execution — jump to batch_passed check
                continue
            fi
        fi

        # Write batch header to progress.txt at the start of each batch (#53)
        # Non-fatal: progress tracking failure must not kill the run
        if type write_batch_progress &>/dev/null; then
            write_batch_progress "$WORKTREE" "$batch" "$title" || \
                echo "WARNING: Failed to write batch progress header (non-fatal)" >&2
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
                # Remove previous run-plan context section if present.
                # awk approach avoids the sed range-deletion bug (#4): if
                # "## Run-Plan:" is the LAST section in CLAUDE.md, the sed
                # pattern '/^## Run-Plan:/,/^## [^R]/' has no closing anchor
                # and deletes from Run-Plan to EOF — eating the entire file.
                # awk prints everything before the Run-Plan section, skips
                # lines until the next ## header (or EOF), then resumes.
                if [[ -f "$claude_md" ]] && grep -q "^## Run-Plan:" "$claude_md"; then
                    local tmp
                    tmp=$(mktemp)
                    awk '
                        /^## Run-Plan:/ { in_section=1; next }
                        in_section && /^## / { in_section=0 }
                        !in_section { print }
                    ' "$claude_md" > "$tmp"
                    mv "$tmp" "$claude_md"
                fi
                # Append new context
                echo "" >> "$claude_md"
                echo "$batch_context" >> "$claude_md"
            } || echo "WARNING: Failed to inject batch context into CLAUDE.md (non-fatal)" >&2
        fi

        # Fetch the current test count INSIDE the loop — it increases after each batch.
        # Combine the cached stable prefix with the per-batch variable suffix so the
        # prompt always reflects the actual current test count (#48).
        local prev_test_count
        prev_test_count=$(get_previous_test_count "$WORKTREE")

        local prompt
        prompt=$(printf '%s\n\n%s\n' \
            "$(build_variable_suffix "$PLAN_FILE" "$batch" "$WORKTREE" "$prev_test_count")" \
            "$stable_prefix")

        # Spec echo-back gate: verify agent understands the batch before executing
        if [[ "${SKIP_ECHO_BACK:-false}" != "true" ]]; then
            if ! echo_back_check "$batch_text" "$WORKTREE/logs" "$batch"; then
                echo "WARNING: Echo-back check failed for batch $batch (proceeding anyway)" >&2
            fi
        fi

        local max_attempts=$((MAX_RETRIES + 1))
        local attempt=0

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
                local avail_mb
                avail_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $7}')
                if [[ -z "$avail_mb" ]]; then
                    echo "  WARNING: Cannot determine available memory. Falling back to single attempt."
                    SAMPLE_COUNT=0
                else
                    local needed_mb=$(( SAMPLE_COUNT * ${SAMPLE_MIN_MEMORY_PER_GB:-4} * 1024 ))
                    if [[ "$avail_mb" -lt "$needed_mb" ]]; then
                        local avail_display needed_display
                        avail_display=$(awk "BEGIN {printf \"%.1f\", $avail_mb / 1024}")
                        needed_display=$(( SAMPLE_COUNT * ${SAMPLE_MIN_MEMORY_PER_GB:-4} ))
                        echo "  WARNING: Not enough memory for sampling (${avail_display}G < ${needed_display}G needed). Falling back to single attempt."
                        SAMPLE_COUNT=0
                    fi
                fi
            fi

            # If sampling enabled and this is a retry, use parallel candidates
            if [[ "${SAMPLE_COUNT:-0}" -gt 0 && $attempt -ge 2 ]]; then
                echo "  Sampling $SAMPLE_COUNT candidates for batch $batch..."
                local scores=""
                local candidate_logs=()

                # Save baseline state using a patch file rather than git stash.
                # This avoids LIFO ordering issues when multiple stash/pop cycles
                # interact: stash.pop always restores the top entry, so interleaved
                # stash calls across candidates can restore the wrong state (#2).
                # Using patch files gives explicit, named state snapshots instead.
                local _baseline_patch="/tmp/run-plan-baseline-${batch}-$$.diff"
                (cd "$WORKTREE" && git diff > "$_baseline_patch" 2>/dev/null || true)

                # Classify batch and get type-aware prompt variants
                local batch_type
                batch_type=$(classify_batch_type "$PLAN_FILE" "$batch")
                local variants
                variants=$(get_prompt_variants "$batch_type" "$WORKTREE/logs/sampling-outcomes.json" "$SAMPLE_COUNT")

                local c=0
                local _winner_patch=""
                while IFS= read -r variant_name; do
                    local variant_suffix=""
                    if [[ "$variant_name" != "vanilla" ]]; then
                        variant_suffix=$'\nIMPORTANT: '"$variant_name"
                    fi

                    local candidate_log="$WORKTREE/logs/batch-${batch}-candidate-${c}.log"
                    candidate_logs+=("$candidate_log")

                    # Restore clean baseline for each candidate using the saved patch.
                    # Reset tracked changes first, then re-apply the baseline diff.
                    (cd "$WORKTREE" && git checkout . 2>/dev/null || true)
                    if [[ -s "$_baseline_patch" ]]; then
                        if ! (cd "$WORKTREE" && git apply "$_baseline_patch" 2>/dev/null); then
                            echo "  WARNING: Failed to restore baseline patch for candidate $c — starting from clean state" >&2
                        fi
                    fi

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

                    # Save winning candidate's state as a patch file for later restore.
                    # Only the last passing candidate's patch is kept as the winner
                    # (select_winner picks the highest score, which is last-wins on tie).
                    if [[ $gate_passed -eq 1 ]]; then
                        _winner_patch="/tmp/run-plan-winner-${batch}-${c}-$$.diff"
                        (cd "$WORKTREE" && git diff > "$_winner_patch" 2>/dev/null || true)
                    fi

                    # Reset worktree for next candidate iteration
                    (cd "$WORKTREE" && git checkout . 2>/dev/null || true)

                    c=$((c + 1))
                done <<< "$variants"

                # Pick winner
                local winner
                winner=$(select_winner "$scores")
                if [[ "$winner" -ge 0 ]]; then
                    echo "  Winner: candidate $winner (scores: $scores)"

                    # Restore winner's patch — explicit named file, no LIFO ordering risk
                    local _apply_patch="/tmp/run-plan-winner-${batch}-${winner}-$$.diff"
                    if [[ -s "$_apply_patch" ]]; then
                        if ! (cd "$WORKTREE" && git apply "$_apply_patch"); then
                            echo "  ERROR: Failed to apply winning candidate $winner patch — sampling result lost" >&2
                            # Don't break — fall through to normal retry path
                            batch_passed=false
                        fi
                    fi

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
                    # Restore baseline state for the normal retry path
                    if [[ -s "$_baseline_patch" ]]; then
                        if ! (cd "$WORKTREE" && git apply "$_baseline_patch" 2>/dev/null); then
                            echo "  WARNING: Failed to restore baseline after sampling — continuing from clean state" >&2
                        fi
                    fi
                fi

                # Clean up temp patch files
                rm -f "$_baseline_patch" /tmp/run-plan-winner-${batch}-*-$$.diff 2>/dev/null || true

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
            # Use --output-format json to capture session_id for cost tracking
            # NOTE: this sacrifices real-time streaming — if streaming is needed,
            # remove --output-format json and use tee instead (#38).
            local claude_exit=0
            local claude_json_output=""
            claude_json_output=$(CLAUDECODE='' claude -p "$full_prompt" \
                --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
                --permission-mode bypassPermissions \
                --output-format json \
                2>"$log_file.stderr") || claude_exit=$?

            # Extract session_id and result from JSON output
            local batch_session_id=""
            if [[ -n "$claude_json_output" ]]; then
                batch_session_id=$(echo "$claude_json_output" | jq -r '.session_id // empty' 2>/dev/null || true)
                # Write result text to log file (was previously done by tee)
                echo "$claude_json_output" | jq -r '.result // empty' 2>/dev/null > "$log_file" || true
                # Append stderr to log
                cat "$log_file.stderr" >> "$log_file" 2>/dev/null || true
            fi
            rm -f "$log_file.stderr"

            if [[ $claude_exit -ne 0 ]]; then
                echo "WARNING: claude exited with code $claude_exit"
            fi

            # Diagnostic: if log file is empty or missing, claude likely crashed with no output (#38)
            if [[ ! -s "$log_file" ]]; then
                echo "WARNING: claude produced no output (log file empty or missing). Claude may have crashed." >&2
                echo "  Log path: $log_file" >&2
                echo "  Exit code: $claude_exit" >&2
                echo "[run-plan] claude produced no output for batch $batch attempt $attempt (exit=$claude_exit)" >> "$log_file"
            fi

            # Echo-back gate: check agent output reflects batch intent (#30)
            # NON-BLOCKING by default; use --strict-echo-back to make it blocking.
            _echo_back_check "$batch_text" "$log_file" || {
                if [[ "${STRICT_ECHO_BACK:-false}" == "true" ]]; then
                    echo "Batch $batch FAILED on attempt $attempt: echo-back gate (strict mode)"
                    # Fall through to quality gate failure handling
                fi
            }

            # Restore CLAUDE.md after context injection (prevent git-clean failure)
            # Try git checkout first (works when CLAUDE.md is tracked).
            # Fallback: if file didn't exist before injection, remove it;
            # if it did exist, restore from backup.
            if [[ -n "$batch_context" ]]; then
                {
                    git -C "$WORKTREE" checkout -- CLAUDE.md 2>/dev/null
                } || {
                    if [[ "$_claude_md_existed" == false ]]; then
                        rm -f "$WORKTREE/CLAUDE.md"
                    elif [[ -n "$_claude_md_backup" ]]; then
                        printf '%s\n' "$_claude_md_backup" > "$WORKTREE/CLAUDE.md"
                    fi
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

                # Record cost for this batch
                if [[ -n "${batch_session_id:-}" ]]; then
                    record_batch_cost "$WORKTREE" "$batch" "$batch_session_id" || \
                        echo "WARNING: Failed to record batch cost (non-fatal)" >&2
                fi

                # Append State section to progress.txt after quality gate passes (#53)
                # Records test count, duration, and cost for cross-context memory.
                if type append_progress_section &>/dev/null; then
                    {
                        local _state_test_count
                        _state_test_count=$(get_previous_test_count "$WORKTREE" 2>/dev/null || echo "0")
                        local _state_cost=""
                        _state_cost=$(jq -r ".costs[\"$batch\"].estimated_cost_usd // empty" "$WORKTREE/.run-plan-state.json" 2>/dev/null || true)
                        local _state_content="- Tests: ${_state_test_count} passing"$'\n'"- Duration: ${duration}"
                        [[ -n "$_state_cost" ]] && _state_content+=$'\n'"- Cost: \$${_state_cost}"
                        append_progress_section "$WORKTREE" "State" "$_state_content"
                    } || echo "WARNING: Failed to append progress State section (non-fatal)" >&2
                fi

                if [[ "$NOTIFY" == true ]]; then
                    {
                        local new_test_count
                        new_test_count=$(get_previous_test_count "$WORKTREE")
                        # Build summary from git log (commits in this batch)
                        local batch_summary=""
                        batch_summary=$(cd "$WORKTREE" && git log --oneline -5 2>/dev/null | head -3 | sed 's/^[a-f0-9]* /• /' | tr '\n' '; ' | sed 's/; $//') || true
                        local batch_cost=""
                        batch_cost=$(jq -r ".costs[\"$batch\"].estimated_cost_usd // empty" "$WORKTREE/.run-plan-state.json" 2>/dev/null || true)
                        notify_success "$plan_name" "$batch" "$END_BATCH" "$title" "$new_test_count" "$prev_test_count" "$duration" "$MODE" "$batch_summary" "$batch_cost"
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
