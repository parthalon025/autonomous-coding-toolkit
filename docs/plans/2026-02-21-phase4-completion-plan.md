# Phase 4 Completion Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the remaining 15% of Phase 4 — batch-type-aware sampling, multi-armed bandit learning, AGENTS.md generation, and 2 missing ast-grep patterns.

**Architecture:** Extend existing sampling code in `run-plan-headless.sh` with batch-type classification and learned prompt allocation from `run-plan-scoring.sh`. Add `generate_agents_md()` to `run-plan-prompt.sh`. Add 2 pattern files to `scripts/patterns/`.

**Tech Stack:** Bash, jq, ast-grep YAML

---

## Quality Gates

Between each batch, run:
```bash
shellcheck -S warning scripts/*.sh scripts/lib/*.sh
bash scripts/tests/run-all-tests.sh
```

---

## Batch 1: Batch-Type Classification + Learned Prompt Allocation

### Task 1: Write tests for batch type classification

**Files:**
- Create: `scripts/tests/test-run-plan-sampling.sh`

**Step 1: Write the test file**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-scoring.sh"
source "$SCRIPT_DIR/helpers.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# === classify_batch_type ===

assert_exit "classify: Create files = new-file" 0 bash -c "
  source $SCRIPT_DIR/../lib/run-plan-scoring.sh
  source $SCRIPT_DIR/../lib/run-plan-parser.sh
  mkdir -p $WORK/plans
  cat > $WORK/plans/test.md << 'PLAN'
## Batch 1: Setup
**Files:**
- Create: src/lib.py
- Create: src/util.py
- Test: tests/test_lib.py

**Step 1:** Write files
PLAN
  result=\$(classify_batch_type '$WORK/plans/test.md' 1)
  [[ \$result == 'new-file' ]]
"

assert_exit "classify: Modify only = refactoring" 0 bash -c "
  source $SCRIPT_DIR/../lib/run-plan-scoring.sh
  source $SCRIPT_DIR/../lib/run-plan-parser.sh
  cat > $WORK/plans/test2.md << 'PLAN'
## Batch 1: Refactor auth
**Files:**
- Modify: src/auth.py:20-50
- Modify: src/session.py:10-30
- Test: tests/test_auth.py

**Step 1:** Update auth
PLAN
  result=\$(classify_batch_type '$WORK/plans/test2.md' 1)
  [[ \$result == 'refactoring' ]]
"

assert_exit "classify: Run commands only = test-only" 0 bash -c "
  source $SCRIPT_DIR/../lib/run-plan-scoring.sh
  source $SCRIPT_DIR/../lib/run-plan-parser.sh
  cat > $WORK/plans/test3.md << 'PLAN'
## Batch 1: Verify
Run: pytest tests/ -v
Run: bash scripts/quality-gate.sh --project-root .

**Step 1:** Run tests
PLAN
  result=\$(classify_batch_type '$WORK/plans/test3.md' 1)
  [[ \$result == 'test-only' ]]
"

assert_exit "classify: integration wiring title = integration" 0 bash -c "
  source $SCRIPT_DIR/../lib/run-plan-scoring.sh
  source $SCRIPT_DIR/../lib/run-plan-parser.sh
  cat > $WORK/plans/test4.md << 'PLAN'
## Batch 1: Integration Wiring
**Files:**
- Modify: src/main.py
- Create: src/glue.py

**Step 1:** Wire components
PLAN
  result=\$(classify_batch_type '$WORK/plans/test4.md' 1)
  [[ \$result == 'integration' ]]
"

echo ""
echo "Results: tests completed"
```

**Step 2: Write test for prompt variant allocation**

Append to the same test file:

```bash
# === get_prompt_variants ===

# Test: with no history, returns vanilla + random variants
assert_exit "variants: no history = vanilla + defaults" 0 bash -c "
  source $SCRIPT_DIR/../lib/run-plan-scoring.sh
  result=\$(get_prompt_variants 'new-file' '/nonexistent/outcomes.json' 3)
  echo \"\$result\" | grep -q 'vanilla'
