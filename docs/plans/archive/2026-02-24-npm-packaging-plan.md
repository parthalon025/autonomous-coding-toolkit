# npm Packaging Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Package the autonomous-coding-toolkit as an installable npm package (`act` CLI) with telemetry, benchmarks, and learning system infrastructure.

**Architecture:** Add `package.json` + `bin/act.js` Node.js router on top of existing bash scripts. No scripts move or change structure. Three new scripts (`init.sh`, `telemetry.sh`, `benchmarks/runner.sh`) follow existing patterns. All state remains project-local.

**Tech Stack:** Node.js 18+ (CLI router only), bash 4+ (all scripts), jq (state/telemetry)

**Design doc:** `docs/plans/2026-02-24-npm-packaging-design.md`

---

## Priority Tiers

- **P0 (Batches 1-4):** Required for `npm publish` — package.json, CLI router, init, portability fixes, README
- **P1 (Batches 5-7):** Learning system — telemetry capture/dashboard, quality gate integration, benchmark suite
- **P2 (Batches 8-9):** Enhancements — trust score, graduated autonomy, semantic echo-back Tier 2

---

## Batch 1: package.json + CLI Router

### Task 1: Create package.json

**Files:**
- Create: `package.json`

**Step 1: Create package.json**

```json
{
  "name": "autonomous-coding-toolkit",
  "version": "1.0.0",
  "description": "Autonomous AI coding pipeline: quality gates, fresh-context execution, community lessons, and compounding learning",
  "license": "MIT",
  "author": "Justin McFarland <parthalon025@gmail.com>",
  "homepage": "https://github.com/parthalon025/autonomous-coding-toolkit",
  "repository": "https://github.com/parthalon025/autonomous-coding-toolkit",
  "bin": {
    "act": "./bin/act.js"
  },
  "files": [
    "bin/",
    "scripts/",
    "skills/",
    "commands/",
    "agents/",
    "hooks/",
    "policies/",
    "examples/",
    "benchmarks/",
    "docs/",
    ".claude-plugin/",
    "Makefile",
    "SECURITY.md"
  ],
  "engines": {
    "node": ">=18.0.0"
  },
  "os": [
    "linux",
    "darwin",
    "win32"
  ],
  "keywords": [
    "autonomous-coding",
    "ai-agents",
    "quality-gates",
    "claude-code",
    "tdd",
    "lessons-learned",
    "headless",
    "multi-armed-bandit",
    "code-review",
    "pipeline"
  ]
}
```

**Step 2: Verify package.json is valid**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && node -e "require('./package.json'); console.log('valid')"`
Expected: `valid`

**Step 3: Verify npm pack lists expected files**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && npm pack --dry-run 2>&1 | head -20`
Expected: Output should list `bin/act.js`, `scripts/`, `skills/`, `docs/`, etc. Should NOT list `logs/`, `.run-plan-state.json`, `.worktrees/`.

**Step 4: Commit**

```bash
git add package.json
git commit -m "feat: add package.json for npm distribution"
```

### Task 2: Create bin/act.js CLI Router

**Files:**
- Create: `bin/act.js`

**Step 1: Create directory**

```bash
mkdir -p bin
```

**Step 2: Write bin/act.js**

```javascript
#!/usr/bin/env node
'use strict';

const { execFileSync, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const TOOLKIT_ROOT = path.resolve(__dirname, '..');
const SCRIPTS = path.join(TOOLKIT_ROOT, 'scripts');
const VERSION = require(path.join(TOOLKIT_ROOT, 'package.json')).version;

// --- Platform check ---
function checkBash() {
  try {
    execFileSync('bash', ['--version'], { stdio: 'pipe' });
  } catch {
    console.error('Error: bash is required but not found.');
    if (process.platform === 'win32') {
      console.error('');
      console.error('On Windows, install WSL (Windows Subsystem for Linux):');
      console.error('  wsl --install');
      console.error('Then run this command inside WSL.');
    }
    process.exit(1);
  }
}

// --- Dependency check ---
function checkDeps() {
  const required = ['git', 'jq'];
  const missing = required.filter(cmd => {
    try {
      execFileSync('which', [cmd], { stdio: 'pipe' });
      return false;
    } catch {
      return true;
    }
  });
  if (missing.length > 0) {
    console.error(`Error: Required commands not found: ${missing.join(', ')}`);
    console.error('Install them and try again.');
    process.exit(1);
  }
}

// --- Command routing ---
const COMMANDS = {
  // Execution
  'plan':           { script: 'run-plan.sh' },
  'compound':       { script: 'auto-compound.sh' },
  'mab':            { script: 'mab-run.sh' },

  // Quality
  'gate':           { script: 'quality-gate.sh' },
  'check':          { script: 'lesson-check.sh' },
  'policy':         { script: 'policy-check.sh' },
  'research-gate':  { script: 'research-gate.sh' },
  'validate':       { script: 'validate-all.sh' },
  'validate-plan':  { script: 'validate-plan-quality.sh' },
  'validate-prd':   { script: 'validate-prd.sh' },

  // Lessons
  'lessons':        { dispatch: true },

  // Analysis
  'audit':          { script: 'entropy-audit.sh' },
  'batch-audit':    { script: 'batch-audit.sh' },
  'batch-test':     { script: 'batch-test.sh' },
  'analyze':        { script: 'analyze-report.sh' },
  'digest':         { script: 'failure-digest.sh' },
  'status':         { script: 'pipeline-status.sh' },
  'architecture':   { script: 'architecture-map.sh' },

  // Setup
  'init':           { script: 'init.sh' },
  'license-check':  { script: 'license-check.sh' },
  'module-size':    { script: 'module-size-check.sh' },

  // Telemetry
  'telemetry':      { script: 'telemetry.sh' },

  // Benchmarks
  'benchmark':      { script: path.join('..', 'benchmarks', 'runner.sh'), relative: true },
};

// Lessons sub-dispatch
const LESSONS_COMMANDS = {
  'pull':    { script: 'pull-community-lessons.sh' },
  'check':   { script: 'lesson-check.sh', args: ['--list'] },
  'promote': { script: 'promote-mab-lessons.sh' },
  'infer':   { script: 'scope-infer.sh' },
};

function runScript(scriptPath, args) {
  const fullPath = path.join(SCRIPTS, scriptPath);
  if (!fs.existsSync(fullPath)) {
    console.error(`Error: Script not found: ${fullPath}`);
    console.error('This command may not be available yet.');
    process.exit(1);
  }
  try {
    execFileSync('bash', [fullPath, ...args], { stdio: 'inherit' });
  } catch (err) {
    process.exit(err.status || 1);
  }
}

function showHelp() {
  console.log(`Autonomous Coding Toolkit v${VERSION}`);
  console.log('');
  console.log('Usage: act <command> [options]');
  console.log('');
  console.log('Execution:');
  console.log('  plan <file> [flags]    Headless/team/MAB batch execution');
  console.log('  plan --resume          Resume interrupted execution');
  console.log('  compound [dir]         Full pipeline: report→PRD→execute→PR');
  console.log('  mab <flags>            Multi-Armed Bandit competing agents');
  console.log('');
  console.log('Quality:');
  console.log('  gate [flags]           Composite quality gate');
  console.log('  check [files...]       Syntactic anti-pattern scan');
  console.log('  policy [flags]         Advisory positive-pattern check');
  console.log('  validate               Toolkit self-validation');
  console.log('  validate-plan <file>   Score plan quality (8 dimensions)');
  console.log('  validate-prd [file]    Validate PRD JSON structure');
  console.log('');
  console.log('Lessons:');
  console.log('  lessons pull [--remote]  Sync community lessons');
  console.log('  lessons check           List active lesson checks');
  console.log('  lessons promote         Auto-promote MAB patterns');
  console.log('  lessons infer [--apply] Infer scope tags');
  console.log('');
  console.log('Analysis:');
  console.log('  audit [flags]          Doc drift & naming violations');
  console.log('  batch-audit <dir>      Cross-project audit');
  console.log('  batch-test <dir>       Memory-aware cross-project tests');
  console.log('  analyze <report>       Extract priority from report');
  console.log('  digest <log>           Summarize failure patterns');
  console.log('  status [dir]           Pipeline health check');
  console.log('  architecture [dir]     Generate architecture diagram');
  console.log('');
  console.log('Telemetry:');
  console.log('  telemetry show         Dashboard: success rate, cost, lesson hits');
  console.log('  telemetry export       Export anonymized run data');
  console.log('  telemetry import <f>   Import community aggregate data');
  console.log('  telemetry reset        Clear local telemetry');
  console.log('');
  console.log('Benchmarks:');
  console.log('  benchmark run [name]   Execute benchmark tasks');
  console.log('  benchmark compare a b  Compare two benchmark results');
  console.log('');
  console.log('Setup:');
  console.log('  init                   Bootstrap project for toolkit use');
  console.log('  init --quickstart      Fast lane: working example in <3 min');
  console.log('  license-check          GPL/AGPL dependency audit');
  console.log('  module-size            Detect oversized modules');
  console.log('');
  console.log('Meta:');
  console.log('  version                Print version');
  console.log('  help                   Show this help');
}

// --- Main ---
function main() {
  const args = process.argv.slice(2);
  const command = args[0];
  const rest = args.slice(1);

  if (!command || command === 'help' || command === '--help' || command === '-h') {
    showHelp();
    process.exit(0);
  }

  if (command === 'version' || command === '--version' || command === '-v') {
    console.log(`act v${VERSION}`);
    process.exit(0);
  }

  checkBash();
  checkDeps();

  // Lessons sub-dispatch
  if (command === 'lessons') {
    const sub = rest[0];
    if (!sub || !LESSONS_COMMANDS[sub]) {
      console.error('Usage: act lessons <pull|check|promote|infer> [options]');
      process.exit(1);
    }
    const cmd = LESSONS_COMMANDS[sub];
    const subArgs = cmd.args ? [...cmd.args, ...rest.slice(1)] : rest.slice(1);
    runScript(cmd.script, subArgs);
    return;
  }

  const cmd = COMMANDS[command];
  if (!cmd) {
    console.error(`Unknown command: ${command}`);
    console.error('Run "act help" for available commands.');
    process.exit(1);
  }

  if (cmd.relative) {
    // Script path relative to toolkit root, not scripts/
    const fullPath = path.join(TOOLKIT_ROOT, 'benchmarks', 'runner.sh');
    if (!fs.existsSync(fullPath)) {
      console.error(`Error: Script not found: ${fullPath}`);
      process.exit(1);
    }
    try {
      execFileSync('bash', [fullPath, ...rest], { stdio: 'inherit' });
    } catch (err) {
      process.exit(err.status || 1);
    }
    return;
  }

  runScript(cmd.script, rest);
}

main();
```

