# Headless Module Split Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Split `scripts/lib/run-plan-headless.sh` (681 lines) into 3 modules, fix issue #73 (MAB path bug), and update all tests.

**Architecture:** Extract echo-back gate and sampling logic into standalone lib modules sourced by `run-plan.sh`. Headless retains the batch orchestration loop. Each extracted module is self-contained with documented interfaces for reuse across execution modes and projects.

**Tech Stack:** Bash (shellcheck-clean), existing test harness (assert_eq pattern)

**Design doc:** `docs/plans/2026-02-24-headless-module-split-design.md`

---

## Batch 1: Extract echo-back gate + update tests

### Task 1: Create `scripts/lib/run-plan-echo-back.sh`

**Files:**
- Create: `scripts/lib/run-plan-echo-back.sh`
- Modify: `scripts/lib/run-plan-headless.sh` (remove lines 1-163)
- Modify: `scripts/run-plan.sh:47` (add source line)

**Step 1: Create the new module file**

Create `scripts/lib/run-plan-echo-back.sh` with the shebang, header comment, and both functions copied verbatim from `run-plan-headless.sh` lines 1-163:

```bash
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
```

Then paste the two functions (`_echo_back_check` and `echo_back_check`) exactly as they appear in `run-plan-headless.sh` lines 14-163.

**Step 2: Remove echo-back functions from headless**

In `scripts/lib/run-plan-headless.sh`, delete everything from line 1 through line 163 (the closing `}` of `echo_back_check`). The file should now start with `run_mode_headless() {`.

Update the file header to:

```bash
#!/usr/bin/env bash
# run-plan-headless.sh — Headless batch execution loop for run-plan
#
# Requires globals: WORKTREE, RESUME, START_BATCH, END_BATCH, NOTIFY,
#   PLAN_FILE, QUALITY_GATE_CMD, PYTHON, MAX_RETRIES, ON_FAILURE, VERIFY, MODE,
#   SKIP_ECHO_BACK, STRICT_ECHO_BACK
# Requires libs: run-plan-parser, state, quality-gate, notify, prompt, scoring, echo-back
```

**Step 3: Add source line in `run-plan.sh`**

In `scripts/run-plan.sh`, add this line BEFORE line 47 (`source "$SCRIPT_DIR/lib/run-plan-headless.sh"`):

```bash
source "$SCRIPT_DIR/lib/run-plan-echo-back.sh"
```

**Step 4: Run tests to verify no regressions**

Run: `bash scripts/tests/test-echo-back.sh`
Expected: ALL PASSED (5/5)

Run: `bash scripts/tests/test-run-plan-headless.sh`
Expected: Some echo-back tests will FAIL because they grep `$RPH` for `_echo_back_check()` — that's expected, we fix those in Task 2.

**Step 5: Commit**

```bash
git add scripts/lib/run-plan-echo-back.sh scripts/lib/run-plan-headless.sh scripts/run-plan.sh
git commit -m "refactor: extract echo-back gate to run-plan-echo-back.sh"
```

### Task 2: Update test files for echo-back extraction

**Files:**
- Modify: `scripts/tests/test-echo-back.sh:7` (change source path)
- Modify: `scripts/tests/test-run-plan-headless.sh` (update echo-back test assertions)

**Step 1: Fix `test-echo-back.sh` source path**

In `scripts/tests/test-echo-back.sh` line 7, change:

```bash
# Before:
source "$SCRIPT_DIR/../lib/run-plan-headless.sh" 2>/dev/null || true
# After:
source "$SCRIPT_DIR/../lib/run-plan-echo-back.sh" 2>/dev/null || true
```

**Step 2: Update `test-run-plan-headless.sh` echo-back assertions**

The headless test file has tests that grep `$RPH` (the headless file) for echo-back functions. These need to point at the new echo-back file instead. Update these tests:

Lines 235-242: Change `$RPH` to the echo-back file:
```bash
# Before:
RPH="$SCRIPT_DIR/../lib/run-plan-headless.sh"
# (this is already defined at line 7)

# Add near the top (after RPH definition, around line 8):
RPEB="$SCRIPT_DIR/../lib/run-plan-echo-back.sh"
```

Then update the 6 echo-back grep tests (lines 235-260) to use `$RPEB` instead of `$RPH`:

- Line 237: `grep -q '_echo_back_check()' "$RPEB"` — and update PASS/FAIL messages to say "run-plan-echo-back.sh"
- Line 246: `grep -q 'STRICT_ECHO_BACK' "$RPEB"`
- Line 255: `grep -q 'NON-BLOCKING' "$RPEB"`

And update the 3 behavioral tests (lines 262-305) to source `$RPEB` instead of `$RPH`:

- Line 265: `source "$RPEB" 2>/dev/null || true`
- Line 278: `source "$RPEB" 2>/dev/null || true`
- Line 293: `source "$RPEB" 2>/dev/null || true`

**Step 3: Run both test files**

Run: `bash scripts/tests/test-echo-back.sh`
Expected: ALL PASSED (5/5)

Run: `bash scripts/tests/test-run-plan-headless.sh`
Expected: ALL PASSED (all tests pass with updated references)

