# Multi-Armed Bandit System Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement competing autonomous agents (superpowers vs ralph-wiggum) that execute the same brief in parallel worktrees, judged by an LLM that extracts lessons and updates strategy performance data.

**Architecture:** Thin bash orchestrator (`mab-run.sh`) creates worktrees, launches agents via `claude -p`, runs quality gates on both, then launches a judge agent that picks a winner and extracts lessons. A planner agent routes work units to MAB or single strategy based on `strategy-perf.json` historical data. An architecture map generator scans the project source to produce `ARCHITECTURE-MAP.json` for planner/judge context.

**Tech Stack:** Bash (orchestration), `claude -p` (agents), `jq` (JSON manipulation), Git worktrees (isolation)

**Design doc:** `docs/plans/2026-02-22-mab-run-design.md`

---

## Batch 1: Agent Prompts and Architecture Map Generator

Core prompt files that define agent behavior, plus the architecture map generator that feeds project structure to the planner and judge.

### Task 1: Create Agent A (superpowers) prompt

**Files:**
- Create: `scripts/prompts/agent-a-superpowers.md`

**Step 1: Write the prompt file**

```markdown
# Agent A — Superpowers Strategy

You are executing a work unit using the **superpowers skill chain**.

## Shared Brief

{DESIGN_DOC}

## PRD

{PRD_CONTENT}

## Architecture Map

{ARCHITECTURE_MAP}

## Previous MMAB Lessons

{MAB_LESSONS}

## Instructions

1. **Write your own implementation plan first.** Analyze the design doc, PRD, and architecture map. Produce a step-by-step plan before writing any code.
2. **Follow TDD:** Write failing test → verify it fails → implement minimal code → verify it passes → commit.
3. **Run quality gates between logical groups of tasks.** Use the quality gate command: `{QUALITY_GATE_CMD}`
4. **Commit after each passing gate** with descriptive messages.
5. **Append discoveries to progress.txt** after each logical unit.

## Toolkit Context

You have access to all toolkit skills, lessons, and hooks. Follow CLAUDE.md conventions. Use `lesson-check.sh` before committing.

## Completion

You are done when all PRD acceptance criteria pass (exit 0). Run each criterion and report results.
```

**Step 2: Verify file exists and is valid markdown**

Run: `test -f scripts/prompts/agent-a-superpowers.md && echo "OK" || echo "MISSING"`
Expected: OK

### Task 2: Create Agent B (ralph) prompt

**Files:**
- Create: `scripts/prompts/agent-b-ralph.md`

**Step 1: Write the prompt file**

```markdown
# Agent B — Ralph Wiggum Strategy

You are executing a work unit using the **ralph-loop approach**.

## Shared Brief

{DESIGN_DOC}

## PRD

{PRD_CONTENT}

## Architecture Map

{ARCHITECTURE_MAP}

## Previous MMAB Lessons

{MAB_LESSONS}

## Instructions

1. **All PRD acceptance criteria in the PRD section must pass (exit 0).**
2. **Iterate until done.** Read the criteria, start coding, test, fix, repeat.
3. **Use any toolkit skills as needed** — TDD, debugging, etc. are available but not mandated in a specific order.
4. **Run quality gate periodically:** `{QUALITY_GATE_CMD}`
5. **Commit working increments** with descriptive messages.
6. **Append discoveries to progress.txt** as you go.

## Toolkit Context

You have access to all toolkit skills, lessons, and hooks. Follow CLAUDE.md conventions. Use `lesson-check.sh` before committing.

## Completion

You are done when ALL acceptance criteria pass. Run each criterion and report results.
```

**Step 2: Verify file exists**

Run: `test -f scripts/prompts/agent-b-ralph.md && echo "OK" || echo "MISSING"`
Expected: OK

### Task 3: Create planner agent prompt

**Files:**
- Create: `scripts/prompts/planner-agent.md`

**Step 1: Write the prompt file**

```markdown
# Planner Agent — MAB Routing Decisions

You are a routing planner for the Multi-Armed Bandit system. Your job is to decide which work units should be MAB tested and which should go to a single strategy.

## Inputs

### Design Doc
{DESIGN_DOC}

### PRD Task Graph
{PRD_CONTENT}

### Architecture Map
{ARCHITECTURE_MAP}

### Strategy Performance Data
{STRATEGY_PERF}

## Decision Rules

For each work unit:

1. **Classify type:** new-file, refactoring, integration, test-only
2. **Check strategy-perf data** for this type
3. **If clear winner** (>70% win rate, 10+ data points): route to winner
4. **If uncertain** or insufficient data: MAB run
5. **If error-prone type** (historically high retry rate): MAB run

## Work Unit Sizing

| Project size | Strategy |
|-------------|----------|
| Small (< 5 PRD tasks) | MAB the whole project |
| Medium (5-15 PRD tasks) | Chunk by PRD dependency groups, route per chunk |
| Large (15+ PRD tasks) | Phase 1: MAB (explore), Phase 2+: route to winners (exploit) |

## Output Format

Respond with ONLY this JSON (no markdown fences, no explanation):

{
  "routing": [
    {
      "unit": 1,
      "description": "description of work unit",
      "type": "new-file|refactoring|integration|test-only",
      "decision": "mab_run|single",
      "strategy": "superpowers|ralph|null",
      "reasoning": "brief explanation"
    }
  ]
}
```

**Step 2: Verify file exists**

Run: `test -f scripts/prompts/planner-agent.md && echo "OK" || echo "MISSING"`
Expected: OK

### Task 4: Create judge agent prompt

**Files:**
- Create: `scripts/prompts/judge-agent.md`

**Step 1: Write the prompt file**

```markdown
# Judge Agent — MAB Evaluation

You are evaluating two competing implementations of the same work unit. Pick the winner and extract lessons.

## Context

### Design Doc
{DESIGN_DOC}

### PRD
{PRD_CONTENT}

### Architecture Map
{ARCHITECTURE_MAP}

### Previous MMAB Lessons
{MAB_LESSONS}

## Agent A Diff (superpowers strategy)
```
{DIFF_A}
```

## Agent A Quality Gate Results
{GATE_A}

## Agent B Diff (ralph strategy)
```
{DIFF_B}
```

## Agent B Quality Gate Results
{GATE_B}

## Automated Scores
- Agent A: gate_passed={GATE_A_PASSED}, test_count={TESTS_A}, diff_lines={DIFF_SIZE_A}
- Agent B: gate_passed={GATE_B_PASSED}, test_count={TESTS_B}, diff_lines={DIFF_SIZE_B}

## Evaluation Criteria

1. **WINNER SELECTION** — Which implementation better serves the overall architecture?
2. **BIDIRECTIONAL LESSONS** — What did the winner do well that the loser should learn from? What did the loser do well that the winner should learn from?
3. **FAILURE MODE CLASSIFICATION** — Categories: over-engineering, under-testing, code-duplication, integration-gap, convention-violation, wrong-abstraction-level
4. **TOOLKIT COMPLIANCE** — CLAUDE.md conventions? TDD? Hookify blocks? Verification?
5. **STRATEGY RECOMMENDATION** — For this work unit type, which strategy should be preferred? Confidence?

## Output Format

Respond with ONLY this JSON (no markdown fences, no explanation):

{
  "winner": "agent_a|agent_b",
  "confidence": "low|medium|high",
  "reasoning": "2-3 sentences explaining the decision",
  "failure_mode": "category from list above",
  "toolkit_compliance": {
    "agent_a": {"tdd": true/false, "conventions": true/false, "hookify_blocks": 0},
    "agent_b": {"tdd": true/false, "conventions": true/false, "hookify_blocks": 0}
  },
  "lessons": [
    {
      "pattern": "what was learned",
      "context": "when this applies",
      "recommendation": "what to do differently",
      "source_strategy": "agent_a|agent_b",
      "lesson_type": "syntactic|semantic"
    }
  ],
  "strategy_update": {
    "batch_type": "new-file|refactoring|integration|test-only",
    "winner": "superpowers|ralph",
    "confidence": "low|medium|high"
  }
}
```

**Step 2: Verify file exists**

Run: `test -f scripts/prompts/judge-agent.md && echo "OK" || echo "MISSING"`
Expected: OK

### Task 5: Write failing tests for architecture-map.sh

**Files:**
- Create: `scripts/tests/test-architecture-map.sh`