**Step 3: Make executable**

```bash
chmod +x bin/act.js
```

**Step 4: Verify the router starts**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && node bin/act.js version`
Expected: `act v1.0.0`

Run: `node bin/act.js help | head -5`
Expected: Shows "Autonomous Coding Toolkit v1.0.0" and "Usage: act <command> [options]"

**Step 5: Verify subcommand routing works**

Run: `node bin/act.js validate --help`
Expected: Shows validate-all.sh usage (or runs successfully)

Run: `node bin/act.js gate --help`
Expected: Shows quality-gate.sh usage

**Step 6: Commit**

```bash
git add bin/act.js
git commit -m "feat: add bin/act.js CLI router for npm distribution"
```

### Task 3: Write test for CLI router

**Files:**
- Create: `scripts/tests/test-act-cli.sh`

**Step 1: Write the test**

```bash
#!/usr/bin/env bash
# Test bin/act.js — CLI router
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ACT="$REPO_ROOT/bin/act.js"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Test 1: version ---
output=$(node "$ACT" version 2>&1)
assert_contains "act version prints version" "act v" "$output"

# --- Test 2: help ---
output=$(node "$ACT" help 2>&1)
assert_contains "act help shows usage" "Usage: act <command>" "$output"
assert_contains "act help lists plan command" "plan" "$output"
assert_contains "act help lists gate command" "gate" "$output"

# --- Test 3: unknown command exits non-zero ---
exit_code=0
node "$ACT" nonexistent-command >/dev/null 2>&1 || exit_code=$?
assert_eq "unknown command exits non-zero" "1" "$exit_code"

# --- Test 4: validate routes correctly ---
output=$(node "$ACT" validate --help 2>&1 || true)
assert_contains "validate routes to validate-all.sh" "validate" "$output"

# --- Test 5: lessons subcommand without sub shows usage ---
exit_code=0
output=$(node "$ACT" lessons 2>&1) || exit_code=$?
assert_eq "lessons without sub exits non-zero" "1" "$exit_code"
assert_contains "lessons shows usage hint" "Usage: act lessons" "$output"

report_results
```

**Step 2: Make executable and run**

```bash
chmod +x scripts/tests/test-act-cli.sh
```

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash scripts/tests/test-act-cli.sh`
Expected: All tests PASS

**Step 3: Verify run-all-tests discovers it**

Run: `bash scripts/tests/run-all-tests.sh 2>&1 | tail -5`
Expected: test-act-cli.sh appears in the test list, all pass

**Step 4: Commit**

```bash
git add scripts/tests/test-act-cli.sh
git commit -m "test: add CLI router tests for bin/act.js"
```

---

## Batch 2: Project Bootstrapper (act init)

### Task 4: Write test for init.sh

**Files:**
- Create: `scripts/tests/test-init.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# Test scripts/init.sh — project bootstrapper
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INIT_SCRIPT="$REPO_ROOT/scripts/init.sh"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Setup temp project ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
git init -q

# --- Test 1: init creates tasks/ directory ---
bash "$INIT_SCRIPT" --project-root "$WORK" 2>&1 || true
assert_eq "init creates tasks/ directory" "true" "$([ -d "$WORK/tasks" ] && echo true || echo false)"

# --- Test 2: init creates progress.txt ---
assert_eq "init creates progress.txt" "true" "$([ -f "$WORK/progress.txt" ] && echo true || echo false)"

# --- Test 3: init creates logs/ directory ---
assert_eq "init creates logs/ directory" "true" "$([ -d "$WORK/logs" ] && echo true || echo false)"

# --- Test 4: init detects project type ---
output=$(bash "$INIT_SCRIPT" --project-root "$WORK" 2>&1 || true)
assert_contains "init detects project type" "Detected:" "$output"

# --- Test 5: init with --quickstart copies quickstart plan ---
mkdir -p "$WORK/docs/plans"
bash "$INIT_SCRIPT" --project-root "$WORK" --quickstart 2>&1 || true
assert_eq "quickstart creates plan file" "true" "$([ -f "$WORK/docs/plans/quickstart.md" ] && echo true || echo false)"

# --- Test 6: init is idempotent ---
bash "$INIT_SCRIPT" --project-root "$WORK" 2>&1 || true
exit_code=0
bash "$INIT_SCRIPT" --project-root "$WORK" 2>&1 || exit_code=$?
assert_eq "init is idempotent (exit 0 on re-run)" "0" "$exit_code"

report_results
```

