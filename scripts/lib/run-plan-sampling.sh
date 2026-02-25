#!/usr/bin/env bash
# run-plan-sampling.sh — Parallel candidate sampling for batch execution
#
# Standalone module: spawns N parallel candidates with prompt variants,
# scores each via quality gate, picks the winner. Uses patch files (not stash)
# to manage worktree state across candidates.
#
# Functions:
#   check_memory_for_sampling
#     Returns 0 if enough memory for SAMPLE_COUNT candidates, 1 otherwise.
#   run_sampling_candidates <worktree> <plan_file> <batch> <prompt> <quality_gate_cmd>
#     Spawns SAMPLE_COUNT candidates, scores them, applies winner's patch.
#     Returns 0 if winner found, 1 if no candidate passed.
#
# Globals (read-only): SAMPLE_COUNT, SAMPLE_MIN_MEMORY_PER_GB
# Requires libs: run-plan-scoring (score_candidate, select_winner, classify_batch_type, get_prompt_variants)
#                run-plan-quality-gate (run_quality_gate)
#                run-plan-state (get_previous_test_count)

check_memory_for_sampling() {
    local avail_mb
    avail_mb=$(free -m 2>/dev/null | awk '/Mem:/{print $7}')
    if [[ -z "$avail_mb" ]]; then
        echo "  WARNING: Cannot determine available memory. Falling back to single attempt."
        SAMPLE_COUNT=0
        return 1
    fi

    local needed_mb=$(( SAMPLE_COUNT * ${SAMPLE_MIN_MEMORY_PER_GB:-4} * 1024 ))
    if [[ "$avail_mb" -lt "$needed_mb" ]]; then
        local avail_display needed_display
        avail_display=$(awk "BEGIN {printf \"%.1f\", $avail_mb / 1024}")
        needed_display=$(( SAMPLE_COUNT * ${SAMPLE_MIN_MEMORY_PER_GB:-4} ))
        echo "  WARNING: Not enough memory for sampling (${avail_display}G < ${needed_display}G needed). Falling back to single attempt."
        SAMPLE_COUNT=0
        return 1
    fi
    return 0
}

run_sampling_candidates() {
    local worktree="$1"
    local plan_file="$2"
    local batch="$3"
    local prompt="$4"
    local quality_gate_cmd="$5"

    echo "  Sampling $SAMPLE_COUNT candidates for batch $batch..."
    local scores=""
    local candidate_logs=()

    # Save baseline state using a patch file rather than git stash.
    # This avoids LIFO ordering issues when multiple stash/pop cycles
    # interact: stash.pop always restores the top entry, so interleaved
    # stash calls across candidates can restore the wrong state (#2).
    # Using patch files gives explicit, named state snapshots instead.
    local _baseline_patch="/tmp/run-plan-baseline-${batch}-$$.diff"
    (cd "$worktree" && git diff > "$_baseline_patch" 2>/dev/null || true)

    # Classify batch and get type-aware prompt variants
    local batch_type
    batch_type=$(classify_batch_type "$plan_file" "$batch")
    local variants
    variants=$(get_prompt_variants "$batch_type" "$worktree/logs/sampling-outcomes.json" "$SAMPLE_COUNT")

    local c=0
    local _winner_patch=""
    while IFS= read -r variant_name; do
        local variant_suffix=""
        if [[ "$variant_name" != "vanilla" ]]; then
            variant_suffix=$'\nIMPORTANT: '"$variant_name"
        fi

        local candidate_log="$worktree/logs/batch-${batch}-candidate-${c}.log"
        candidate_logs+=("$candidate_log")

        # Restore clean baseline for each candidate using the saved patch.
        # Reset tracked changes first, then re-apply the baseline diff.
        (cd "$worktree" && git checkout . 2>/dev/null || true)
        if [[ -s "$_baseline_patch" ]]; then
            if ! (cd "$worktree" && git apply "$_baseline_patch" 2>/dev/null); then
                echo "  WARNING: Failed to restore baseline patch for candidate $c — starting from clean state" >&2
            fi
        fi

        CLAUDECODE='' claude -p "${prompt}${variant_suffix}" \
            --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
            --permission-mode bypassPermissions \
            > "$candidate_log" 2>&1 || true

        # Score this candidate
        local gate_exit=0
        run_quality_gate "$worktree" "$quality_gate_cmd" "sample-$c" "0" || gate_exit=$?
        local gate_passed=0
        [[ $gate_exit -eq 0 ]] && gate_passed=1

        local new_tests
        new_tests=$(get_previous_test_count "$worktree")
        local diff_size
        diff_size=$(cd "$worktree" && git diff --stat HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1 || echo "100")

        local score
        score=$(score_candidate "$gate_passed" "${new_tests:-0}" "${diff_size:-100}" "0" "0" "0")
        scores+="$score "

        echo "  Candidate $c: score=$score (gate=$gate_passed, tests=${new_tests:-0})"

        # Save winning candidate's state as a patch file for later restore.
        # Only the last passing candidate's patch is kept as the winner
        # (select_winner picks the highest score, which is last-wins on tie).
        if [[ $gate_passed -eq 1 ]]; then
            _winner_patch="/tmp/run-plan-winner-${batch}-${c}-$$.diff"
            (cd "$worktree" && git diff > "$_winner_patch" 2>/dev/null || true)
        fi

        # Reset worktree for next candidate iteration
        (cd "$worktree" && git checkout . 2>/dev/null || true)

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
            if ! (cd "$worktree" && git apply "$_apply_patch"); then
                echo "  ERROR: Failed to apply winning candidate $winner patch — sampling result lost" >&2
                # Clean up temp patch files
                rm -f "$_baseline_patch" /tmp/run-plan-winner-${batch}-*-$$.diff 2>/dev/null || true
                return 1
            fi
        fi

        # Log sampling outcome
        local outcomes_file="$worktree/logs/sampling-outcomes.json"
        mkdir -p "$(dirname "$outcomes_file")"
        [[ ! -f "$outcomes_file" ]] && echo "[]" > "$outcomes_file"

        # Get the winning variant name from the variants list
        local winning_variant
        winning_variant=$(echo "$variants" | sed -n "$((winner + 1))p")
        winning_variant="${winning_variant:-vanilla}"

        jq --arg bt "$batch_type" --arg vn "$winning_variant" --arg sc "$(echo "$scores" | awk '{print $1}')" \
            '. += [{"batch_type": $bt, "prompt_variant": $vn, "won": true, "score": ($sc | tonumber), "timestamp": now | tostring}]' \
            "$outcomes_file" > "$outcomes_file.tmp" && mv "$outcomes_file.tmp" "$outcomes_file" || true

        # Clean up temp patch files
        rm -f "$_baseline_patch" /tmp/run-plan-winner-${batch}-*-$$.diff 2>/dev/null || true
        return 0
    else
        echo "  No candidate passed quality gate"
        # Restore baseline state for the normal retry path
        if [[ -s "$_baseline_patch" ]]; then
            if ! (cd "$worktree" && git apply "$_baseline_patch" 2>/dev/null); then
                echo "  WARNING: Failed to restore baseline after sampling — continuing from clean state" >&2
            fi
        fi
    fi

    # Clean up temp patch files
    rm -f "$_baseline_patch" /tmp/run-plan-winner-${batch}-*-$$.diff 2>/dev/null || true

    return 1
}