**Step 1: Write the test file**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SCRIPT="$SCRIPT_DIR/../architecture-map.sh"

# --- CLI tests ---
assert_exit "help exits 0" 0 "$SCRIPT" --help

output=$("$SCRIPT" --help 2>&1)
assert_contains "help mentions output" "ARCHITECTURE-MAP.json" "$output"

# --- Generate on a temp project ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Create a minimal project structure
mkdir -p "$TMPDIR/src" "$TMPDIR/tests"
cat > "$TMPDIR/src/main.sh" << 'SH'
#!/usr/bin/env bash
source ./src/utils.sh
SH
cat > "$TMPDIR/src/utils.sh" << 'SH'
#!/usr/bin/env bash
echo "utility"
SH
cat > "$TMPDIR/src/app.py" << 'PY'
from src.utils import helper
import os
PY

output=$("$SCRIPT" --project-root "$TMPDIR" 2>&1)
assert_exit "generates successfully" 0 "$SCRIPT" --project-root "$TMPDIR"
assert_contains "output is JSON" "modules" "$output"

# Verify output file
assert_eq "creates ARCHITECTURE-MAP.json" "true" "$(test -f "$TMPDIR/docs/ARCHITECTURE-MAP.json" && echo true || echo false)"

# Verify JSON structure
map_content=$(cat "$TMPDIR/docs/ARCHITECTURE-MAP.json")
assert_contains "has generated_at" "generated_at" "$map_content"
assert_contains "has modules array" "modules" "$map_content"

# Verify module detection
assert_contains "detects shell source" "utils.sh" "$map_content"

# --- Empty project ---
EMPTY_DIR=$(mktemp -d)
assert_exit "empty project exits 0" 0 "$SCRIPT" --project-root "$EMPTY_DIR"
rm -rf "$EMPTY_DIR"

report_results
```

**Step 2: Run tests to verify they fail**

Run: `bash scripts/tests/test-architecture-map.sh 2>&1 | tail -5`
Expected: FAIL (script doesn't exist yet)

### Task 6: Implement architecture-map.sh

**Files:**
- Create: `scripts/architecture-map.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail
# architecture-map.sh — Generate ARCHITECTURE-MAP.json from project source
#
# Usage: architecture-map.sh --project-root <dir> [--output <file>]
#
# Scans source files for import/source statements and produces a module
# dependency graph as JSON.

# --- Usage ---
usage() {
    cat <<'USAGE'
architecture-map.sh — Generate module dependency graph

Usage:
  architecture-map.sh --project-root <dir> [--output <file>]

Options:
  --project-root <dir>   Project root directory to scan
  --output <file>        Output file (default: <project-root>/docs/ARCHITECTURE-MAP.json)
  -h, --help             Show this help

Output:
  Produces docs/ARCHITECTURE-MAP.json with module names, files, and dependency edges
  derived from import/source/require statements.
USAGE
}

# --- Argument parsing ---
PROJECT_ROOT=""
OUTPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --output) OUTPUT_FILE="$2"; shift 2 ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "ERROR: --project-root required" >&2
    exit 1
fi

if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="$PROJECT_ROOT/docs/ARCHITECTURE-MAP.json"
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

# --- Scan functions ---

# Extract shell source dependencies
scan_shell() {
    local file="$1"
    grep -oE '(source|\.)\s+[^ ;]+' "$file" 2>/dev/null | \
        sed -E 's/^(source|\.) +//' | \
        sed 's/"//g; s/'\''//g' || true
}

# Extract Python import dependencies
scan_python() {
    local file="$1"
    {
        grep -oE '^from [a-zA-Z0-9_.]+' "$file" 2>/dev/null | sed 's/^from //' || true
        grep -oE '^import [a-zA-Z0-9_.]+' "$file" 2>/dev/null | sed 's/^import //' || true
    } | grep -v '^$' || true
}

# Extract JS/TS import dependencies
scan_js() {
    local file="$1"
    {
        grep -oE "from ['\"][^'\"]+['\"]" "$file" 2>/dev/null | sed "s/from ['\"]//; s/['\"]$//" || true
        grep -oE "require\(['\"][^'\"]+['\"]\)" "$file" 2>/dev/null | sed "s/require(['\"]//; s/['\"]\)$//" || true
    } | grep -v '^$' || true
}

# --- Main scan ---
modules_json="[]"

