#!/usr/bin/env bash
# run-plan-echo-back.sh — Spec echo-back gate for verifying agent understanding
#
# Standalone module: can be sourced by any execution mode (headless, team, ralph).
# No dependencies on batch loop state — only reads SKIP_ECHO_BACK and STRICT_ECHO_BACK globals.
#
# Functions:
#   _echo_back_check <batch_text> <log_file>
#     Lightweight keyword-match gate on agent output. Non-blocking by default.
#   echo_back_check <batch_text> <log_dir> <batch_num> [claude_cmd]
#     Full spec verification: agent restatement → haiku verdict → retry once.
#
# Globals (read-only): SKIP_ECHO_BACK, STRICT_ECHO_BACK
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