"

# Test: get_prompt_variants returns exactly N variants
assert_exit "variants: returns N lines" 0 bash -c "
  source $SCRIPT_DIR/../lib/run-plan-scoring.sh
  result=\$(get_prompt_variants 'refactoring' '/nonexistent/outcomes.json' 3)
  count=\$(echo \"\$result\" | wc -l)
  [[ \$count -eq 3 ]]
"
```

**Step 3: Run tests to verify they fail**

Run: `bash scripts/tests/test-run-plan-sampling.sh`
Expected: FAIL — `classify_batch_type` and `get_prompt_variants` not defined

**Step 4: Commit test file**

```bash
git add scripts/tests/test-run-plan-sampling.sh
git commit -m "test: add sampling tests for batch-type classification and prompt variants"
```

---

### Task 2: Implement batch-type classification

**Files:**
- Modify: `scripts/lib/run-plan-scoring.sh`

**Step 1: Add classify_batch_type function**

Append to `scripts/lib/run-plan-scoring.sh`:

```bash
# Classify a batch by its dominant action type.
# Returns: new-file | refactoring | integration | test-only | unknown
classify_batch_type() {
    local plan_file="$1" batch_num="$2"
    local batch_text title

    # Source parser if not already loaded
    type get_batch_text &>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/run-plan-parser.sh"

    batch_text=$(get_batch_text "$plan_file" "$batch_num" 2>/dev/null || true)
    title=$(get_batch_title "$plan_file" "$batch_num" 2>/dev/null || true)

    # Check title for integration keywords
    if echo "$title" | grep -qiE 'integrat|wir|connect|glue'; then
        echo "integration"
        return
    fi

    local creates modifies runs
    creates=$(echo "$batch_text" | grep -cE '^\s*-\s*Create:' || true)
    modifies=$(echo "$batch_text" | grep -cE '^\s*-\s*Modify:' || true)
    runs=$(echo "$batch_text" | grep -cE '^Run:' || true)

    # Test-only: only Run commands, no Create/Modify
    if [[ "${creates:-0}" -eq 0 && "${modifies:-0}" -eq 0 && "${runs:-0}" -gt 0 ]]; then
        echo "test-only"
        return
    fi

    # New file creation dominant
    if [[ "${creates:-0}" -gt "${modifies:-0}" ]]; then
        echo "new-file"
        return
    fi

    # Refactoring: modifications dominant
    if [[ "${modifies:-0}" -gt 0 ]]; then
        echo "refactoring"
        return
    fi

    echo "unknown"
}
```

**Step 2: Add get_prompt_variants function**

Append to `scripts/lib/run-plan-scoring.sh`:

```bash
# Get prompt variant suffixes for a batch type.
# Uses learned outcomes if available, otherwise defaults.
# Args: <batch_type> <outcomes_file> <count>
# Output: N lines, each a prompt suffix string
get_prompt_variants() {
    local batch_type="$1"
    local outcomes_file="$2"
    local count="${3:-3}"

    # Default variants per batch type
    local -A type_variants
    type_variants[new-file]="check all imports before running tests|write tests first then implement"
    type_variants[refactoring]="minimal change only|run tests after each edit"
    type_variants[integration]="trace end-to-end before declaring done|check every import and export"
    type_variants[test-only]="use real objects not mocks|focus on edge cases only"
    type_variants[unknown]="try a different approach|make the minimum possible change"

    local defaults="${type_variants[$batch_type]:-${type_variants[unknown]}}"

    # Slot 1: always vanilla
    echo "vanilla"

    # Check for learned winners
    local learned_variant=""
    if [[ -f "$outcomes_file" ]]; then
        learned_variant=$(jq -r --arg bt "$batch_type" \
            '[.[] | select(.batch_type == $bt and .won == true)] | sort_by(.score) | reverse | .[0].prompt_variant // empty' \
            "$outcomes_file" 2>/dev/null || true)
    fi

    # Slot 2: learned winner or first default
    local variant2="${learned_variant:-$(echo "$defaults" | cut -d'|' -f1)}"
    if [[ "$count" -ge 2 ]]; then
        echo "$variant2"
    fi

    # Slot 3+: remaining defaults (exploration)
    local slot=3
    IFS='|' read -ra parts <<< "$defaults"
    for part in "${parts[@]}"; do
        [[ "$slot" -gt "$count" ]] && break
        [[ "$part" == "$variant2" ]] && continue
        echo "$part"
        slot=$((slot + 1))
    done

    # Fill remaining slots with generic variants
    while [[ "$slot" -le "$count" ]]; do
        echo "try a fundamentally different approach"
        slot=$((slot + 1))
    done
}
```

**Step 3: Run tests**

Run: `bash scripts/tests/test-run-plan-sampling.sh`
Expected: ALL PASS

**Step 4: Run full suite**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: 25 test files, ALL PASS

**Step 5: Commit**

```bash
git add scripts/lib/run-plan-scoring.sh
git commit -m "feat: add batch-type classification and learned prompt variant allocation"
```

---

### Task 3: Wire batch-type-aware variants into headless runner

**Files:**
- Modify: `scripts/lib/run-plan-headless.sh:96-102` (replace hardcoded variant suffixes)

**Step 1: Replace the hardcoded variant case statement**

In `scripts/lib/run-plan-headless.sh`, replace lines 96-102:

```bash
                for ((c = 0; c < SAMPLE_COUNT; c++)); do
                    local variant_suffix=""
                    case $c in
                        0) variant_suffix="" ;;  # vanilla retry
                        1) variant_suffix=$'\nIMPORTANT: Take a fundamentally different approach than the previous attempt.' ;;
                        2) variant_suffix=$'\nIMPORTANT: Make the minimum possible change to pass the quality gate.' ;;
                    esac