# Find source files (skip node_modules, .git, __pycache__, .venv)
while IFS= read -r -d '' file; do
    rel_path="${file#"$PROJECT_ROOT/"}"
    deps="[]"

    case "$file" in
        *.sh|*.bash)
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                deps=$(echo "$deps" | jq --arg d "$dep" '. + [$d]')
            done < <(scan_shell "$file")
            ;;
        *.py)
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                deps=$(echo "$deps" | jq --arg d "$dep" '. + [$d]')
            done < <(scan_python "$file")
            ;;
        *.js|*.ts|*.jsx|*.tsx|*.mjs)
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                deps=$(echo "$deps" | jq --arg d "$dep" '. + [$d]')
            done < <(scan_js "$file")
            ;;
        *) continue ;;
    esac

    # Derive module name from directory
    module_name=$(dirname "$rel_path")
    [[ "$module_name" == "." ]] && module_name="root"

    # Add to modules (merge if module already exists)
    modules_json=$(echo "$modules_json" | jq \
        --arg name "$module_name" \
        --arg file "$rel_path" \
        --argjson deps "$deps" \
        '
        if any(.[]; .name == $name) then
            map(if .name == $name then
                .files += [$file] |
                .depends_on += $deps |
                .depends_on |= unique
            else . end)
        else
            . + [{"name": $name, "files": [$file], "depends_on": $deps}]
        end
        ')
done < <(find "$PROJECT_ROOT" \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/__pycache__/*' \
    -not -path '*/.venv/*' \
    -not -path '*/vendor/*' \
    -not -path '*/.claude/*' \
    \( -name '*.sh' -o -name '*.bash' -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.jsx' -o -name '*.tsx' -o -name '*.mjs' \) \
    -print0 2>/dev/null)

# Produce final JSON
jq -n \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson modules "$modules_json" \
    '{"generated_at": $ts, "modules": $modules}' \
    > "$OUTPUT_FILE"

# Also print to stdout
cat "$OUTPUT_FILE"
```

**Step 2: Make executable**

Run: `chmod +x scripts/architecture-map.sh`

**Step 3: Run tests to verify they pass**

Run: `bash scripts/tests/test-architecture-map.sh`
Expected: ALL PASSED

**Step 4: Commit**

```bash
git add scripts/prompts/ scripts/architecture-map.sh scripts/tests/test-architecture-map.sh
git commit -m "feat: add agent prompts and architecture-map.sh for Multi-Armed Bandit system"
```

---

## Batch 2: MAB Run Orchestrator (mab-run.sh)

The core orchestrator that creates worktrees, launches agents, runs gates, invokes the judge, and merges the winner.

### Task 7: Write failing tests for mab-run.sh

**Files:**
- Create: `scripts/tests/test-mab-run.sh`

**Step 1: Write the test file**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SCRIPT="$SCRIPT_DIR/../mab-run.sh"

# --- CLI tests ---
assert_exit "help exits 0" 0 "$SCRIPT" --help

output=$("$SCRIPT" --help 2>&1)
assert_contains "help mentions worktree" "worktree" "$output"
assert_contains "help mentions judge" "judge" "$output"
assert_contains "help mentions design" "design" "$output"

# --- Missing args ---
assert_exit "no args exits 1" 1 "$SCRIPT"

# --- Dry-run mode ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Create minimal project for dry-run
mkdir -p "$TMPDIR/docs" "$TMPDIR/tasks" "$TMPDIR/logs"
cd "$TMPDIR" && git init -q && git add -A && git commit -q -m "init" && cd -

cat > "$TMPDIR/tasks/prd.json" << 'JSON'
{"tasks": [{"id": 1, "description": "test task", "criterion": "exit 0"}]}
JSON

cat > "$TMPDIR/design.md" << 'MD'
# Test Design
Simple test project.
MD

output=$("$SCRIPT" \
    --design "$TMPDIR/design.md" \
    --prd "$TMPDIR/tasks/prd.json" \
    --project-root "$TMPDIR" \
    --dry-run 2>&1)
assert_contains "dry-run shows worktree creation" "worktree" "$output"
assert_contains "dry-run shows agent launch" "agent" "$output"

# --- Data file initialization ---
output=$("$SCRIPT" \
    --design "$TMPDIR/design.md" \
    --prd "$TMPDIR/tasks/prd.json" \
    --project-root "$TMPDIR" \
    --init-data 2>&1)

assert_eq "creates strategy-perf.json" "true" \
    "$(test -f "$TMPDIR/logs/strategy-perf.json" && echo true || echo false)"
assert_eq "creates mab-lessons.json" "true" \
    "$(test -f "$TMPDIR/logs/mab-lessons.json" && echo true || echo false)"

# Verify JSON structure
strat=$(cat "$TMPDIR/logs/strategy-perf.json")
assert_contains "has new-file type" "new-file" "$strat"
assert_contains "has refactoring type" "refactoring" "$strat"

report_results
```

**Step 2: Run tests to verify they fail**

Run: `bash scripts/tests/test-mab-run.sh 2>&1 | tail -5`
Expected: FAIL

### Task 8: Implement mab-run.sh — argument parsing and data init

**Files:**
- Create: `scripts/mab-run.sh`

**Step 1: Write the script (part 1 — args, data init, dry-run)**

```bash
#!/usr/bin/env bash
set -euo pipefail
# mab-run.sh — MAB execution orchestrator
#
# Creates two worktrees, launches competing agents (superpowers vs ralph),
# runs quality gates on both, invokes an LLM judge, merges the winner,
# and records lessons.
#
# Usage:
#   mab-run.sh --design <doc> --prd <file> --project-root <dir> [options]
#
# Options:
#   --design <file>          Design document (required)
#   --prd <file>             PRD JSON file (required)
#   --project-root <dir>     Project root (required)
#   --quality-gate <cmd>     Quality gate command
#   --work-unit <desc>       Work unit description (for logging)
#   --batch-type <type>      Batch type: new-file|refactoring|integration|test-only
#   --dry-run                Print what would happen without executing
#   --init-data              Initialize data files and exit
#   --notify                 Send Telegram notifications
#   -h, --help               Show this help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared libs
if [[ -f "$SCRIPT_DIR/lib/run-plan-quality-gate.sh" ]]; then
    source "$SCRIPT_DIR/lib/run-plan-quality-gate.sh"
fi
if [[ -f "$SCRIPT_DIR/lib/run-plan-scoring.sh" ]]; then
    source "$SCRIPT_DIR/lib/run-plan-scoring.sh"
fi
if [[ -f "$SCRIPT_DIR/lib/run-plan-notify.sh" ]]; then
    source "$SCRIPT_DIR/lib/run-plan-notify.sh"
fi

# Ignore HUP/PIPE for background execution safety
trap '' HUP PIPE

usage() {
    cat <<'USAGE'
mab-run.sh — MAB execution orchestrator

Creates two worktrees with competing agents (superpowers vs ralph-wiggum),
runs quality gates, invokes an LLM judge, merges the winner, and records lessons.

Usage:
  mab-run.sh --design <doc> --prd <file> --project-root <dir> [options]

Options:
  --design <file>          Design document (required)
  --prd <file>             PRD JSON file (required)
  --project-root <dir>     Project root directory (required)
  --quality-gate <cmd>     Quality gate command (default: scripts/quality-gate.sh --project-root .)
  --work-unit <desc>       Work unit description for logging
  --batch-type <type>      new-file|refactoring|integration|test-only (default: auto-detect)
  --dry-run                Print actions without executing
  --init-data              Initialize data files (strategy-perf.json, mab-lessons.json) and exit
  --notify                 Send Telegram notifications
  -h, --help               Show this help
USAGE
}

# --- Defaults ---
DESIGN_DOC=""
PRD_FILE=""
PROJECT_ROOT=""
QUALITY_GATE_CMD="scripts/quality-gate.sh --project-root ."
WORK_UNIT=""
BATCH_TYPE=""
DRY_RUN=false
INIT_DATA=false
NOTIFY=false

# --- Argument parsing ---
parse_mmab_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --design) DESIGN_DOC="$2"; shift 2 ;;
            --prd) PRD_FILE="$2"; shift 2 ;;
            --project-root) PROJECT_ROOT="$2"; shift 2 ;;
            --quality-gate) QUALITY_GATE_CMD="$2"; shift 2 ;;
            --work-unit) WORK_UNIT="$2"; shift 2 ;;
            --batch-type) BATCH_TYPE="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --init-data) INIT_DATA=true; shift ;;
            --notify) NOTIFY=true; shift ;;
            *) echo "ERROR: Unknown option: $1" >&2; usage >&2; exit 1 ;;
        esac
    done

    if [[ -z "$PROJECT_ROOT" ]]; then
        echo "ERROR: --project-root required" >&2
        exit 1
    fi

    if [[ "$INIT_DATA" == true ]]; then
        init_data_files
        exit 0
    fi

    if [[ -z "$DESIGN_DOC" ]]; then
        echo "ERROR: --design required" >&2
        exit 1
    fi
    if [[ -z "$PRD_FILE" ]]; then
        echo "ERROR: --prd required" >&2
        exit 1
    fi
}

# --- Data file initialization ---
init_data_files() {
    mkdir -p "$PROJECT_ROOT/logs"

    # strategy-perf.json — win rates per strategy x batch type
    if [[ ! -f "$PROJECT_ROOT/logs/strategy-perf.json" ]]; then
        cat > "$PROJECT_ROOT/logs/strategy-perf.json" << 'JSON'
{
  "new-file": {
    "superpowers": {"wins": 0, "losses": 0, "total": 0},
    "ralph": {"wins": 0, "losses": 0, "total": 0}
  },
  "refactoring": {
    "superpowers": {"wins": 0, "losses": 0, "total": 0},
    "ralph": {"wins": 0, "losses": 0, "total": 0}
  },
  "integration": {
    "superpowers": {"wins": 0, "losses": 0, "total": 0},
    "ralph": {"wins": 0, "losses": 0, "total": 0}
  },
  "test-only": {
    "superpowers": {"wins": 0, "losses": 0, "total": 0},
    "ralph": {"wins": 0, "losses": 0, "total": 0}
  }
}
JSON
        echo "Created: $PROJECT_ROOT/logs/strategy-perf.json"
    fi

    # mab-lessons.json — accumulated MAB lessons
    if [[ ! -f "$PROJECT_ROOT/logs/mab-lessons.json" ]]; then
        echo "[]" > "$PROJECT_ROOT/logs/mab-lessons.json"
        echo "Created: $PROJECT_ROOT/logs/mab-lessons.json"
    fi
}

# --- Prompt assembly ---
# Reads a prompt template and substitutes placeholders with actual content
assemble_prompt() {
    local template_file="$1"
    local design_content prd_content map_content lessons_content

    design_content=$(cat "$DESIGN_DOC" 2>/dev/null || echo "(no design doc)")
    prd_content=$(cat "$PRD_FILE" 2>/dev/null || echo "(no PRD)")
    map_content=""
    if [[ -f "$PROJECT_ROOT/docs/ARCHITECTURE-MAP.json" ]]; then
        map_content=$(cat "$PROJECT_ROOT/docs/ARCHITECTURE-MAP.json")
    else
        map_content="(no architecture map — run architecture-map.sh to generate)"
    fi
    lessons_content="[]"
    if [[ -f "$PROJECT_ROOT/logs/mab-lessons.json" ]]; then
        lessons_content=$(cat "$PROJECT_ROOT/logs/mab-lessons.json")
    fi

    local prompt
    prompt=$(cat "$template_file")

    # Substitute placeholders
    prompt="${prompt//\{DESIGN_DOC\}/$design_content}"
    prompt="${prompt//\{PRD_CONTENT\}/$prd_content}"
    prompt="${prompt//\{ARCHITECTURE_MAP\}/$map_content}"
    prompt="${prompt//\{AB_LESSONS\}/$lessons_content}"
    prompt="${prompt//\{QUALITY_GATE_CMD\}/$QUALITY_GATE_CMD}"

    echo "$prompt"
}

# --- Worktree management ---
create_worktrees() {
    local timestamp
    timestamp=$(date +%s)
    WORKTREE_A="$PROJECT_ROOT/.claude/worktrees/mab-a-$timestamp"
    WORKTREE_B="$PROJECT_ROOT/.claude/worktrees/mab-b-$timestamp"
    BRANCH_A="mab-a-$timestamp"
    BRANCH_B="mab-b-$timestamp"

    git -C "$PROJECT_ROOT" worktree add "$WORKTREE_A" -b "$BRANCH_A" HEAD
    git -C "$PROJECT_ROOT" worktree add "$WORKTREE_B" -b "$BRANCH_B" HEAD

    echo "Created worktree A: $WORKTREE_A (branch: $BRANCH_A)"
    echo "Created worktree B: $WORKTREE_B (branch: $BRANCH_B)"
}

cleanup_worktrees() {
    echo "Cleaning up worktrees..."
    {
        git -C "$PROJECT_ROOT" worktree remove "$WORKTREE_A" 2>/dev/null
        git -C "$PROJECT_ROOT" branch -d "$BRANCH_A" 2>/dev/null
    } || echo "WARNING: Failed to cleanup worktree A" >&2
    {
        git -C "$PROJECT_ROOT" worktree remove "$WORKTREE_B" 2>/dev/null
        git -C "$PROJECT_ROOT" branch -d "$BRANCH_B" 2>/dev/null
    } || echo "WARNING: Failed to cleanup worktree B" >&2
}

# --- Agent execution ---
run_agent() {
    local worktree="$1" prompt="$2" label="$3"
    local log_file="$worktree/logs/mab-agent-$label.log"
    mkdir -p "$worktree/logs"

    echo "Launching agent $label in $worktree..."
    local exit_code=0
    CLAUDECODE='' claude -p "$prompt" \
        --allowedTools "Bash,Read,Write,Edit,Grep,Glob" \
        --permission-mode bypassPermissions \
        > "$log_file" 2>&1 || exit_code=$?

    echo "Agent $label finished (exit code: $exit_code)"
    return $exit_code
}

# --- Quality gate ---
run_agent_gate() {
    local worktree="$1" label="$2"
    local gate_exit=0
    local gate_output

    echo "Running quality gate for $label..."
    gate_output=$(cd "$worktree" && eval "$QUALITY_GATE_CMD" 2>&1) || gate_exit=$?

    echo "$gate_output" > "$worktree/logs/mab-gate-$label.log"

    if [[ $gate_exit -eq 0 ]]; then
        echo "  $label: PASSED"
    else
        echo "  $label: FAILED (exit $gate_exit)"
    fi

    return $gate_exit
}

# --- Judge ---
run_judge() {
    local judge_prompt
    local template="$SCRIPT_DIR/prompts/judge-agent.md"

    judge_prompt=$(assemble_prompt "$template")

    # Add diffs
    local diff_a diff_b
    diff_a=$(git -C "$WORKTREE_A" diff HEAD~..HEAD 2>/dev/null || git -C "$WORKTREE_A" diff HEAD 2>/dev/null || echo "(no diff)")
    diff_b=$(git -C "$WORKTREE_B" diff HEAD~..HEAD 2>/dev/null || git -C "$WORKTREE_B" diff HEAD 2>/dev/null || echo "(no diff)")

    # Add gate results
    local gate_a gate_b
    gate_a=$(cat "$WORKTREE_A/logs/mab-gate-agent_a.log" 2>/dev/null || echo "(no gate output)")
    gate_b=$(cat "$WORKTREE_B/logs/mab-gate-agent_b.log" 2>/dev/null || echo "(no gate output)")

    # Add scores
    local tests_a tests_b diff_size_a diff_size_b
    tests_a=$(cd "$WORKTREE_A" && grep -cE '(def test_|it\(|test\()' tests/**/* 2>/dev/null || echo "0")
    tests_b=$(cd "$WORKTREE_B" && grep -cE '(def test_|it\(|test\()' tests/**/* 2>/dev/null || echo "0")
    diff_size_a=$(git -C "$WORKTREE_A" diff --stat HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")
    diff_size_b=$(git -C "$WORKTREE_B" diff --stat HEAD 2>/dev/null | tail -1 | grep -oE '[0-9]+' | head -1 || echo "0")

    local gate_a_passed=0 gate_b_passed=0
    [[ -f "$WORKTREE_A/logs/mab-gate-agent_a.log" ]] && grep -q "PASSED\|passed\|OK" "$WORKTREE_A/logs/mab-gate-agent_a.log" && gate_a_passed=1
    [[ -f "$WORKTREE_B/logs/mab-gate-agent_b.log" ]] && grep -q "PASSED\|passed\|OK" "$WORKTREE_B/logs/mab-gate-agent_b.log" && gate_b_passed=1

    # Substitute remaining placeholders
    judge_prompt="${judge_prompt//\{DIFF_A\}/$diff_a}"
    judge_prompt="${judge_prompt//\{DIFF_B\}/$diff_b}"
    judge_prompt="${judge_prompt//\{GATE_A\}/$gate_a}"
    judge_prompt="${judge_prompt//\{GATE_B\}/$gate_b}"
    judge_prompt="${judge_prompt//\{GATE_A_PASSED\}/$gate_a_passed}"
    judge_prompt="${judge_prompt//\{GATE_B_PASSED\}/$gate_b_passed}"
    judge_prompt="${judge_prompt//\{TESTS_A\}/$tests_a}"
    judge_prompt="${judge_prompt//\{TESTS_B\}/$tests_b}"
    judge_prompt="${judge_prompt//\{DIFF_SIZE_A\}/$diff_size_a}"
    judge_prompt="${judge_prompt//\{DIFF_SIZE_B\}/$diff_size_b}"

    local judge_log="$PROJECT_ROOT/logs/mab-judge-$(date +%s).log"
    echo "Running judge agent..."
    local judge_output
    judge_output=$(CLAUDECODE='' claude -p "$judge_prompt" \
        --allowedTools "Read,Grep,Glob" \
        --permission-mode bypassPermissions 2>/dev/null) || true

    echo "$judge_output" > "$judge_log"

    # Extract JSON from judge output (may be wrapped in text)
    local judge_json
    judge_json=$(echo "$judge_output" | grep -o '{.*}' | head -1 || echo "{}")

    echo "$judge_json"
}

# --- Data updates ---
update_strategy_perf() {
    local winner="$1" batch_type="$2"
    local perf_file="$PROJECT_ROOT/logs/strategy-perf.json"

    [[ ! -f "$perf_file" ]] && init_data_files

    local winner_strategy loser_strategy
    if [[ "$winner" == "agent_a" ]]; then
        winner_strategy="superpowers"
        loser_strategy="ralph"
    else
        winner_strategy="ralph"
        loser_strategy="superpowers"
    fi

    # Ensure batch_type exists in perf file
    local bt="${batch_type:-unknown}"
    jq --arg bt "$bt" --arg ws "$winner_strategy" --arg ls "$loser_strategy" '
        .[$bt] //= {"superpowers": {"wins": 0, "losses": 0, "total": 0}, "ralph": {"wins": 0, "losses": 0, "total": 0}} |
        .[$bt][$ws].wins += 1 |
        .[$bt][$ws].total += 1 |
        .[$bt][$ls].losses += 1 |
        .[$bt][$ls].total += 1
    ' "$perf_file" > "$perf_file.tmp" && mv "$perf_file.tmp" "$perf_file"

    echo "Updated strategy-perf.json: $winner_strategy wins for $bt"
}

record_mab_lessons() {
    local judge_json="$1" batch_type="$2" work_unit="$3"
    local lessons_file="$PROJECT_ROOT/logs/mab-lessons.json"

    [[ ! -f "$lessons_file" ]] && echo "[]" > "$lessons_file"

    # Extract lessons array from judge output
    local lessons
    lessons=$(echo "$judge_json" | jq -r '.lessons // []' 2>/dev/null || echo "[]")

    local winner
    winner=$(echo "$judge_json" | jq -r '.winner // "unknown"' 2>/dev/null || echo "unknown")
    local failure_mode
    failure_mode=$(echo "$judge_json" | jq -r '.failure_mode // "unknown"' 2>/dev/null || echo "unknown")

    # Append each lesson
    echo "$lessons" | jq -c '.[]' 2>/dev/null | while IFS= read -r lesson; do
        jq --argjson lesson "$lesson" \
           --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
           --arg project "$(basename "$PROJECT_ROOT")" \
           --arg wu "$work_unit" \
           --arg bt "$batch_type" \
           --arg winner "$winner" \
           --arg fm "$failure_mode" \
           '. += [$lesson + {"timestamp": $ts, "project": $project, "work_unit": $wu, "batch_type": $bt, "winner": $winner, "failure_mode": $fm}]' \
           "$lessons_file" > "$lessons_file.tmp" && mv "$lessons_file.tmp" "$lessons_file"
    done

    echo "Recorded $(echo "$lessons" | jq 'length') lessons to mab-lessons.json"
}

# --- Merge winner ---
merge_winner() {
    local winner="$1"
    local winner_branch

    if [[ "$winner" == "agent_a" ]]; then
        winner_branch="$BRANCH_A"
    else
        winner_branch="$BRANCH_B"
    fi

    echo "Merging winner branch: $winner_branch"
    git -C "$PROJECT_ROOT" merge "$winner_branch" --no-edit
}

# --- Main orchestration ---
run_mab() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "=== DRY RUN ==="
        echo "Would create worktree A (superpowers agent)"
        echo "Would create worktree B (ralph agent)"
        echo "Would launch agent A with superpowers prompt"
        echo "Would launch agent B with ralph prompt"
        echo "Would run quality gate on both"
        echo "Would invoke judge agent"
        echo "Would merge winner and record lessons"
        return 0
    fi

    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  MAB Run — Competing Agents                        ║"
    echo "║  Design: $(basename "$DESIGN_DOC")"
    echo "║  PRD: $(basename "$PRD_FILE")"
    echo "║  Type: ${BATCH_TYPE:-auto}"
    echo "╚══════════════════════════════════════════════════════╝"

    # Initialize data files
    init_data_files

    # Generate architecture map
    if [[ -f "$SCRIPT_DIR/architecture-map.sh" ]]; then
        echo "Generating architecture map..."
        { "$SCRIPT_DIR/architecture-map.sh" --project-root "$PROJECT_ROOT" > /dev/null 2>&1; } \
            || echo "WARNING: architecture-map.sh failed (non-fatal)" >&2
    fi

    # Create worktrees
    create_worktrees

    # Assemble prompts
    local prompt_a prompt_b
    prompt_a=$(assemble_prompt "$SCRIPT_DIR/prompts/agent-a-superpowers.md")
    prompt_b=$(assemble_prompt "$SCRIPT_DIR/prompts/agent-b-ralph.md")

    # Launch agents in parallel
    echo ""
    echo "--- Launching agents in parallel ---"
    local pid_a pid_b exit_a=0 exit_b=0

    run_agent "$WORKTREE_A" "$prompt_a" "agent_a" &
    pid_a=$!

    run_agent "$WORKTREE_B" "$prompt_b" "agent_b" &
    pid_b=$!

    # Wait for both
    wait "$pid_a" || exit_a=$?
    wait "$pid_b" || exit_b=$?

    echo ""
    echo "Agent A exit: $exit_a"
    echo "Agent B exit: $exit_b"

    # Run quality gates
    echo ""
    echo "--- Quality Gates ---"
    local gate_a=0 gate_b=0
    run_agent_gate "$WORKTREE_A" "agent_a" || gate_a=$?
    run_agent_gate "$WORKTREE_B" "agent_b" || gate_b=$?

    # Invoke judge
    echo ""
    echo "--- Judge Evaluation ---"
    local judge_result
    judge_result=$(run_judge)

    local winner confidence reasoning
    winner=$(echo "$judge_result" | jq -r '.winner // "agent_a"' 2>/dev/null || echo "agent_a")
    confidence=$(echo "$judge_result" | jq -r '.confidence // "low"' 2>/dev/null || echo "low")
    reasoning=$(echo "$judge_result" | jq -r '.reasoning // "no reasoning provided"' 2>/dev/null || echo "no reasoning")

    echo ""
    echo "Winner: $winner (confidence: $confidence)"
    echo "Reasoning: $reasoning"

    # If neither passed gate, don't merge
    if [[ $gate_a -ne 0 && $gate_b -ne 0 ]]; then
        echo ""
        echo "WARNING: Neither agent passed quality gate. No merge performed."
        echo "Review worktrees manually:"
        echo "  Agent A: $WORKTREE_A"
        echo "  Agent B: $WORKTREE_B"

        # Still record lessons
        update_strategy_perf "$winner" "${BATCH_TYPE:-unknown}"
        record_mab_lessons "$judge_result" "${BATCH_TYPE:-unknown}" "${WORK_UNIT:-unnamed}"
        return 1
    fi

    # If only one passed, override judge
    if [[ $gate_a -eq 0 && $gate_b -ne 0 ]]; then
        echo "Overriding judge: only Agent A passed quality gate"
        winner="agent_a"
    elif [[ $gate_a -ne 0 && $gate_b -eq 0 ]]; then
        echo "Overriding judge: only Agent B passed quality gate"
        winner="agent_b"
    fi

    # Merge winner
    merge_winner "$winner"

    # Update data files
    update_strategy_perf "$winner" "${BATCH_TYPE:-unknown}"
    record_mab_lessons "$judge_result" "${BATCH_TYPE:-unknown}" "${WORK_UNIT:-unnamed}"

    # Log run
    local run_log="$PROJECT_ROOT/logs/mab-run-$(date +%s).json"
    jq -n \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg design "$(basename "$DESIGN_DOC")" \
        --arg prd "$(basename "$PRD_FILE")" \
        --arg winner "$winner" \
        --arg confidence "$confidence" \
        --arg reasoning "$reasoning" \
        --arg batch_type "${BATCH_TYPE:-unknown}" \
        --arg work_unit "${WORK_UNIT:-unnamed}" \
        --argjson judge "$judge_result" \
        '{
            "timestamp": $ts,
            "design": $design,
            "prd": $prd,
            "winner": $winner,
            "confidence": $confidence,
            "reasoning": $reasoning,
            "batch_type": $batch_type,
            "work_unit": $work_unit,
            "judge_output": $judge
        }' > "$run_log"

    echo "Run logged to: $run_log"

    # Cleanup
    cleanup_worktrees

    echo ""
    echo "MAB run complete. Winner ($winner) merged."
}