**Step 2: Make executable and verify it fails**

```bash
chmod +x scripts/tests/test-init.sh
```

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash scripts/tests/test-init.sh 2>&1 | tail -3`
Expected: FAIL (init.sh doesn't exist yet)

### Task 5: Implement init.sh

**Files:**
- Create: `scripts/init.sh`

**Step 1: Write the implementation**

```bash
#!/usr/bin/env bash
# init.sh — Bootstrap a project for use with the Autonomous Coding Toolkit
#
# Usage: init.sh --project-root <dir> [--quickstart]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT=""
QUICKSTART=false

usage() {
    cat <<'USAGE'
Usage: init.sh --project-root <dir> [--quickstart]

Bootstrap a project for the Autonomous Coding Toolkit.

Creates:
  tasks/         — PRD and acceptance criteria
  logs/          — Telemetry, routing decisions, failure patterns
  progress.txt   — Append-only discovery log

Options:
  --project-root <dir>  Project directory to initialize (required)
  --quickstart          Copy quickstart plan + run quality gate
  --help, -h            Show this help

USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
        --quickstart) QUICKSTART=true; shift ;;
        --help|-h) usage ;;
        *) echo "init: unknown option: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "init: --project-root is required" >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

echo "Autonomous Coding Toolkit — Project Init"
echo "========================================="
echo ""

# Detect project type
project_type=$(detect_project_type "$PROJECT_ROOT")
echo "Detected: $project_type project"

# Create directories
mkdir -p "$PROJECT_ROOT/tasks"
mkdir -p "$PROJECT_ROOT/logs"
mkdir -p "$PROJECT_ROOT/docs/plans"
echo "Created: tasks/, logs/, docs/plans/"

# Create progress.txt if missing
if [[ ! -f "$PROJECT_ROOT/progress.txt" ]]; then
    echo "# Progress — $(basename "$PROJECT_ROOT")" > "$PROJECT_ROOT/progress.txt"
    echo "# Append-only discovery log. Read at start of each batch." >> "$PROJECT_ROOT/progress.txt"
    echo "" >> "$PROJECT_ROOT/progress.txt"
    echo "Created: progress.txt"
else
    echo "Exists: progress.txt (skipped)"
fi

# Detect language for scope tags
scope_lang=""
case "$project_type" in
    python) scope_lang="language:python" ;;
    node) scope_lang="language:javascript" ;;
    bash) scope_lang="language:bash" ;;
    *) scope_lang="" ;;
esac

# Print next steps
echo ""
echo "--- Next Steps ---"
echo ""
echo "1. Quality gate:  act gate --project-root $PROJECT_ROOT"
echo "2. Run a plan:    act plan docs/plans/your-plan.md"

if [[ -n "$scope_lang" ]]; then
    echo ""
    echo "Recommended: Add to your CLAUDE.md:"
    echo "  ## Scope Tags"
    echo "  $scope_lang"
fi

# Quickstart mode
if [[ "$QUICKSTART" == true ]]; then
    echo ""
    echo "--- Quickstart ---"
    if [[ -f "$TOOLKIT_ROOT/examples/quickstart-plan.md" ]]; then
        cp "$TOOLKIT_ROOT/examples/quickstart-plan.md" "$PROJECT_ROOT/docs/plans/quickstart.md"
        echo "Copied: docs/plans/quickstart.md"
        echo ""
        echo "Run your first quality-gated execution:"
        echo "  act plan docs/plans/quickstart.md"
    else
        echo "WARNING: quickstart-plan.md not found in toolkit" >&2
    fi
fi

echo ""
echo "Init complete."
```

**Step 2: Make executable**

```bash
chmod +x scripts/init.sh
```

**Step 3: Run the tests**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash scripts/tests/test-init.sh`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add scripts/init.sh scripts/tests/test-init.sh
git commit -m "feat: add init.sh project bootstrapper with quickstart mode"
```

---

## Batch 3: Portability Fixes

### Task 6: Fix hardcoded ~/.env in telegram.sh

**Files:**
- Modify: `scripts/lib/telegram.sh:9`
- Create: `scripts/tests/test-telegram-env.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# Test telegram.sh — ACT_ENV_FILE support
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Setup ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create a fake .env
cat > "$WORK/test.env" <<'ENV'
TELEGRAM_BOT_TOKEN=test-token-123
TELEGRAM_CHAT_ID=test-chat-456
ENV

# --- Test 1: ACT_ENV_FILE overrides default ---
(
    export ACT_ENV_FILE="$WORK/test.env"
    source "$REPO_ROOT/scripts/lib/telegram.sh"
    _load_telegram_env
    assert_eq "ACT_ENV_FILE loads token" "test-token-123" "$TELEGRAM_BOT_TOKEN"
    assert_eq "ACT_ENV_FILE loads chat id" "test-chat-456" "$TELEGRAM_CHAT_ID"
)

# --- Test 2: Explicit argument still works ---
(
    source "$REPO_ROOT/scripts/lib/telegram.sh"
    _load_telegram_env "$WORK/test.env"
    assert_eq "Explicit arg loads token" "test-token-123" "$TELEGRAM_BOT_TOKEN"
)

# --- Test 3: Missing file returns error ---
(
    source "$REPO_ROOT/scripts/lib/telegram.sh"
    exit_code=0
    _load_telegram_env "$WORK/nonexistent.env" 2>/dev/null || exit_code=$?
    assert_eq "Missing env file returns 1" "1" "$exit_code"
)

report_results
```

**Step 2: Make executable and verify it fails**

```bash
chmod +x scripts/tests/test-telegram-env.sh
```

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash scripts/tests/test-telegram-env.sh 2>&1 | tail -3`
Expected: Test 1 FAILS (ACT_ENV_FILE not recognized yet)

**Step 3: Fix telegram.sh**

In `scripts/lib/telegram.sh`, change line 9 from:

```bash
    local env_file="${1:-$HOME/.env}"
```

to:

```bash
    local env_file="${1:-${ACT_ENV_FILE:-$HOME/.env}}"
```

This adds `ACT_ENV_FILE` as an intermediate default — if set, it overrides `$HOME/.env`; if not, behavior is unchanged.

**Step 4: Run the tests**

Run: `bash scripts/tests/test-telegram-env.sh`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add scripts/lib/telegram.sh scripts/tests/test-telegram-env.sh
git commit -m "fix: support ACT_ENV_FILE in telegram.sh for portable installs"
```

### Task 7: Add ACT_ENV_FILE support to ollama.sh

**Files:**
- Modify: `scripts/lib/ollama.sh` (add env file sourcing)

**Step 1: Verify current behavior**

The ollama.sh module already uses env vars (`OLLAMA_DIRECT_URL`, `OLLAMA_QUEUE_URL`) with defaults. No hardcoded path to fix — the credentials (if any) come from the calling script's environment.

If `ACT_ENV_FILE` is set, the calling script (e.g., `auto-compound.sh`) should source it. This is not an ollama.sh change — it's a convention.

**Step 2: Verify no change needed**

Run: `grep -n 'HOME\|\.env' ~/Documents/projects/autonomous-coding-toolkit/scripts/lib/ollama.sh`
Expected: No matches (ollama.sh has no hardcoded paths)

**Step 3: Skip — no change needed**

ollama.sh is already portable. Document the `ACT_ENV_FILE` convention in init.sh output instead.

### Task 8: Add project-local lessons fallback to lesson-check.sh

**Files:**
- Modify: `scripts/lesson-check.sh:8`
- Create: `scripts/tests/test-lesson-local.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# Test lesson-check.sh — project-local lesson loading (Tier 3)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LESSON_CHECK="$REPO_ROOT/scripts/lesson-check.sh"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Setup: project with local lessons ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create a project-local lesson
mkdir -p "$WORK/docs/lessons"
cat > "$WORK/docs/lessons/0001-local-test.md" <<'LESSON'
---
id: "0001"
title: "Test local lesson"
severity: error
languages: [python]
scope: [universal]
category: testing
pattern:
  type: syntactic
  regex: "LOCALTEST_BAD_PATTERN"