```

With:

```bash
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
```

Also update the closing of the for loop — change `done` (after line 140) to match the new `while` loop:

The existing `done` on the line after the stash/checkout block closes the for loop. It now closes the while loop instead. No line change needed since `done` closes both `for` and `while`.

**Step 2: Update variant name logging**

In the sampling outcome logging section (~line 156-158), replace the hardcoded variant name lookup:

```bash
                    local variant_name="vanilla"
                    [[ "$winner" -eq 1 ]] && variant_name="different-approach"
                    [[ "$winner" -eq 2 ]] && variant_name="minimal-change"
```

With:

```bash
                    # Get the winning variant name from the variants list
                    local variant_name
                    variant_name=$(echo "$variants" | sed -n "$((winner + 1))p")
                    variant_name="${variant_name:-vanilla}"
```

**Step 3: Run full test suite + shellcheck**

Run: `shellcheck -S warning scripts/lib/run-plan-headless.sh && bash scripts/tests/run-all-tests.sh`
Expected: Clean shellcheck, ALL PASS

**Step 4: Commit**

```bash
git add scripts/lib/run-plan-headless.sh
git commit -m "feat: wire batch-type-aware prompt variants into sampling runner"
```

---

### Task 4: Add sampling config constants to routing

**Files:**
- Modify: `scripts/lib/run-plan-routing.sh` (add config block near top)

**Step 1: Add sampling configuration**

After the existing parallelism config block (~line 18), add:

```bash
# --- Sampling configuration ---
SAMPLE_ON_RETRY=true             # auto-sample when batch fails first attempt
SAMPLE_ON_CRITICAL=true          # auto-sample for critical: true batches
# shellcheck disable=SC2034  # consumed by run-plan-headless.sh
SAMPLE_DEFAULT_COUNT=3           # default candidate count
SAMPLE_MAX_COUNT=5               # hard cap
SAMPLE_MIN_MEMORY_PER_GB=4       # per-candidate memory requirement
```

**Step 2: Shellcheck**

Run: `shellcheck -S warning scripts/lib/run-plan-routing.sh`
Expected: Clean

**Step 3: Commit**

```bash
git add scripts/lib/run-plan-routing.sh
git commit -m "feat: add sampling configuration constants to routing module"
```

---

## Batch 2: AGENTS.md Auto-Generation + ast-grep Patterns

### Task 5: Write test for AGENTS.md generation

**Files:**
- Create: `scripts/tests/test-agents-md.sh`

**Step 1: Write the test**

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/run-plan-prompt.sh"
source "$SCRIPT_DIR/../lib/run-plan-parser.sh"
source "$SCRIPT_DIR/../lib/run-plan-routing.sh"
source "$SCRIPT_DIR/helpers.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create a test plan
cat > "$WORK/plan.md" << 'PLAN'
## Batch 1: Setup
**Files:**
- Create: src/lib.py
- Test: tests/test_lib.py

**Step 1:** Create files

## Batch 2: Core Logic
**Files:**
- Create: src/core.py
- Modify: src/lib.py

**Step 1:** Add core
PLAN

# Generate AGENTS.md
generate_agents_md "$WORK/plan.md" "$WORK" "headless"

assert_exit "AGENTS.md created" 0 test -f "$WORK/AGENTS.md"

output=$(cat "$WORK/AGENTS.md")
assert_contains "has batch count" "2 batches" "$output"
assert_contains "has mode" "headless" "$output"
assert_contains "has tools" "Bash" "$output"

echo ""
echo "Results: tests completed"
```