# --- Entry point ---
parse_mmab_args "$@"
run_mab
```

**Step 2: Make executable**

Run: `chmod +x scripts/mab-run.sh`

**Step 3: Run tests to verify they pass**

Run: `bash scripts/tests/test-mab-run.sh`
Expected: ALL PASSED

**Step 4: Commit**

```bash
git add scripts/mab-run.sh scripts/tests/test-mab-run.sh
git commit -m "feat: add mab-run.sh orchestrator with parallel agents, judge, and data tracking"
```

---

## Batch 3: Run-Plan Integration and MAB Context Injection

Wire `mab-run.sh` into `run-plan.sh` via an `--mab` flag, and inject MAB lessons into batch context.

### Task 9: Write failing tests for --mab flag in run-plan CLI

**Files:**
- Modify: `scripts/tests/test-run-plan-cli.sh`

**Step 1: Add test cases for --mab flag**

Append to the test file (before `report_results`):

```bash
# --- MAB mode tests ---
output=$("$SCRIPT" --help 2>&1)
assert_contains "help mentions ab flag" "--mab" "$output"

# --mab requires --design and --prd
output=$("$SCRIPT" docs/plans/example.md --mab 2>&1 || true)
assert_contains "ab requires design" "design" "$output"
```

**Step 2: Run tests to verify the new cases fail**

Run: `bash scripts/tests/test-run-plan-cli.sh 2>&1 | grep -E "FAIL|PASS" | tail -5`
Expected: New tests FAIL

### Task 10: Add --mab flag to run-plan.sh

**Files:**
- Modify: `scripts/run-plan.sh`

**Step 1: Add --mab, --design, --prd flags to argument parsing**

Add after the `--max-budget` case in `parse_args()`:

```bash
            --mab)
                MAB_MODE=true; shift
                ;;
            --design)
                MAB_DESIGN="$2"; shift 2
                ;;
            --prd-file)
                MAB_PRD="$2"; shift 2
                ;;
