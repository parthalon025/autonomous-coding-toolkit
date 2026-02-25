# Design: Headless Module Split

**Date:** 2026-02-24
**Status:** Approved
**Problem:** `scripts/lib/run-plan-headless.sh` is 681 lines (project limit: 300). Three concerns mixed in one file: echo-back gate, sampling candidates, and batch orchestration.
**Approach:** Extract two new lib modules. Fix issue #73 (MAB path resolution).

## Extraction 1: Echo-Back Gate

### New file: `scripts/lib/run-plan-echo-back.sh`

**Functions moved (verbatim):**
- `_echo_back_check()` — lightweight keyword-match gate on agent output (lines 19-63)
- `echo_back_check()` — full spec verification: agent restatement → haiku verdict → retry once (lines 65-163)

**Globals (read-only):** `SKIP_ECHO_BACK`, `STRICT_ECHO_BACK`

**Interface:** No signature changes. Functions called by name from `run_mode_headless()`.

**Source order in `run-plan.sh`:** Add before headless source line:
```bash
source "$SCRIPT_DIR/lib/run-plan-echo-back.sh"
```

**Test changes:**
- `test-echo-back.sh`: Change source from `run-plan-headless.sh` to `run-plan-echo-back.sh`
- `test-run-plan-headless.sh`: 5 tests for `_echo_back_check()` move to `test-echo-back.sh` (or source both modules)

**Reuse opportunity:** `run-plan-team.sh` can source this module to add spec verification before team batch groups — implements lesson #61 across execution modes.

## Extraction 2: Sampling Candidates

### New file: `scripts/lib/run-plan-sampling.sh`

**New function wrapping extracted code:**
```bash
# run_sampling_candidates <worktree> <plan_file> <batch> <prompt> <quality_gate_cmd>
# Returns: 0 if winner found (worktree has winner's changes), 1 if no candidate passed
# Side-effects: writes logs/sampling-outcomes.json, uses patch files in /tmp/
run_sampling_candidates() { ... }
```

**Code moved:** Lines 373-494 of current `run_mode_headless()` (the sampling block inside the retry while-loop).

**Also extracted:**
- `check_memory_for_sampling()` — memory guard logic (current lines 354-369), reusable by any mode

**Globals (read-only):** `SAMPLE_COUNT`, `SAMPLE_ON_RETRY`, `SAMPLE_ON_CRITICAL`, `SAMPLE_DEFAULT_COUNT`, `SAMPLE_MIN_MEMORY_PER_GB`

**Call site in headless:** Replace inline sampling block with:
```bash
if [[ "${SAMPLE_COUNT:-0}" -gt 0 && $attempt -ge 2 ]]; then
    check_memory_for_sampling || SAMPLE_COUNT=0
    if [[ "${SAMPLE_COUNT:-0}" -gt 0 ]]; then
        if run_sampling_candidates "$WORKTREE" "$PLAN_FILE" "$batch" "$prompt" "$QUALITY_GATE_CMD"; then
            batch_passed=true
            break
        fi
        continue
    fi
fi
```

**Source order in `run-plan.sh`:** Add before headless:
```bash
source "$SCRIPT_DIR/lib/run-plan-sampling.sh"
```

**Dependencies:** Requires `run-plan-scoring.sh` (for `score_candidate`, `select_winner`, `classify_batch_type`, `get_prompt_variants`).

## Bug Fix: Issue #73

**File:** `scripts/lib/run-plan-headless.sh` line 251
**Before:** `"$SCRIPT_DIR/../mab-run.sh"`
**After:** `"$SCRIPT_DIR/mab-run.sh"`
**Root cause:** `SCRIPT_DIR` resolves to `scripts/` (set in `run-plan.sh` line 14). `../mab-run.sh` looks at repo root; `mab-run.sh` lives in `scripts/`.

## Resulting Line Counts

| Module | Before | After |
|--------|--------|-------|
| `run-plan-headless.sh` | 681 | ~416 |
| `run-plan-echo-back.sh` | (new) | ~145 |
| `run-plan-sampling.sh` | (new) | ~135 |

**Remaining debt:** Headless at ~416 is over the 300-line limit. The remaining bulk is the sequential batch orchestration loop (init → prompt → claude → gate → notify → failure handling). This is inherently sequential — further splitting would create artificial boundaries. Future candidate: retry/escalation logic (~60 lines) if the module grows again.

## Implementation Order

1. Create `run-plan-echo-back.sh` (move functions, update sources, fix tests)
2. Create `run-plan-sampling.sh` (extract + wrap in function, update call site)
3. Fix #73 (one-line path change)
4. Run full test suite to confirm no regressions
5. Commit and close #73

## Risk

**Low.** Echo-back extraction is pure function move with no interface change. Sampling extraction wraps existing code in a function — the only new interface is the 5-parameter signature. Both are tested by existing test files.