**Step 2: Run to verify failure**

Run: `bash scripts/tests/test-agents-md.sh`
Expected: FAIL — `generate_agents_md` not defined

**Step 3: Commit**

```bash
git add scripts/tests/test-agents-md.sh
git commit -m "test: add AGENTS.md generation tests"
```

---

### Task 6: Implement generate_agents_md

**Files:**
- Modify: `scripts/lib/run-plan-prompt.sh`

**Step 1: Add generate_agents_md function**

Append to `scripts/lib/run-plan-prompt.sh`:

```bash
# Generate AGENTS.md in the worktree for agent team awareness.
# Args: <plan_file> <worktree> <mode>
generate_agents_md() {
    local plan_file="$1" worktree="$2" mode="${3:-headless}"

    # Source parser if needed
    type count_batches &>/dev/null || source "$(dirname "${BASH_SOURCE[0]}")/run-plan-parser.sh"

    local total_batches
    total_batches=$(count_batches "$plan_file")

    local batch_info=""
    for ((b = 1; b <= total_batches; b++)); do
        local title
        title=$(get_batch_title "$plan_file" "$b")
        [[ -z "$title" ]] && continue
        batch_info+="| $b | $title |"$'\n'
    done

    cat > "$worktree/AGENTS.md" << EOF
# Agent Configuration

**Plan:** $(basename "$plan_file")
**Mode:** $mode
**Total:** $total_batches batches

## Tools Allowed

Bash, Read, Write, Edit, Grep, Glob

## Permission Mode

bypassPermissions

## Batches

| # | Title |
|---|-------|
${batch_info}
## Guidelines

- Run quality gate after each batch
- Commit after passing gate
- Append discoveries to progress.txt
- Do not modify files outside your batch scope
EOF
}
```

**Step 2: Run tests**

Run: `bash scripts/tests/test-agents-md.sh`
Expected: ALL PASS

**Step 3: Run full suite**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: 26+ test files, ALL PASS

**Step 4: Commit**

```bash
git add scripts/lib/run-plan-prompt.sh
git commit -m "feat: add AGENTS.md auto-generation for worktree agent awareness"
```

---

### Task 7: Wire AGENTS.md into headless runner

**Files:**
- Modify: `scripts/lib/run-plan-headless.sh`

**Step 1: Add AGENTS.md generation at run start**

In `run_mode_headless()`, after the state initialization block (around line 30), add:

```bash
    # Generate AGENTS.md for agent awareness
    generate_agents_md "$PLAN_FILE" "$WORKTREE" "$MODE"
```

**Step 2: Run full suite + shellcheck**

Run: `shellcheck -S warning scripts/lib/run-plan-headless.sh && bash scripts/tests/run-all-tests.sh`
Expected: Clean