```

Add defaults after existing defaults block:

```bash
MAB_MODE=false
MAB_DESIGN=""
MAB_PRD=""
```

Add to `validate_args()` after the on-failure validation:

```bash
    # MAB mode validation
    if [[ "$MAB_MODE" == true ]]; then
        if [[ -z "$MAB_DESIGN" ]]; then
            echo "ERROR: --mab requires --design <file>" >&2
            exit 1
        fi
        if [[ -z "$MAB_PRD" ]]; then
            echo "ERROR: --mab requires --prd-file <file>" >&2
            exit 1
        fi
    fi
```

Add `--mab` to the usage text in the Options section:

```
  --mab                             Enable MAB competing agents mode
  --design <file>                  Design doc for MAB mode
  --prd-file <file>                PRD JSON for MAB mode
```

Add `ab` to the valid modes comment in the mode dispatch:

```bash
        ab)
            run_mode_mab
            ;;
```

And add the mode function:

```bash
run_mode_mab() {
    local mab_script="$SCRIPT_DIR/mab-run.sh"
    if [[ ! -f "$mab_script" ]]; then
        echo "ERROR: mab-run.sh not found at $mab_script" >&2
        exit 1
    fi

    local mab_args=(
        --design "$MAB_DESIGN"
        --prd "$MAB_PRD"
        --project-root "$WORKTREE"
        --quality-gate "$QUALITY_GATE_CMD"
    )

    if [[ "$NOTIFY" == true ]]; then
        mab_args+=(--notify)
    fi

    "$mab_script" "${mab_args[@]}"
}
```

**Step 2: Run CLI tests**

Run: `bash scripts/tests/test-run-plan-cli.sh`
Expected: ALL PASSED

### Task 11: Write failing tests for MAB context injection

**Files:**
- Modify: `scripts/tests/test-run-plan-context.sh`

**Step 1: Add tests for MAB lesson injection**

Append test cases (before `report_results`):

```bash
# --- MAB lessons injection ---
TMPDIR2=$(mktemp -d)
mkdir -p "$TMPDIR2/logs"
cat > "$TMPDIR2/logs/mab-lessons.json" << 'JSON'
[
    {
        "pattern": "Extract shared validation before per-type validators",
        "context": "new-file batches with 3+ validators",
        "recommendation": "Create shared contract first",
        "batch_type": "new-file",
        "winner": "agent_a"
    }
]
JSON