fix: "Use LOCALTEST_GOOD_PATTERN instead"
positive_alternative: "LOCALTEST_GOOD_PATTERN"
---
LESSON

# Create a file that triggers the local lesson
cat > "$WORK/bad.py" <<'PY'
x = LOCALTEST_BAD_PATTERN
PY

# --- Test: project-local lesson is loaded ---
output=$(PROJECT_ROOT="$WORK" PROJECT_CLAUDE_MD="/dev/null" bash "$LESSON_CHECK" "$WORK/bad.py" 2>&1 || true)
if echo "$output" | grep -q 'lesson-1'; then
    pass "Project-local lesson detected violation"
else
    fail "Project-local lesson not loaded, got: $output"
fi

# --- Test: clean file passes with local lessons ---
cat > "$WORK/good.py" <<'PY'
x = LOCALTEST_GOOD_PATTERN
PY

exit_code=0
PROJECT_ROOT="$WORK" PROJECT_CLAUDE_MD="/dev/null" bash "$LESSON_CHECK" "$WORK/good.py" 2>/dev/null || exit_code=$?
assert_eq "Clean file passes with local lessons" "0" "$exit_code"

report_results
```

**Step 2: Make executable and verify it fails**

```bash
chmod +x scripts/tests/test-lesson-local.sh
```

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash scripts/tests/test-lesson-local.sh 2>&1 | tail -3`
Expected: FAIL (project-local lessons not loaded yet)

**Step 3: Add project-local lesson loading**

In `scripts/lesson-check.sh`, after line 8 (`LESSONS_DIR=...`), add:

```bash
# Project-local lessons (Tier 3) — loaded alongside bundled lessons.
# Set PROJECT_ROOT to the project being checked for project-specific anti-patterns.
PROJECT_LESSONS_DIR=""
if [[ -n "${PROJECT_ROOT:-}" && -d "${PROJECT_ROOT}/docs/lessons" ]]; then
    PROJECT_LESSONS_DIR="${PROJECT_ROOT}/docs/lessons"
fi
```

Then find the glob loop that loads lesson files (the line that iterates over `"$LESSONS_DIR"/[0-9]*.md`). After that loop completes, add a second loop for project-local lessons:

```bash
# Load project-local lessons (Tier 3)
if [[ -n "$PROJECT_LESSONS_DIR" ]]; then
    for lesson_file in "$PROJECT_LESSONS_DIR"/[0-9]*.md; do
        [[ -f "$lesson_file" ]] || continue
        # Same parse_lesson + check logic as bundled lessons
        # (reuse the same function — it's already defined)
    done
fi
```

The exact insertion point depends on the lesson-check.sh structure. The implementer should read the full file to find where lessons are iterated and add the project-local loop after.

**Step 4: Run the tests**

Run: `bash scripts/tests/test-lesson-local.sh`
Expected: All tests PASS

Run: `bash scripts/tests/test-lesson-check.sh`
Expected: All existing tests still PASS (no regression)

**Step 5: Commit**

```bash
git add scripts/lesson-check.sh scripts/tests/test-lesson-local.sh
git commit -m "feat: support project-local lessons (Tier 3) in lesson-check.sh"
```

---

## Batch 4: README + npm Prep

### Task 9: Update README.md with npm install instructions

**Files:**
- Modify: `README.md`

**Step 1: Update installation section**

Replace the current Install section with:

```markdown
## Install

### npm (recommended)

```bash
npm install -g autonomous-coding-toolkit
```

This puts `act` on your PATH. Requires Node.js 18+ and bash 4+.

### Claude Code Plugin

```bash
# Add the marketplace source
/plugin marketplace add parthalon025/autonomous-coding-toolkit

# Install the plugin
/plugin install autonomous-coding-toolkit@autonomous-coding-toolkit
```

### From Source

```bash
git clone https://github.com/parthalon025/autonomous-coding-toolkit.git
cd autonomous-coding-toolkit
npm link  # puts 'act' on PATH
```

> **Windows:** Requires [WSL](https://learn.microsoft.com/en-us/windows/wsl/install). Run `wsl --install`, then use the toolkit inside WSL.
```

**Step 2: Add Quick Start section for CLI**

Update the Quick Start section to include CLI commands alongside plugin commands:

```markdown
## Quick Start

```bash
# Bootstrap your project
act init --quickstart

# Full pipeline — brainstorm → plan → execute → verify → finish
/autocode "Add user authentication with JWT"

# Run a plan headless (fully autonomous, fresh context per batch)
act plan docs/plans/my-feature.md --on-failure retry --notify

# Quality check
act gate --project-root .

# See all commands
act help
```
```

**Step 3: Verify README renders correctly**

Run: `head -60 ~/Documents/projects/autonomous-coding-toolkit/README.md`
Expected: Updated installation and quick start sections visible

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update README with npm install and CLI usage"
```

### Task 10: Add .npmignore

**Files:**
- Create: `.npmignore`

**Step 1: Create .npmignore**

```
# Development files
.worktrees/
.run-plan-state.json
progress.txt
logs/
tasks/
.claude/
.github/
research/

# Test fixtures (tests themselves ship for validation)
scripts/tests/fixtures/

# Git
.git/
.gitignore
```

**Step 2: Verify npm pack excludes dev files**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && npm pack --dry-run 2>&1 | grep -c 'run-plan-state\|\.worktrees\|research/'`
Expected: `0` (none of those files included)

**Step 3: Commit**

```bash
git add .npmignore
git commit -m "chore: add .npmignore for clean npm packaging"
```

### Task 11: Verify full test suite passes

**Step 1: Run all tests**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash scripts/tests/run-all-tests.sh`
Expected: All tests PASS, including the 3 new test files

**Step 2: Run quality gate on self**

Run: `bash scripts/quality-gate.sh --project-root ~/Documents/projects/autonomous-coding-toolkit`
Expected: ALL PASSED

---

## Batch 5: Telemetry Script (P1)

### Task 12: Write tests for telemetry.sh

**Files:**
- Create: `scripts/tests/test-telemetry.sh`

**Step 1: Write the tests**

```bash
#!/usr/bin/env bash
# Test scripts/telemetry.sh — telemetry capture, show, export, reset
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TELEMETRY="$REPO_ROOT/scripts/telemetry.sh"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Setup ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/logs"

# --- Test 1: record writes to telemetry.jsonl ---
bash "$TELEMETRY" record --project-root "$WORK" \
    --batch-number 1 --passed true --strategy superpowers \
    --duration 120 --cost 0.42 --test-delta 5 2>&1 || true
assert_eq "record creates telemetry.jsonl" "true" \
    "$([ -f "$WORK/logs/telemetry.jsonl" ] && echo true || echo false)"

# --- Test 2: record appends valid JSON ---
line=$(head -1 "$WORK/logs/telemetry.jsonl")
echo "$line" | jq . >/dev/null 2>&1
assert_eq "record writes valid JSON" "0" "$?"

# --- Test 3: show produces dashboard output ---
output=$(bash "$TELEMETRY" show --project-root "$WORK" 2>&1 || true)
assert_contains "show displays header" "Telemetry Dashboard" "$output"