**Step 3: Commit**

```bash
git add scripts/lib/run-plan-headless.sh
git commit -m "feat: wire AGENTS.md generation into headless runner startup"
```

---

### Task 8: Add 2 missing ast-grep patterns

**Files:**
- Create: `scripts/patterns/retry-loop.yml`
- Create: `scripts/patterns/unused-import.yml`

**Step 1: Create retry-loop.yml**

```yaml
id: retry-loop-no-backoff
language: python
rule:
  pattern: |
    for $_ in range($RETRIES):
      try:
        $$$BODY
      except $EXC:
        $$$HANDLER
message: "Retry loop without backoff — add exponential backoff or sleep between retries"
severity: warning
```

**Step 2: Create unused-import.yml**

```yaml
id: unused-import
language: python
rule:
  pattern: import $MODULE
message: "Verify this import is used — unused imports increase load time and confuse readers"
severity: hint
note: "Advisory only — ast-grep cannot track usage across the file. Review manually."
```

**Step 3: Verify pattern count**

Run: `ls scripts/patterns/*.yml | wc -l`
Expected: 5

**Step 4: Commit**

```bash
git add scripts/patterns/retry-loop.yml scripts/patterns/unused-import.yml
git commit -m "feat: add retry-loop and unused-import ast-grep patterns (5 total)"
```

---

## Batch 3: Integration Wiring + Verification

### Task 9: Wire sampling auto-trigger on retry and critical batches

**Files:**
- Modify: `scripts/lib/run-plan-headless.sh`

**Step 1: Add auto-sampling logic**

In the retry loop section of `run_mode_headless()`, before the existing `if [[ "${SAMPLE_COUNT:-0}" -gt 0 && $attempt -ge 2 ]]` check (~line 88), add:

```bash
            # Auto-sample on retry if configured
            if [[ "${SAMPLE_ON_RETRY:-true}" == "true" && "$SAMPLE_COUNT" -eq 0 && $attempt -ge 2 ]]; then
                SAMPLE_COUNT="${SAMPLE_DEFAULT_COUNT:-3}"
                echo "  Auto-enabling sampling ($SAMPLE_COUNT candidates) for retry"
            fi

            # Auto-sample on critical batches
            if [[ "${SAMPLE_ON_CRITICAL:-true}" == "true" && "$SAMPLE_COUNT" -eq 0 && $attempt -eq 1 ]]; then
                if is_critical_batch "$PLAN_FILE" "$batch"; then
                    SAMPLE_COUNT="${SAMPLE_DEFAULT_COUNT:-3}"
                    echo "  Auto-enabling sampling ($SAMPLE_COUNT candidates) for critical batch"
                fi
            fi
```

**Step 2: Add memory guard before sampling**

Right after the auto-trigger block, before entering the sampling path:

```bash
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
```

**Step 3: Shellcheck + full tests**

Run: `shellcheck -S warning scripts/lib/run-plan-headless.sh && bash scripts/tests/run-all-tests.sh`
Expected: Clean

**Step 4: Commit**

```bash
git add scripts/lib/run-plan-headless.sh
git commit -m "feat: auto-trigger sampling on retry and critical batches with memory guard"
```

---

### Task 10: Update CLAUDE.md and run final verification

**Files:**
- Modify: `CLAUDE.md` (update capability list)

**Step 1: Update CLAUDE.md**

In the Quality Gates section, add sampling info. In the State & Persistence section, confirm `logs/sampling-outcomes.json` is listed.

**Step 2: Run full verification**

Run all checks:

```bash
shellcheck -S warning scripts/*.sh scripts/lib/*.sh scripts/tests/test-*.sh
bash scripts/tests/run-all-tests.sh
bash scripts/quality-gate.sh --project-root .
bash scripts/pipeline-status.sh .
```

Expected: All clean, all pass.

**Step 3: Final commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with Phase 4 completion — sampling, AGENTS.md, patterns"
```

**Step 4: Push**

```bash
git push
```