# The context should include MAB lessons when present
context=$(generate_batch_context "$PLAN_FILE" 2 "$TMPDIR2" 2>/dev/null || true)
assert_contains "includes AB lessons header" "MMAB Lessons" "$context"
assert_contains "includes lesson pattern" "shared validation" "$context"
rm -rf "$TMPDIR2"
```

**Step 2: Run to verify fail**

Run: `bash scripts/tests/test-run-plan-context.sh 2>&1 | tail -5`
Expected: New tests FAIL

### Task 12: Inject MAB lessons into batch context

**Files:**
- Modify: `scripts/lib/run-plan-context.sh`

**Step 1: Add MAB lesson injection to `generate_batch_context()`**

Add after the failure patterns section (around line 75), before the context_refs section:

```bash
    # 3. MAB lessons (if available)
    local mmab_lessons_file="$worktree/logs/mab-lessons.json"
    if [[ -f "$mmab_lessons_file" ]]; then
        local mab_count
        mab_count=$(jq 'length' "$mmab_lessons_file" 2>/dev/null || echo "0")
        if [[ "$mab_count" -gt 0 ]]; then
            local mab_section=""
            mab_section+=$'\n'"### MMAB Lessons (from previous competing agent runs)"$'\n'

            # Include most recent 5 lessons (most relevant)
            local mab_entries
            mab_entries=$(jq -r '.[-5:] | .[] | "- **\(.pattern)** (\(.context // "general")): \(.recommendation // "")"' \
                "$mmab_lessons_file" 2>/dev/null || true)

            if [[ -n "$mab_entries" ]]; then
                mab_section+="$mab_entries"$'\n'
                local mab_len=${#mab_section}
                if [[ $((chars_used + mab_len)) -lt $TOKEN_BUDGET_CHARS ]]; then
                    context+="$mab_section"
                    chars_used=$((chars_used + mab_len))
                fi
            fi
        fi
    fi
```

**Step 2: Run context tests**

Run: `bash scripts/tests/test-run-plan-context.sh`
Expected: ALL PASSED

**Step 3: Commit**

```bash
git add scripts/run-plan.sh scripts/lib/run-plan-context.sh scripts/tests/test-run-plan-cli.sh scripts/tests/test-run-plan-context.sh
git commit -m "feat: add --mab flag to run-plan.sh and inject MAB lessons into batch context"
```

---

## Batch 4: Community Sync and Lesson Promotion

Scripts for pulling community lessons upstream and auto-promoting recurring MAB lessons to `docs/lessons/`.

### Task 13: Write failing tests for pull-community-lessons.sh

**Files:**
- Create: `scripts/tests/test-pull-community-lessons.sh`

**Step 1: Write the test file**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SCRIPT="$SCRIPT_DIR/../pull-community-lessons.sh"

# --- CLI tests ---
assert_exit "help exits 0" 0 "$SCRIPT" --help

output=$("$SCRIPT" --help 2>&1)
assert_contains "help mentions upstream" "upstream" "$output"
assert_contains "help mentions lessons" "lessons" "$output"

# --- Dry-run on temp repo ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

cd "$TMPDIR"
git init -q
mkdir -p docs/lessons logs
echo "[]" > logs/strategy-perf.json
echo "# Lesson 1" > docs/lessons/0001-test.md
git add -A && git commit -q -m "init"

# Should handle missing upstream gracefully
output=$("$SCRIPT" --project-root "$TMPDIR" --dry-run 2>&1 || true)
assert_contains "dry-run reports status" "dry" "$output"

report_results
```

**Step 2: Run to verify fail**

Run: `bash scripts/tests/test-pull-community-lessons.sh 2>&1 | tail -5`
Expected: FAIL

### Task 14: Implement pull-community-lessons.sh

**Files:**
- Create: `scripts/pull-community-lessons.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail
# pull-community-lessons.sh — Sync lessons and strategy data from upstream
#
# Usage: pull-community-lessons.sh --project-root <dir> [--dry-run]
#
# Fetches latest lessons and strategy performance data from the upstream
# autonomous-coding-toolkit repo. New lessons are copied into docs/lessons/,
# and community strategy-perf.json is merged with local data.

usage() {
    cat <<'USAGE'
pull-community-lessons.sh — Pull community lessons from upstream

Fetches latest lessons and strategy performance data from the upstream
autonomous-coding-toolkit repo.

Usage:
  pull-community-lessons.sh --project-root <dir> [--dry-run]

Options:
  --project-root <dir>   Project root directory
  --upstream <remote>     Git remote name (default: upstream)
  --branch <branch>       Upstream branch (default: main)
  --dry-run               Show what would be synced without doing it
  -h, --help              Show this help
USAGE
}

PROJECT_ROOT=""
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="main"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --upstream) UPSTREAM_REMOTE="$2"; shift 2 ;;
        --branch) UPSTREAM_BRANCH="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "ERROR: --project-root required" >&2
    exit 1
fi

cd "$PROJECT_ROOT"

# Check if upstream remote exists
if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    echo "No '$UPSTREAM_REMOTE' remote configured."
    echo "Add one with: git remote add $UPSTREAM_REMOTE <repo-url>"
    if [[ "$DRY_RUN" == true ]]; then
        echo "(dry-run: would fetch from upstream)"
        exit 0
    fi
    exit 1
fi

echo "Fetching from $UPSTREAM_REMOTE/$UPSTREAM_BRANCH..."
if [[ "$DRY_RUN" == true ]]; then
    echo "(dry-run: would fetch $UPSTREAM_REMOTE)"
else
    git fetch "$UPSTREAM_REMOTE" "$UPSTREAM_BRANCH"
fi

# Sync lessons
echo ""
echo "--- Syncing lessons ---"
local_lessons=$(ls docs/lessons/*.md 2>/dev/null | wc -l || echo "0")
upstream_lessons=$(git ls-tree --name-only "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" -- docs/lessons/ 2>/dev/null || true)

new_count=0
while IFS= read -r lesson_file; do
    [[ -z "$lesson_file" ]] && continue
    local_path="$PROJECT_ROOT/$lesson_file"
    if [[ ! -f "$local_path" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "  Would copy: $lesson_file"
        else
            git show "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH:$lesson_file" > "$local_path"
            echo "  Copied: $lesson_file"
        fi
        new_count=$((new_count + 1))
    fi
done <<< "$upstream_lessons"

echo "New lessons: $new_count (local total: $local_lessons)"

# Sync strategy-perf.json (merge, don't replace)
echo ""
echo "--- Syncing strategy data ---"
local_perf="$PROJECT_ROOT/logs/strategy-perf.json"
upstream_perf_content=$(git show "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH:logs/strategy-perf.json" 2>/dev/null || echo "")

if [[ -n "$upstream_perf_content" && -f "$local_perf" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would merge upstream strategy-perf.json with local data"
    else
        # Merge: add upstream counts to local counts
        echo "$upstream_perf_content" | jq -s '
            .[0] as $local | .[1] as $upstream |
            $local | to_entries | map(
                .key as $type |
                .value | to_entries | map(
                    .key as $strat |
                    .value as $local_val |
                    ($upstream[$type][$strat] // {"wins": 0, "losses": 0, "total": 0}) as $up_val |
                    {
                        key: $strat,
                        value: {
                            "wins": ($local_val.wins + $up_val.wins),
                            "losses": ($local_val.losses + $up_val.losses),
                            "total": ($local_val.total + $up_val.total)
                        }
                    }
                ) | from_entries |
                {key: $type, value: .}
            ) | from_entries
        ' "$local_perf" - > "$local_perf.tmp" && mv "$local_perf.tmp" "$local_perf"
        echo "  Merged strategy performance data"
    fi
elif [[ -n "$upstream_perf_content" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would copy upstream strategy-perf.json (no local file)"
    else
        mkdir -p logs
        echo "$upstream_perf_content" > "$local_perf"
        echo "  Copied strategy-perf.json from upstream"
    fi
fi

echo ""
echo "Community sync complete."
```

**Step 2: Make executable**

Run: `chmod +x scripts/pull-community-lessons.sh`

**Step 3: Run tests**

Run: `bash scripts/tests/test-pull-community-lessons.sh`
Expected: ALL PASSED

### Task 15: Write failing tests for lesson promotion

**Files:**
- Create: `scripts/tests/test-promote-mab-lessons.sh`

**Step 1: Write test file**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

SCRIPT="$SCRIPT_DIR/../promote-mab-lessons.sh"

# --- CLI tests ---
assert_exit "help exits 0" 0 "$SCRIPT" --help

# --- Promotion threshold ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/docs/lessons" "$TMPDIR/logs"

# 2 occurrences — should NOT promote (threshold is 3)
cat > "$TMPDIR/logs/mab-lessons.json" << 'JSON'
[
    {"pattern": "Extract shared validation", "context": "new-file", "recommendation": "Create shared contract", "lesson_type": "semantic", "occurrences": 1},
    {"pattern": "Extract shared validation", "context": "new-file", "recommendation": "Create shared contract", "lesson_type": "semantic", "occurrences": 1}
]
JSON

output=$("$SCRIPT" --project-root "$TMPDIR" 2>&1)
assert_contains "reports no promotions" "0 lessons promoted" "$output"

# 3+ occurrences — should promote
cat > "$TMPDIR/logs/mab-lessons.json" << 'JSON'
[
    {"pattern": "Extract shared validation", "context": "new-file", "recommendation": "Create shared contract", "lesson_type": "semantic"},
    {"pattern": "Extract shared validation", "context": "new-file", "recommendation": "Create shared contract", "lesson_type": "semantic"},
    {"pattern": "Extract shared validation", "context": "new-file", "recommendation": "Create shared contract", "lesson_type": "semantic"}
]
JSON

# Need existing lessons to get next number
echo "---" > "$TMPDIR/docs/lessons/0060-existing.md"

output=$("$SCRIPT" --project-root "$TMPDIR" 2>&1)
assert_contains "reports promotion" "1 lessons promoted" "$output"

# Verify lesson file was created
promoted=$(ls "$TMPDIR/docs/lessons/"0061-*.md 2>/dev/null | wc -l)
assert_eq "created lesson file" "1" "$promoted"

# Verify promoted lesson has correct YAML frontmatter
content=$(cat "$TMPDIR/docs/lessons/"0061-*.md)
assert_contains "has title" "title:" "$content"
assert_contains "has category" "category:" "$content"
assert_contains "has source" "ab-run" "$content"

report_results
```

**Step 2: Run to verify fail**

Run: `bash scripts/tests/test-promote-mab-lessons.sh 2>&1 | tail -5`
Expected: FAIL

### Task 16: Implement promote-mab-lessons.sh

**Files:**
- Create: `scripts/promote-mab-lessons.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail
# promote-mab-lessons.sh — Auto-promote recurring MAB lessons to docs/lessons/
#
# When the same pattern appears 3+ times in mab-lessons.json, create a proper
# lesson file in docs/lessons/ so it becomes part of the permanent lesson corpus.
#
# Usage: promote-mab-lessons.sh --project-root <dir>

PROMOTION_THRESHOLD=3

usage() {
    cat <<'USAGE'
promote-mab-lessons.sh — Promote recurring MAB lessons to docs/lessons/

When the same pattern appears 3+ times in logs/mab-lessons.json, creates a
proper lesson file in docs/lessons/ with YAML frontmatter.

Usage:
  promote-mab-lessons.sh --project-root <dir>

Options:
  --project-root <dir>    Project root directory
  --threshold N           Promotion threshold (default: 3)
  --dry-run               Show what would be promoted
  -h, --help              Show this help
USAGE
}

PROJECT_ROOT=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        --threshold) PROMOTION_THRESHOLD="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "ERROR: --project-root required" >&2
    exit 1