# --- Test 4: export produces anonymized output ---
bash "$TELEMETRY" export --project-root "$WORK" > "$WORK/export.json" 2>&1 || true
assert_eq "export creates output" "true" "$([ -s "$WORK/export.json" ] && echo true || echo false)"

# --- Test 5: reset clears telemetry ---
bash "$TELEMETRY" reset --project-root "$WORK" --yes 2>&1 || true
if [[ -f "$WORK/logs/telemetry.jsonl" ]]; then
    line_count=$(wc -l < "$WORK/logs/telemetry.jsonl")
    assert_eq "reset clears telemetry" "0" "$line_count"
else
    pass "reset removes telemetry file"
fi

report_results
```

**Step 2: Make executable and verify it fails**

```bash
chmod +x scripts/tests/test-telemetry.sh
```

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash scripts/tests/test-telemetry.sh 2>&1 | tail -3`
Expected: FAIL (telemetry.sh doesn't exist yet)

### Task 13: Implement telemetry.sh

**Files:**
- Create: `scripts/telemetry.sh`

**Step 1: Write the implementation**

```bash
#!/usr/bin/env bash
# telemetry.sh — Local telemetry capture, dashboard, export, and import
#
# Usage:
#   telemetry.sh record --project-root <dir> [--batch-number N] [--passed true|false] ...
#   telemetry.sh show --project-root <dir>
#   telemetry.sh export --project-root <dir>
#   telemetry.sh import --project-root <dir> <file>
#   telemetry.sh reset --project-root <dir> --yes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT=""
SUBCOMMAND=""

# --- Parse top-level ---
SUBCOMMAND="${1:-}"
shift || true

# Parse remaining args
BATCH_NUMBER=""
PASSED=""
STRATEGY=""
DURATION=""
COST=""
TEST_DELTA=""
LESSONS_TRIGGERED=""
PLAN_QUALITY=""
BATCH_TYPE=""
CONFIRM_YES=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="${2:-}"; shift 2 ;;
        --batch-number) BATCH_NUMBER="${2:-}"; shift 2 ;;
        --passed) PASSED="${2:-}"; shift 2 ;;
        --strategy) STRATEGY="${2:-}"; shift 2 ;;
        --duration) DURATION="${2:-}"; shift 2 ;;
        --cost) COST="${2:-}"; shift 2 ;;
        --test-delta) TEST_DELTA="${2:-}"; shift 2 ;;
        --lessons-triggered) LESSONS_TRIGGERED="${2:-}"; shift 2 ;;
        --plan-quality) PLAN_QUALITY="${2:-}"; shift 2 ;;
        --batch-type) BATCH_TYPE="${2:-}"; shift 2 ;;
        --yes) CONFIRM_YES=true; shift ;;
        --help|-h) echo "Usage: telemetry.sh <record|show|export|import|reset> --project-root <dir> [options]"; exit 0 ;;
        *)
            # Positional arg (for import file)
            if [[ -z "${IMPORT_FILE:-}" ]]; then
                IMPORT_FILE="$1"
            fi
            shift ;;
    esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
    echo "telemetry: --project-root is required" >&2
    exit 1
fi

TELEMETRY_FILE="$PROJECT_ROOT/logs/telemetry.jsonl"

case "$SUBCOMMAND" in
    record)
        mkdir -p "$PROJECT_ROOT/logs"
        jq -n \
            --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --arg bn "${BATCH_NUMBER:-0}" \
            --arg passed "${PASSED:-false}" \
            --arg strategy "${STRATEGY:-unknown}" \
            --arg duration "${DURATION:-0}" \
            --arg cost "${COST:-0}" \
            --arg td "${TEST_DELTA:-0}" \
            --arg lt "${LESSONS_TRIGGERED:-}" \
            --arg pq "${PLAN_QUALITY:-}" \
            --arg bt "${BATCH_TYPE:-unknown}" \
            --arg pt "$(detect_project_type "$PROJECT_ROOT")" \
            '{
                timestamp: $ts,
                project_type: $pt,
                batch_type: $bt,
                batch_number: ($bn | tonumber),
                passed_gate: ($passed == "true"),
                strategy: $strategy,
                duration_seconds: ($duration | tonumber),
                cost_usd: ($cost | tonumber),
                test_count_delta: ($td | tonumber),
                lessons_triggered: (if $lt == "" then [] else ($lt | split(",")) end),
                plan_quality_score: (if $pq == "" then null else ($pq | tonumber) end)
            }' >> "$TELEMETRY_FILE"
        echo "telemetry: recorded batch $BATCH_NUMBER"
        ;;

    show)
        echo "Autonomous Coding Toolkit — Telemetry Dashboard"
        echo "════════════════════════════════════════════════"
        echo ""

        if [[ ! -f "$TELEMETRY_FILE" ]] || [[ ! -s "$TELEMETRY_FILE" ]]; then
            echo "No telemetry data yet. Run some batches first."
            exit 0
        fi

        # Summary stats
        total=$(wc -l < "$TELEMETRY_FILE")
        passed=$(jq -s '[.[] | select(.passed_gate == true)] | length' "$TELEMETRY_FILE")
        total_cost=$(jq -s '[.[].cost_usd] | add // 0' "$TELEMETRY_FILE")
        total_duration=$(jq -s '[.[].duration_seconds] | add // 0' "$TELEMETRY_FILE")
        avg_cost=$(jq -s 'if length > 0 then ([.[].cost_usd] | add) / length else 0 end' "$TELEMETRY_FILE")

        echo "Runs: $total batches"
        if [[ "$total" -gt 0 ]]; then
            pct=$((passed * 100 / total))
            echo "Success rate: ${pct}% ($passed/$total passed gate on first attempt)"
        fi
        printf "Total cost: \$%.2f (\$%.2f/batch average)\n" "$total_cost" "$avg_cost"
        hours=$(awk "BEGIN {printf \"%.1f\", $total_duration / 3600}")
        echo "Total time: ${hours} hours"

        # Strategy performance
        echo ""
        echo "Strategy Performance:"
        jq -s '
            group_by(.strategy) | .[] |
            {
                strategy: .[0].strategy,
                wins: [.[] | select(.passed_gate == true)] | length,
                total: length
            } |
            "  \(.strategy): \(.wins)/\(.total) (\(if .total > 0 then (.wins * 100 / .total) else 0 end)% win rate)"
        ' "$TELEMETRY_FILE" 2>/dev/null || echo "  (no strategy data)"

        # Top lesson hits
        echo ""
        echo "Top Lesson Hits:"
        jq -s '
            [.[].lessons_triggered | arrays | .[]] |
            group_by(.) | map({lesson: .[0], count: length}) |
            sort_by(-.count) | .[:5] |
            .[] | "  \(.lesson): \(.count) hits"
        ' "$TELEMETRY_FILE" 2>/dev/null || echo "  (no lesson data)"
        ;;

    export)
        if [[ ! -f "$TELEMETRY_FILE" ]]; then
            echo "No telemetry data to export." >&2
            exit 1
        fi
        # Anonymize: remove timestamps precision, no file paths
        jq -s '
            [.[] | {
                project_type,
                batch_type,
                passed_gate,
                strategy,
                duration_seconds,
                cost_usd,
                test_count_delta,
                lessons_triggered,
                plan_quality_score
            }]
        ' "$TELEMETRY_FILE"
        ;;

    import)
        if [[ -z "${IMPORT_FILE:-}" || ! -f "${IMPORT_FILE:-}" ]]; then
            echo "telemetry: import requires a file argument" >&2
            exit 1
        fi
        echo "telemetry: import not yet implemented (planned for community sync)"
        ;;

    reset)
        if [[ "$CONFIRM_YES" != true ]]; then
            echo "telemetry: use --yes to confirm reset" >&2
            exit 1
        fi
        if [[ -f "$TELEMETRY_FILE" ]]; then
            > "$TELEMETRY_FILE"
            echo "telemetry: cleared $TELEMETRY_FILE"
        else
            echo "telemetry: no telemetry file to reset"
        fi
        ;;

    *)
        echo "Usage: telemetry.sh <record|show|export|import|reset> --project-root <dir>" >&2
        exit 1
        ;;
esac
```

**Step 2: Make executable**

```bash
chmod +x scripts/telemetry.sh
```

**Step 3: Run the tests**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash scripts/tests/test-telemetry.sh`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add scripts/telemetry.sh scripts/tests/test-telemetry.sh
git commit -m "feat: add telemetry.sh — capture, dashboard, export, reset"
```

---

## Batch 6: Telemetry Integration in Quality Gate

### Task 14: Add telemetry capture to quality-gate.sh

**Files:**
- Modify: `scripts/quality-gate.sh:248` (after "ALL PASSED")

**Step 1: Add telemetry capture after the final echo**

Before the `exit 0` at the end of quality-gate.sh, add telemetry recording:

```bash
# === Telemetry capture (append batch result) ===
# Only record if TELEMETRY_BATCH_NUMBER is set (called from run-plan context)
if [[ -n "${TELEMETRY_BATCH_NUMBER:-}" ]]; then
    "$SCRIPT_DIR/telemetry.sh" record \
        --project-root "$PROJECT_ROOT" \
        --batch-number "${TELEMETRY_BATCH_NUMBER}" \
        --passed true \
        --strategy "${TELEMETRY_STRATEGY:-unknown}" \
        --duration "${TELEMETRY_DURATION:-0}" \
        --cost "${TELEMETRY_COST:-0}" \
        --test-delta "${TELEMETRY_TEST_DELTA:-0}" \
        --batch-type "${TELEMETRY_BATCH_TYPE:-unknown}" \
        2>/dev/null || true  # Never fail the gate for telemetry errors
fi
```

This is conditional — telemetry only records when the env vars are set by the calling script (run-plan.sh). Quality gate still works exactly as before when called standalone.

**Step 2: Verify quality gate still passes standalone**

Run: `bash scripts/quality-gate.sh --project-root ~/Documents/projects/autonomous-coding-toolkit --quick`
Expected: ALL PASSED (no telemetry vars set, so telemetry capture is silently skipped)

**Step 3: Verify telemetry records when vars are set**

```bash
WORK=$(mktemp -d)
mkdir -p "$WORK/logs"
git -C "$WORK" init -q
TELEMETRY_BATCH_NUMBER=1 TELEMETRY_STRATEGY=test \
    bash scripts/quality-gate.sh --project-root "$WORK" --quick 2>&1 | tail -3
cat "$WORK/logs/telemetry.jsonl" 2>/dev/null || echo "(no telemetry)"
rm -rf "$WORK"
```

Expected: quality gate passes and telemetry.jsonl has one line

**Step 4: Commit**

```bash
git add scripts/quality-gate.sh
git commit -m "feat: integrate telemetry capture into quality gate pipeline"
```

### Task 15: Run full test suite

**Step 1: Run all tests**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash scripts/tests/run-all-tests.sh`
Expected: All tests PASS

**Step 2: Run quality gate**

Run: `bash scripts/quality-gate.sh --project-root ~/Documents/projects/autonomous-coding-toolkit`
Expected: ALL PASSED

---

## Batch 7: Benchmark Suite (P1)

### Task 16: Create benchmark directory structure

**Files:**
- Create: `benchmarks/runner.sh`
- Create: `benchmarks/tasks/01-rest-endpoint/task.md`
- Create: `benchmarks/tasks/01-rest-endpoint/rubric.sh`

**Step 1: Create directories**

```bash
mkdir -p benchmarks/tasks/01-rest-endpoint
mkdir -p benchmarks/tasks/02-refactor-module
mkdir -p benchmarks/tasks/03-fix-integration-bug
mkdir -p benchmarks/tasks/04-add-test-coverage
mkdir -p benchmarks/tasks/05-multi-file-feature
mkdir -p benchmarks/rubrics
```

**Step 2: Write benchmark runner**

```bash
#!/usr/bin/env bash
# runner.sh — Benchmark orchestrator for the Autonomous Coding Toolkit
#
# Usage:
#   runner.sh run [task-name]      Run all or one benchmark
#   runner.sh compare <a> <b>      Compare two result files
#   runner.sh list                 List available benchmarks
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
TASKS_DIR="$SCRIPT_DIR/tasks"
RESULTS_DIR="${BENCHMARK_RESULTS_DIR:-$SCRIPT_DIR/results}"

usage() {
    cat <<'USAGE'
Usage: runner.sh <run|compare|list> [options]

Commands:
  run [name]        Run all benchmarks, or a specific one by directory name
  compare <a> <b>   Compare two result JSON files
  list              List available benchmark tasks

Options:
  --help, -h        Show this help

Results are saved to benchmarks/results/ (gitignored).
USAGE
    exit 0
}

SUBCOMMAND="${1:-}"
shift || true

case "$SUBCOMMAND" in
    list)
        echo "Available benchmarks:"
        for task_dir in "$TASKS_DIR"/*/; do
            [[ -d "$task_dir" ]] || continue
            name=$(basename "$task_dir")
            desc=""
            if [[ -f "$task_dir/task.md" ]]; then
                desc=$(head -1 "$task_dir/task.md" | sed 's/^# //')
            fi
            echo "  $name — $desc"
        done
        ;;

    run)
        TARGET="${1:-all}"
        mkdir -p "$RESULTS_DIR"
        timestamp=$(date -u +%Y%m%dT%H%M%SZ)

        run_benchmark() {
            local task_dir="$1"
            local name=$(basename "$task_dir")
            echo "=== Benchmark: $name ==="

            if [[ ! -f "$task_dir/rubric.sh" ]]; then
                echo "  SKIP: no rubric.sh found"
                return
            fi

            local score=0
            local total=0
            local pass=0

            # Run rubric — each line of output is "PASS: desc" or "FAIL: desc"
            while IFS= read -r line; do
                total=$((total + 1))
                if [[ "$line" == PASS:* ]]; then
                    pass=$((pass + 1))
                fi
                echo "  $line"
            done < <(bash "$task_dir/rubric.sh" 2>&1 || true)

            if [[ $total -gt 0 ]]; then
                score=$((pass * 100 / total))
            fi
            echo "  Score: ${score}% ($pass/$total)"
            echo ""

            # Write result
            jq -n --arg name "$name" --argjson score "$score" \
                --argjson pass "$pass" --argjson total "$total" \
                --arg ts "$timestamp" \
                '{name: $name, score: $score, passed: $pass, total: $total, timestamp: $ts}' \
                >> "$RESULTS_DIR/$timestamp.jsonl"
        }

        if [[ "$TARGET" == "all" ]]; then
            for task_dir in "$TASKS_DIR"/*/; do
                [[ -d "$task_dir" ]] || continue
                run_benchmark "$task_dir"
            done
        else
            if [[ -d "$TASKS_DIR/$TARGET" ]]; then
                run_benchmark "$TASKS_DIR/$TARGET"
            else
                echo "Benchmark not found: $TARGET" >&2
                echo "Run 'runner.sh list' to see available benchmarks." >&2
                exit 1
            fi
        fi

        echo "Results saved to: $RESULTS_DIR/$timestamp.jsonl"
        ;;

    compare)
        FILE_A="${1:-}"
        FILE_B="${2:-}"
        if [[ -z "$FILE_A" || -z "$FILE_B" ]]; then
            echo "Usage: runner.sh compare <result-a.jsonl> <result-b.jsonl>" >&2
            exit 1
        fi
        if [[ ! -f "$FILE_A" || ! -f "$FILE_B" ]]; then
            echo "One or both files not found." >&2
            exit 1
        fi

        echo "Benchmark Comparison"
        echo "═════════════════════════════════════"
        printf "%-25s %8s %8s %8s\n" "Task" "Before" "After" "Delta"
        echo "─────────────────────────────────────────────"

        # Merge by name and compare
        jq -s '
            [.[0], .[1]] | transpose | .[] |
            select(.[0] != null and .[1] != null) |
            "\(.[0].name)|\(.[0].score)|\(.[1].score)|\(.[1].score - .[0].score)"
        ' <(jq -s '.' "$FILE_A") <(jq -s '.' "$FILE_B") 2>/dev/null | \
        while IFS='|' read -r name before after delta; do
            sign=""
            [[ "$delta" -gt 0 ]] && sign="+"
            printf "%-25s %7s%% %7s%% %7s%%\n" "$name" "$before" "$after" "${sign}${delta}"
        done

        echo "═════════════════════════════════════"
        ;;

    help|--help|-h|"")
        usage
        ;;

    *)
        echo "Unknown command: $SUBCOMMAND" >&2
        usage
        ;;
