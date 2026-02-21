#!/usr/bin/env bash
# Test run-plan.sh end-to-end — exercises the full Mode C headless loop
# with a fake claude binary and fake quality gate (no real API calls).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_PLAN="$SCRIPT_DIR/../run-plan.sh"

FAILURES=0
TESTS=0

# --- Setup temp workspace ---
WORK=$(mktemp -d)
FIXTURES=$(mktemp -d)
trap 'rm -rf "$WORK" "$FIXTURES"' EXIT

# 1. Git init the worktree
git -C "$WORK" init -q
git -C "$WORK" config user.email "test@test.com"
git -C "$WORK" config user.name "Test"

# Gitignore run-plan artifacts so check_git_clean passes
cat > "$WORK/.gitignore" <<'GITIGNORE'
.run-plan-state.json
logs/
GITIGNORE

git -C "$WORK" add -A
git -C "$WORK" commit -q -m "init"

# 2. Create a small plan file (2 batches, 2 tasks each)
cat > "$WORK/plan.md" <<'PLAN'
# Test Plan

## Batch 1: Setup foundation

### Task 1: Create config module
Create the config module with defaults.

### Task 2: Add config tests
Write tests for the config module.

## Batch 2: Build feature

### Task 3: Implement feature
Build the main feature on top of config.

### Task 4: Add feature tests
Write tests for the feature.
PLAN

git -C "$WORK" add plan.md
git -C "$WORK" commit -q -m "add plan"

# 3. Create fake claude binary (outside worktree to keep git clean)
FAKE_BIN="$FIXTURES/bin"
mkdir -p "$FAKE_BIN"

cat > "$FAKE_BIN/claude" <<'FAKECLAUDE'
#!/usr/bin/env bash
# Fake claude — simulates batch work without API calls
echo "Working on batch..."
echo "42 passed, 0 failed in 1.2s"
exit 0
FAKECLAUDE
chmod +x "$FAKE_BIN/claude"

# 4. Create fake quality gate script (outside worktree)
cat > "$FIXTURES/fake-quality-gate.sh" <<'FAKEGATE'
#!/usr/bin/env bash
# Fake quality gate — always passes
echo "42 passed in 1.0s"
exit 0
FAKEGATE
chmod +x "$FIXTURES/fake-quality-gate.sh"

# 5. Run run-plan.sh with fake claude first on PATH
export PATH="$FAKE_BIN:$PATH"

OUTPUT=$(cd "$WORK" && "$RUN_PLAN" "$WORK/plan.md" \
    --worktree "$WORK" \
    --quality-gate "$FIXTURES/fake-quality-gate.sh" \
    --on-failure stop \
    2>&1) && EXIT_CODE=0 || EXIT_CODE=$?

# --- Assertions ---

assert() {
    local desc="$1" result="$2"
    TESTS=$((TESTS + 1))
    if [[ "$result" == "true" ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        FAILURES=$((FAILURES + 1))
    fi
}

# 1. Exit code is 0
assert "exit code is 0" "$([ "$EXIT_CODE" -eq 0 ] && echo true || echo false)"

# 2. State file was created
assert "state file exists" "$([ -f "$WORK/.run-plan-state.json" ] && echo true || echo false)"

# 3. Both batches in completed_batches
if [[ -f "$WORK/.run-plan-state.json" ]]; then
    HAS_BATCH_1=$(jq '.completed_batches | contains([1])' "$WORK/.run-plan-state.json")
    HAS_BATCH_2=$(jq '.completed_batches | contains([2])' "$WORK/.run-plan-state.json")
    assert "batch 1 in completed_batches" "$HAS_BATCH_1"
    assert "batch 2 in completed_batches" "$HAS_BATCH_2"
else
    assert "batch 1 in completed_batches (no state file)" "false"
    assert "batch 2 in completed_batches (no state file)" "false"
fi

# 4. Log files exist
assert "batch 1 log exists" "$([ -f "$WORK/logs/batch-1-attempt-1.log" ] && echo true || echo false)"
assert "batch 2 log exists" "$([ -f "$WORK/logs/batch-2-attempt-1.log" ] && echo true || echo false)"

# --- Summary ---
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    echo ""
    echo "--- Debug output ---"
    echo "$OUTPUT"
    if [[ -f "$WORK/.run-plan-state.json" ]]; then
        echo ""
        echo "--- State file ---"
        cat "$WORK/.run-plan-state.json"
    fi
    exit 1
fi
echo "ALL PASSED"