**Step 4: Commit**

```bash
git add scripts/tests/test-echo-back.sh scripts/tests/test-run-plan-headless.sh
git commit -m "test: update echo-back test references after extraction"
```

## Batch 2: Extract sampling logic + fix #73

### Task 3: Create `scripts/lib/run-plan-sampling.sh`

**Files:**
- Create: `scripts/lib/run-plan-sampling.sh`
- Modify: `scripts/lib/run-plan-headless.sh` (replace inline sampling with function call)
- Modify: `scripts/run-plan.sh` (add source line)

**Step 1: Create the new sampling module**

Create `scripts/lib/run-plan-sampling.sh` with two functions extracted from `run-plan-headless.sh`:

```bash
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
#     Prints warning and sets SAMPLE_COUNT=0 on insufficient memory.
#   run_sampling_candidates <worktree> <plan_file> <batch> <prompt> <quality_gate_cmd>
#     Spawns SAMPLE_COUNT candidates, scores them, applies winner's patch.
#     Returns 0 if winner found, 1 if no candidate passed.
#
# Globals (read-only): SAMPLE_COUNT, SAMPLE_MIN_MEMORY_PER_GB
# Requires libs: run-plan-scoring (score_candidate, select_winner, classify_batch_type, get_prompt_variants)
#                run-plan-quality-gate (run_quality_gate)
#                run-plan-state (get_previous_test_count)
```

**`check_memory_for_sampling` function:** Extract from current headless lines 354-369:

```bash
# check_memory_for_sampling
# Checks if sufficient memory is available for SAMPLE_COUNT parallel candidates.
# Returns: 0 if OK, 1 if insufficient (also sets SAMPLE_COUNT=0 and prints warning)
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
```

**`run_sampling_candidates` function:** Extract from current headless lines 373-494. Wrap the block in a function that takes 5 parameters:

```bash
# run_sampling_candidates <worktree> <plan_file> <batch> <prompt> <quality_gate_cmd>
# Spawns SAMPLE_COUNT parallel candidates with batch-type-aware prompt variants.
# Uses patch files for worktree state management (no git stash — bug #2/#27).
# Returns: 0 if winner found (worktree contains winner's changes), 1 if no candidate passed.
# Side-effects: writes logs/sampling-outcomes.json
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
    # (rest of the code from lines 382-494, replacing $WORKTREE with $worktree,
    #  $PLAN_FILE with $plan_file, $QUALITY_GATE_CMD with $quality_gate_cmd)

    # ... (full extraction — replace global refs with parameters)

    # Return 0 for winner found, 1 for no candidate passed
}
```

Inside the function body, replace these global variable references with function parameters:
- `$WORKTREE` → `$worktree`
- `$PLAN_FILE` → `$plan_file`
- `$QUALITY_GATE_CMD` → `$quality_gate_cmd`