fi

lessons_file="$PROJECT_ROOT/logs/mab-lessons.json"
if [[ ! -f "$lessons_file" ]]; then
    echo "No mab-lessons.json found. 0 lessons promoted."
    exit 0
fi

lessons_dir="$PROJECT_ROOT/docs/lessons"
mkdir -p "$lessons_dir"

# Find the next lesson number
next_num=$(ls "$lessons_dir"/*.md 2>/dev/null | \
    grep -oE '[0-9]{4}' | sort -n | tail -1 || echo "0000")
next_num=$((10#$next_num + 1))

# Group lessons by pattern and count occurrences
# Use jq to group, count, and filter by threshold
promotable=$(jq --argjson threshold "$PROMOTION_THRESHOLD" '
    group_by(.pattern) |
    map(select(length >= $threshold)) |
    map({
        pattern: .[0].pattern,
        context: .[0].context,
        recommendation: .[0].recommendation,
        lesson_type: (.[0].lesson_type // "semantic"),
        count: length
    })
' "$lessons_file" 2>/dev/null || echo "[]")

promoted_count=0

echo "$promotable" | jq -c '.[]' 2>/dev/null | while IFS= read -r entry; do
    pattern=$(echo "$entry" | jq -r '.pattern')
    context=$(echo "$entry" | jq -r '.context // "general"')
    recommendation=$(echo "$entry" | jq -r '.recommendation // ""')
    lesson_type=$(echo "$entry" | jq -r '.lesson_type // "semantic"')
    count=$(echo "$entry" | jq -r '.count')

    # Generate slug from pattern
    slug=$(echo "$pattern" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-' | head -c 40)

    lesson_file="$lessons_dir/$(printf '%04d' "$next_num")-$slug.md"

    # Check if a lesson with similar slug already exists
    if ls "$lessons_dir"/*"$slug"*.md >/dev/null 2>&1; then
        echo "  Skipping (already exists): $pattern"
        continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
        echo "  Would promote: $pattern ($count occurrences)"
    else
        cat > "$lesson_file" << LESSON
---
title: "$pattern"
severity: warning
category: mab-learned
source: mab-run
applies_to: all
lesson_type: $lesson_type
occurrences: $count
---

# $pattern

## Context

$context

## Recommendation

$recommendation

## Source

Auto-promoted from MAB run lessons after $count occurrences.
LESSON
        echo "  Promoted: $lesson_file"
    fi

    next_num=$((next_num + 1))
    promoted_count=$((promoted_count + 1))
done

echo "$promoted_count lessons promoted."
```

**Step 2: Make executable**

Run: `chmod +x scripts/promote-mab-lessons.sh`

**Step 3: Run tests**

Run: `bash scripts/tests/test-promote-mab-lessons.sh`
Expected: ALL PASSED

**Step 4: Commit**

```bash
git add scripts/pull-community-lessons.sh scripts/promote-mab-lessons.sh scripts/tests/test-pull-community-lessons.sh scripts/tests/test-promote-mab-lessons.sh
git commit -m "feat: add community lesson sync and auto-promotion for MAB lessons"
```

---

## Batch 5: Documentation and ARCHITECTURE.md Updates

Update project documentation to cover the Multi-Armed Bandit system.

### Task 17: Update ARCHITECTURE.md

**Files:**
- Modify: `docs/ARCHITECTURE.md`

**Step 1: Add Multi-Armed Bandit System section**

Append a new section to `docs/ARCHITECTURE.md`:

```markdown
## Multi-Armed Bandit System

Competing autonomous agents execute the same brief using different methodologies (superpowers skill chain vs ralph-wiggum iteration loop). An LLM judge evaluates both and extracts lessons that compound over time.

### Architecture

```
PHASE 1 — HUMAN + SINGLE AGENT (shared)
  1. Brainstorm → approved design doc
  2. PRD → machine-verifiable acceptance criteria
  3. Architecture map generated (architecture-map.sh)

PHASE 2 — PLANNER AGENT (LLM)
  Reads: design doc, PRD, architecture map, strategy-perf.json
  Decides per work unit: MAB or single? Which strategy? Unit size?

PHASE 3 — MAB EXECUTION (parallel worktrees)
  Agent A (superpowers): writes own plan, TDD, batch-by-batch
  Agent B (ralph): iterates until PRD criteria pass

PHASE 4 — JUDGE AGENT (LLM)
  Reads: both diffs, design doc, PRD, architecture map, lesson history
  Outputs: winner, bidirectional lessons, strategy update, failure mode

PHASE 5 — MERGE + LEARN
  Merge winner, log lessons, update strategy data, promote patterns
```

### Data Files

| File | Purpose |
|------|---------|
| `logs/mab-lessons.json` | Accumulated MAB lessons (patterns, recommendations) |
| `logs/strategy-perf.json` | Strategy win rates per batch type |
| `logs/mab-run-<timestamp>.json` | Per-run log (judge output, winner, reasoning) |
| `docs/ARCHITECTURE-MAP.json` | Auto-generated module dependency graph |

### Scripts

| Script | Purpose |
|--------|---------|
| `scripts/mab-run.sh` | MAB execution orchestrator |
| `scripts/architecture-map.sh` | Module dependency graph generator |
| `scripts/pull-community-lessons.sh` | Sync lessons from upstream |
| `scripts/promote-mab-lessons.sh` | Auto-promote recurring lessons |
| `scripts/prompts/planner-agent.md` | Planner routing prompt |
| `scripts/prompts/judge-agent.md` | Judge evaluation prompt |
| `scripts/prompts/agent-a-superpowers.md` | Superpowers agent instructions |
| `scripts/prompts/agent-b-ralph.md` | Ralph agent instructions |

### Lesson Lifecycle

1. Judge extracts lesson → `logs/mab-lessons.json`
2. Pattern recurs 3+ times → auto-promoted to `docs/lessons/NNNN-*.md`
3. Promoted lesson → enforced by `lesson-check.sh` (syntactic) or `lesson-scanner` (semantic)
4. User runs `/submit-lesson` → PR to upstream for community

### Strategy Learning

The planner agent reads `logs/strategy-perf.json` to route work units:
- **>70% win rate, 10+ data points** → route to winning strategy (exploit)
- **Uncertain or insufficient data** → MAB run (explore)
- **Error-prone type** → MAB run (gather more data)

New users start with community baseline data via `pull-community-lessons.sh`.
```

**Step 2: Verify update**

Run: `grep -c "Multi-Armed Bandit System" docs/ARCHITECTURE.md`
Expected: 1

### Task 18: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add Multi-Armed Bandit system to the skill chain table**

In the "The Skill Chain" table, add a new row after `4d. Execute (loop)`:

```
| 4e. Execute (MAB) | `scripts/mab-run.sh` | Parallel competing agents with LLM judge |
```

**Step 2: Add to the Scripts section of Directory Layout**

Add to the scripts section:

```
├── mab-run.sh                    # MAB competing agents orchestrator
├── architecture-map.sh          # Module dependency graph generator
├── pull-community-lessons.sh    # Community lesson sync from upstream
├── promote-mab-lessons.sh        # Auto-promote recurring MAB lessons
```

**Step 3: Add to Data Files section under State & Persistence**

Add entries:

```
- **`logs/mab-lessons.json`** — accumulated MAB lessons from competing agent runs.
- **`logs/strategy-perf.json`** — strategy win rates per batch type (feeds planner decisions).
- **`logs/mab-run-<timestamp>.json`** — per-run judge output, winner, and reasoning.
- **`docs/ARCHITECTURE-MAP.json`** — auto-generated module dependency graph.
```

**Step 4: Commit**

```bash
git add docs/ARCHITECTURE.md CLAUDE.md
git commit -m "docs: add Multi-Armed Bandit system to ARCHITECTURE.md and CLAUDE.md"
```

---

## Batch 6: Integration Wiring and Final Verification

Wire all components together, run the full test suite, and verify end-to-end.

### Task 19: Add ab-run tests to run-all-tests.sh

**Files:**
- Modify: `scripts/tests/run-all-tests.sh`

**Step 1: Add new test files**

Add to the test file list in `run-all-tests.sh`:

```bash
test-architecture-map.sh
test-mab-run.sh
test-pull-community-lessons.sh
test-promote-mab-lessons.sh
```

**Step 2: Run the full test suite**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

### Task 20: Add architecture-map.sh to quality-gate.sh (optional step)

**Files:**
- Modify: `scripts/quality-gate.sh` (if appropriate — only if the project uses the architecture map)

**Step 1: Check if architecture map generation should be part of the gate**

The architecture map is informational, not a gate. Do NOT add it to quality-gate.sh. It should be run explicitly or as part of `mab-run.sh`.

Verify this is correct by checking the quality gate doesn't reference it:

Run: `grep -c "architecture-map" scripts/quality-gate.sh || echo "0"`
Expected: 0 (not referenced)

### Task 21: Verify all new scripts are executable

**Step 1: Check permissions**

Run: `ls -la scripts/mab-run.sh scripts/architecture-map.sh scripts/pull-community-lessons.sh scripts/promote-mab-lessons.sh | awk '{print $1, $NF}'`
Expected: All show `-rwxr-xr-x` or similar executable permissions

### Task 22: Run the full test suite

**Step 1: Run all tests**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED with no regressions

### Task 23: Verify mab-run.sh dry-run works end-to-end

**Step 1: Create a temp project and test dry-run**

Run:
```bash
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init -q
mkdir -p tasks docs
echo '{"tasks":[{"id":1,"description":"test","criterion":"exit 0"}]}' > tasks/prd.json
echo "# Test Design" > docs/design.md
git add -A && git commit -q -m "init"
scripts/mab-run.sh --design docs/design.md --prd tasks/prd.json --project-root "$TMPDIR" --dry-run
cd -
rm -rf "$TMPDIR"
```
Expected: Shows dry-run output mentioning worktree creation and agent launch

### Task 24: Verify architecture-map.sh on the toolkit itself

**Step 1: Generate map for this project**

Run: `scripts/architecture-map.sh --project-root .`
Expected: Produces JSON with `modules` array containing project modules (scripts/lib/*, etc.)

### Task 25: Final commit

```bash
git add scripts/tests/run-all-tests.sh
git commit -m "feat: wire Multi-Armed Bandit system into test suite and verify integration"
```

### Task 26: Run quality gate

Run: `scripts/quality-gate.sh --project-root .`
Expected: PASSED

---

## Quality Gates

Between each batch, run:

```bash
# Full quality gate
scripts/quality-gate.sh --project-root .

# Or manually:
bash scripts/tests/run-all-tests.sh          # All tests pass
scripts/lesson-check.sh scripts/*.sh          # No lesson violations
git diff --name-only                          # All changes committed
```

## Summary

| Batch | Focus | New Files | Tests |
|-------|-------|-----------|-------|
| 1 | Agent prompts + architecture-map.sh | 6 | test-architecture-map.sh |
| 2 | mab-run.sh orchestrator | 2 | test-mab-run.sh |
| 3 | run-plan --mab flag + context injection | 0 (modifications) | test-run-plan-cli.sh, test-run-plan-context.sh (modified) |
| 4 | Community sync + lesson promotion | 4 | test-pull-community-lessons.sh, test-promote-mab-lessons.sh |
| 5 | Documentation updates | 0 (modifications) | — |
| 6 | Integration wiring + verification | 0 (modifications) | run-all-tests.sh (modified) |