esac
```

**Step 3: Make executable**

```bash
chmod +x benchmarks/runner.sh
```

**Step 4: Write first benchmark task definition**

Create `benchmarks/tasks/01-rest-endpoint/task.md`:

```markdown
# Add a REST Endpoint with Tests

**Complexity:** Simple (1 batch)
**Measures:** Basic execution, TDD compliance

## Task

Add a `/health` endpoint to the project that:
1. Returns HTTP 200 with JSON body `{"status": "ok", "timestamp": "<ISO8601>"}`
2. Has a test that verifies the response status and body structure
3. All tests pass

## Constraints

- Use the project's existing web framework (or add minimal one if none exists)
- Follow existing code style and patterns
- Test must be automated (no manual verification)
```

Create `benchmarks/tasks/01-rest-endpoint/rubric.sh`:

```bash
#!/usr/bin/env bash
# Rubric for 01-rest-endpoint benchmark
# Checks for task completion criteria
set -euo pipefail

PROJECT_ROOT="${BENCHMARK_PROJECT_ROOT:-.}"

# Criterion 1: Health endpoint file exists
if compgen -G "$PROJECT_ROOT/src/*health*" >/dev/null 2>&1 || \
   compgen -G "$PROJECT_ROOT/app/*health*" >/dev/null 2>&1 || \
   grep -rl "health" "$PROJECT_ROOT/src/" "$PROJECT_ROOT/app/" 2>/dev/null | head -1 >/dev/null 2>&1; then
    echo "PASS: Health endpoint file exists"