Keep `$SAMPLE_COUNT` as a global read (it's set by the caller and used across the module).

**Step 2: Replace inline sampling in headless with function call**

In `run-plan-headless.sh`, replace the entire sampling block (the `if [[ "${SAMPLE_COUNT:-0}" -gt 0 && $attempt -ge 2 ]]` block through its closing `fi` and `continue`) with:

```bash
            # If sampling enabled and this is a retry, use parallel candidates
            if [[ "${SAMPLE_COUNT:-0}" -gt 0 && $attempt -ge 2 ]]; then
                check_memory_for_sampling || true
                if [[ "${SAMPLE_COUNT:-0}" -gt 0 ]]; then
                    if run_sampling_candidates "$WORKTREE" "$PLAN_FILE" "$batch" "$prompt" "$QUALITY_GATE_CMD"; then
                        batch_passed=true
                        break
                    fi
                    continue  # Skip normal retry path below
                fi
            fi
```

Also replace the memory guard block (lines 354-369) with:

```bash
            # Memory guard for sampling
            if [[ "${SAMPLE_COUNT:-0}" -gt 0 ]]; then
                check_memory_for_sampling || true
            fi
```

**Step 3: Add source line in `run-plan.sh`**

In `scripts/run-plan.sh`, add BEFORE the headless source line:

```bash
source "$SCRIPT_DIR/lib/run-plan-sampling.sh"
```

**Step 4: Run tests**

Run: `bash scripts/tests/test-run-plan-headless.sh`
Expected: ALL PASSED — the sampling grep tests check `$RPH` for `_baseline_patch`, `_winner_patch`, `git apply`. These patterns will still exist in the headless file OR we need to update them. Check and fix if needed.

Run: `bash scripts/tests/test-echo-back.sh`
Expected: ALL PASSED (5/5, unchanged)

**Step 5: Commit**

```bash
git add scripts/lib/run-plan-sampling.sh scripts/lib/run-plan-headless.sh scripts/run-plan.sh
git commit -m "refactor: extract sampling logic to run-plan-sampling.sh"
```

### Task 4: Fix issue #73 (MAB path resolution)

**Files:**
- Modify: `scripts/lib/run-plan-headless.sh` (one line change)

**Step 1: Fix the path**

In `scripts/lib/run-plan-headless.sh`, find the MAB invocation line (originally line 251, now shifted after extraction). Change:

```bash
# Before:
"$SCRIPT_DIR/../mab-run.sh" \
# After:
"$SCRIPT_DIR/mab-run.sh" \
```

**Step 2: Verify path resolves correctly**

Run: `ls -la "$(cd "$(dirname "$(readlink -f scripts/run-plan.sh)")" && pwd)/mab-run.sh"`
Expected: Shows `scripts/mab-run.sh` exists at the resolved path.

**Step 3: Commit**

```bash
git add scripts/lib/run-plan-headless.sh
git commit -m "fix: MAB path resolution — \$SCRIPT_DIR/mab-run.sh not \$SCRIPT_DIR/../ (closes #73)"
```

### Task 5: Update sampling tests in `test-run-plan-headless.sh`

**Files:**
- Modify: `scripts/tests/test-run-plan-headless.sh`

**Step 1: Add sampling module reference**

Near the top of `test-run-plan-headless.sh` (after line 8 where `RPEB` was added), add:

```bash
RPS="$SCRIPT_DIR/../lib/run-plan-sampling.sh"
```

**Step 2: Update sampling grep tests**

Lines 176-213 grep `$RPH` for sampling patterns (`_baseline_patch`, `_winner_patch`, `git stash`, `git apply`). Update:

- The `_baseline_patch` test (line 177): grep `$RPS` instead of `$RPH`
- The `_winner_patch` test (line 186): grep `$RPS` instead of `$RPH`
- The `git stash` test (line 196): extract sampling block from `$RPS` instead of `$RPH`
- The `git apply` test (line 208): extract from `$RPS` instead of `$RPH`
- Update PASS/FAIL messages to reference "run-plan-sampling.sh"

**Step 3: Add existence test for new modules**

Add near the existing file-existence test (after line 33):

```bash
# === Extracted echo-back file exists ===
TESTS=$((TESTS + 1))
if [[ -f "$RPEB" ]]; then
    echo "PASS: run-plan-echo-back.sh exists"
else
    echo "FAIL: run-plan-echo-back.sh should exist at scripts/lib/"
    FAILURES=$((FAILURES + 1))
fi

# === Extracted sampling file exists ===
TESTS=$((TESTS + 1))
if [[ -f "$RPS" ]]; then
    echo "PASS: run-plan-sampling.sh exists"
else
    echo "FAIL: run-plan-sampling.sh should exist at scripts/lib/"
    FAILURES=$((FAILURES + 1))
fi

# === run-plan.sh sources new modules ===
TESTS=$((TESTS + 1))
if grep -q 'source.*lib/run-plan-echo-back.sh' "$RP"; then
    echo "PASS: run-plan.sh sources lib/run-plan-echo-back.sh"
else
    echo "FAIL: run-plan.sh should source lib/run-plan-echo-back.sh"
    FAILURES=$((FAILURES + 1))
fi

TESTS=$((TESTS + 1))
if grep -q 'source.*lib/run-plan-sampling.sh' "$RP"; then
    echo "PASS: run-plan.sh sources lib/run-plan-sampling.sh"
else
    echo "FAIL: run-plan.sh should source lib/run-plan-sampling.sh"
    FAILURES=$((FAILURES + 1))
fi
```

**Step 4: Run all test files**

Run: `bash scripts/tests/test-run-plan-headless.sh`
Expected: ALL PASSED

Run: `bash scripts/tests/test-echo-back.sh`
Expected: ALL PASSED

Run: `bash scripts/tests/test-mab-run.sh`
Expected: ALL PASSED (MAB wiring test should still find the check in headless)

**Step 5: Commit**

```bash
git add scripts/tests/test-run-plan-headless.sh
git commit -m "test: update headless tests for sampling extraction + new module checks"
```

## Batch 3: Verify line counts + full suite

### Task 6: Verify final line counts and run full test suite

**Files:** (read-only verification)

**Step 1: Check line counts**

Run: `wc -l scripts/lib/run-plan-headless.sh scripts/lib/run-plan-echo-back.sh scripts/lib/run-plan-sampling.sh`

Expected (approximate):
- `run-plan-headless.sh`: ~416 lines
- `run-plan-echo-back.sh`: ~145 lines
- `run-plan-sampling.sh`: ~135 lines

**Step 2: Run full test suite**

Run: `for t in scripts/tests/test-*.sh; do echo "=== $t ==="; bash "$t" || echo "FAILED: $t"; done`

Expected: All test files pass.

**Step 3: shellcheck all new and modified files**

Run: `shellcheck scripts/lib/run-plan-echo-back.sh scripts/lib/run-plan-sampling.sh scripts/lib/run-plan-headless.sh`

Expected: No errors. Fix any warnings before proceeding.

**Step 4: Close issue #73**

Run: `gh issue close 73 --comment "Fixed in $(git log --oneline -1 --grep='MAB path' | cut -d' ' -f1). \$SCRIPT_DIR/mab-run.sh resolves correctly now."`

**Step 5: Final commit (if shellcheck fixes needed)**

```bash
git add -A
git commit -m "chore: shellcheck fixes after module split"
```