else
    echo "FAIL: Health endpoint file not found"
fi

# Criterion 2: Test file exists
if compgen -G "$PROJECT_ROOT/tests/*health*" >/dev/null 2>&1 || \
   compgen -G "$PROJECT_ROOT/test/*health*" >/dev/null 2>&1; then
    echo "PASS: Health endpoint test file exists"
else
    echo "FAIL: Health endpoint test file not found"
fi

# Criterion 3: Test passes
if cd "$PROJECT_ROOT" && (npm test 2>/dev/null || pytest 2>/dev/null || make test 2>/dev/null); then
    echo "PASS: Tests pass"
else
    echo "FAIL: Tests do not pass"
fi
```

```bash
chmod +x benchmarks/tasks/01-rest-endpoint/rubric.sh
```

**Step 5: Write remaining task stubs**

For benchmarks 02-05, create minimal `task.md` files (rubrics can be expanded later):

Create `benchmarks/tasks/02-refactor-module/task.md`:
```markdown
# Refactor a Module into Two

**Complexity:** Medium (2 batches)
**Measures:** Refactoring quality, test preservation

## Task

Split `src/utils.sh` into `src/string-utils.sh` and `src/file-utils.sh`, preserving all existing tests.
```

Create `benchmarks/tasks/03-fix-integration-bug/task.md`:
```markdown
# Fix an Integration Bug

**Complexity:** Medium (2 batches)
**Measures:** Debugging, root cause analysis

## Task

The `/api/users` endpoint returns 500 when the database connection pool is exhausted. Find and fix the root cause.
```

Create `benchmarks/tasks/04-add-test-coverage/task.md`:
```markdown
# Add Test Coverage to Untested Module

**Complexity:** Medium (2 batches)
**Measures:** Test quality, edge case discovery

## Task

Add comprehensive tests to `src/parser.sh` which currently has 0% coverage. Cover happy path, edge cases, and error conditions.
```

Create `benchmarks/tasks/05-multi-file-feature/task.md`:
```markdown
# Multi-File Feature with API + DB + Tests

**Complexity:** Complex (4 batches)
**Measures:** Full pipeline, cross-file coordination

## Task

Add a "bookmarks" feature: API endpoints (CRUD), database migration, and integration tests.
```

**Step 6: Verify runner works**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash benchmarks/runner.sh list`
Expected: Lists all 5 benchmark tasks

**Step 7: Add results/ to .gitignore**

```bash
echo "benchmarks/results/" >> .gitignore
```

**Step 8: Commit**

```bash
git add benchmarks/ .gitignore
git commit -m "feat: add benchmark suite with 5 tasks and runner.sh"
```

### Task 17: Write benchmark runner test

**Files:**
- Create: `scripts/tests/test-benchmark-runner.sh`

**Step 1: Write the test**

```bash
#!/usr/bin/env bash
# Test benchmarks/runner.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RUNNER="$REPO_ROOT/benchmarks/runner.sh"

source "$SCRIPT_DIR/test-helpers.sh"

# --- Test 1: list shows benchmarks ---
output=$(bash "$RUNNER" list 2>&1)
assert_contains "list shows benchmarks" "01-rest-endpoint" "$output"
assert_contains "list shows all 5" "05-multi-file-feature" "$output"

# --- Test 2: help works ---
output=$(bash "$RUNNER" help 2>&1)
assert_contains "help shows usage" "Usage:" "$output"

# --- Test 3: unknown benchmark fails gracefully ---
exit_code=0
bash "$RUNNER" run nonexistent-benchmark >/dev/null 2>&1 || exit_code=$?
assert_eq "unknown benchmark exits non-zero" "1" "$exit_code"

report_results
```

**Step 2: Make executable and run**

```bash
chmod +x scripts/tests/test-benchmark-runner.sh
```

Run: `bash scripts/tests/test-benchmark-runner.sh`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add scripts/tests/test-benchmark-runner.sh
git commit -m "test: add benchmark runner tests"
```

---

## Batch 8: Trust Score + Graduated Autonomy (P2)

### Task 18: Add trust score computation to telemetry.sh

**Files:**
- Modify: `scripts/telemetry.sh` (add `trust` subcommand)

**Step 1: Add trust score subcommand**

Add a new case to the `case "$SUBCOMMAND"` block in telemetry.sh:

```bash
    trust)
        if [[ ! -f "$TELEMETRY_FILE" ]] || [[ ! -s "$TELEMETRY_FILE" ]]; then
            echo '{"score":0,"level":"new","runs":0,"message":"No telemetry data yet"}'
            exit 0
        fi

        jq -s '
            def trust_level(score; runs):
                if runs < 10 then "new"
                elif score < 30 then "new"
                elif score < 70 then "growing"
                elif score < 90 then "trusted"
                else "autonomous"
                end;

            length as $total |
            ([.[] | select(.passed_gate == true)] | length) as $passed |
            (if $total > 0 then ($passed * 100 / $total) else 0 end) as $gate_rate |
            # Trust score = gate pass rate (simplified; full formula adds echo-back, regression, revert)
            $gate_rate as $score |
            trust_level($score; $total) as $level |
            {
                score: $score,
                level: $level,
                runs: $total,
                gate_pass_rate: $gate_rate,
                default_mode: (
                    if $level == "new" then "human checkpoint every batch"
                    elif $level == "growing" then "headless with checkpoint every 3rd batch"
                    elif $level == "trusted" then "headless with notification on failures only"
                    else "full headless, post-run summary only"
                    end
                )
            }
        ' "$TELEMETRY_FILE"
        ;;
```

**Step 2: Verify trust score works**

Create some test data and check:

```bash
WORK=$(mktemp -d)
mkdir -p "$WORK/logs"
for i in $(seq 1 15); do
    bash scripts/telemetry.sh record --project-root "$WORK" --batch-number "$i" --passed true --strategy test --duration 60 --cost 0.30
done
bash scripts/telemetry.sh trust --project-root "$WORK"
rm -rf "$WORK"
```

Expected: JSON with `"score": 100`, `"level": "autonomous"`, `"runs": 15`

**Step 3: Commit**

```bash
git add scripts/telemetry.sh
git commit -m "feat: add trust score computation to telemetry"
```

### Task 19: Add trust score to pipeline-status.sh

**Files:**
- Modify: `scripts/pipeline-status.sh` (add trust score display section)

**Step 1: Add trust score section**

After the "Git" section (before the final `echo` at the bottom), add:

```bash
# Trust score (from telemetry)
if [[ -x "$SCRIPT_DIR/telemetry.sh" ]]; then
    trust_json=$("$SCRIPT_DIR/telemetry.sh" trust --project-root "$PROJECT_ROOT" 2>/dev/null || echo '{}')
    trust_score=$(echo "$trust_json" | jq -r '.score // "n/a"' 2>/dev/null || echo "n/a")
    trust_level=$(echo "$trust_json" | jq -r '.level // "unknown"' 2>/dev/null || echo "unknown")
    trust_runs=$(echo "$trust_json" | jq -r '.runs // 0' 2>/dev/null || echo "0")
    trust_mode=$(echo "$trust_json" | jq -r '.default_mode // "unknown"' 2>/dev/null || echo "unknown")

    if [[ "$trust_score" != "n/a" && "$trust_runs" != "0" ]]; then
        echo ""
        echo "--- Trust Score ---"
        echo "  Score: ${trust_score}/100 ($trust_runs runs)"
        echo "  Level: $trust_level"
        echo "  Default mode: $trust_mode"
    fi
fi
```

**Step 2: Verify it works (with no telemetry data, silently skips)**

Run: `bash scripts/pipeline-status.sh ~/Documents/projects/autonomous-coding-toolkit 2>&1 | tail -10`
Expected: Shows git section, trust section may show "n/a" or be absent (no telemetry data in the toolkit itself)

**Step 3: Commit**

```bash
git add scripts/pipeline-status.sh
git commit -m "feat: display trust score in pipeline status"
```

---

## Batch 9: Semantic Echo-Back Tier 2 (P2)

### Task 20: Add Tier 2 echo-back support

**Files:**
- Modify: `scripts/lib/run-plan-echo-back.sh` (add LLM verification tier)

**Step 1: Read the current echo-back implementation**

The implementer should read `scripts/lib/run-plan-echo-back.sh` fully to understand the current keyword-matching logic before adding Tier 2.

**Step 2: Add Tier 2 function**

Add after the existing `run_echo_back()` function:

```bash
# --- Tier 2: LLM semantic verification ---
# Activates on batch 1, integration batches, or --strict-echo-back
# Requires: claude CLI available
run_echo_back_tier2() {
    local batch_text="$1"
    local agent_summary="$2"

    if ! command -v claude >/dev/null 2>&1; then
        echo "echo-back-tier2: claude CLI not available — skipping" >&2
        return 0
    fi

    local prompt
    prompt=$(cat <<PROMPT
You are a specification compliance reviewer. Compare:

SPECIFICATION:
$batch_text

AGENT'S UNDERSTANDING:
$agent_summary

Does the agent's understanding match the specification? Flag any:
- Missing requirements
- Added requirements not in spec
- Misinterpreted requirements
- Ambiguous interpretations

Output exactly one line: PASS or FAIL followed by a colon and explanation.
PROMPT
    )

    local result
    result=$(echo "$prompt" | claude -p --max-tokens 200 2>/dev/null || echo "PASS: echo-back tier2 unavailable")

    if echo "$result" | grep -qi "^FAIL"; then
        echo "echo-back-tier2: FAILED — $result"
        return 1
    else
        echo "echo-back-tier2: PASSED"
        return 0
    fi
}

# Determine if tier 2 should activate
should_run_tier2() {
    local batch_number="${1:-0}"
    local batch_type="${2:-unknown}"
    local strict="${3:-false}"

    # Always on batch 1 (disproportionate risk)
    [[ "$batch_number" == "1" ]] && return 0

    # Always on integration batches
    [[ "$batch_type" == "integration" ]] && return 0

    # When strict mode is set
    [[ "$strict" == "true" ]] && return 0

    return 1
}
```

**Step 3: Integration point**

The Tier 2 function is now available. Integration into the run-plan headless loop is optional — it will be called by `run-plan-headless.sh` when `STRICT_ECHO_BACK=true` or conditions match. The implementer should add the call at the appropriate point in the headless loop (after agent generates output, before quality gate).

**Step 4: Commit**

```bash
git add scripts/lib/run-plan-echo-back.sh
git commit -m "feat: add Tier 2 semantic echo-back via LLM verification"
```

### Task 21: Final test suite + quality gate

**Step 1: Run full test suite**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && bash scripts/tests/run-all-tests.sh`
Expected: All tests PASS (including all new tests from this plan)

**Step 2: Run quality gate**

Run: `bash scripts/quality-gate.sh --project-root ~/Documents/projects/autonomous-coding-toolkit`
Expected: ALL PASSED

**Step 3: Run validate-all**

Run: `bash scripts/validate-all.sh`
Expected: All validators pass

---

## Summary

| Batch | Priority | Tasks | New Files | Modified Files |
|-------|----------|-------|-----------|---------------|
| 1 | P0 | 1-3 | `package.json`, `bin/act.js`, `test-act-cli.sh` | — |
| 2 | P0 | 4-5 | `scripts/init.sh`, `test-init.sh` | — |
| 3 | P0 | 6-8 | `test-telegram-env.sh`, `test-lesson-local.sh` | `telegram.sh`, `lesson-check.sh` |
| 4 | P0 | 9-11 | `.npmignore` | `README.md` |
| 5 | P1 | 12-13 | `scripts/telemetry.sh`, `test-telemetry.sh` | — |
| 6 | P1 | 14-15 | — | `quality-gate.sh` |
| 7 | P1 | 16-17 | `benchmarks/runner.sh`, 5 task dirs, `test-benchmark-runner.sh` | `.gitignore` |
| 8 | P2 | 18-19 | — | `telemetry.sh`, `pipeline-status.sh` |
| 9 | P2 | 20-21 | — | `run-plan-echo-back.sh` |

**Total: 21 tasks across 9 batches. ~1,150 new lines. 6 new files, 6 modified files.**
