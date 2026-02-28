# Code Factory v2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate code duplication, fix broken pipeline steps, expand quality gates, and add new capabilities to the Code Factory toolchain.

**Architecture:** Extract shared bash libraries from duplicated code across 6 scripts, then refactor each script to use them. Fix accuracy issues (test count parsing, cross-batch context). Add lint, prior-art search, and pipeline status tools. Finally add failure digest, structured context refs, and team mode.

**Tech Stack:** Bash, jq, ruff (Python linter), gh CLI, ast-grep (structural code search)

## Quality Gates

Between each batch, run:
```bash
scripts/tests/run-all-tests.sh        # All existing + new tests pass
wc -l scripts/*.sh scripts/lib/*.sh   # No script >300 lines
```

---

## Batch 1: Foundation Libraries

Create `scripts/lib/common.sh` and `scripts/lib/ollama.sh` — shared functions extracted from duplicated code across scripts. These are the building blocks for all subsequent refactoring.

### Task 1: Create common.sh with detect_project_type

**Files:**
- Create: `scripts/lib/common.sh`
- Create: `scripts/tests/test-common.sh`

**Step 1: Write the failing test**

Create `scripts/tests/test-common.sh`:

```bash
#!/usr/bin/env bash
# Test shared common.sh functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_exit() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    "$@" || actual_exit=$?
    TESTS=$((TESTS + 1))
    if [[ "$expected_exit" != "$actual_exit" ]]; then
        echo "FAIL: $desc"
        echo "  expected exit: $expected_exit"
        echo "  actual exit:   $actual_exit"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT

# === detect_project_type tests ===

# Python project (pyproject.toml)
mkdir -p "$WORK/py-proj"
touch "$WORK/py-proj/pyproject.toml"
val=$(detect_project_type "$WORK/py-proj")
assert_eq "detect_project_type: pyproject.toml -> python" "python" "$val"

# Python project (setup.py)
mkdir -p "$WORK/py-setup"
touch "$WORK/py-setup/setup.py"
val=$(detect_project_type "$WORK/py-setup")
assert_eq "detect_project_type: setup.py -> python" "python" "$val"

# Node project (package.json)
mkdir -p "$WORK/node-proj"
echo '{"name":"test"}' > "$WORK/node-proj/package.json"
val=$(detect_project_type "$WORK/node-proj")
assert_eq "detect_project_type: package.json -> node" "node" "$val"

# Makefile project
mkdir -p "$WORK/make-proj"
echo 'test:' > "$WORK/make-proj/Makefile"
val=$(detect_project_type "$WORK/make-proj")
assert_eq "detect_project_type: Makefile -> make" "make" "$val"

# Unknown project
mkdir -p "$WORK/empty"
val=$(detect_project_type "$WORK/empty")
assert_eq "detect_project_type: empty -> unknown" "unknown" "$val"

# === strip_json_fences tests ===

val=$(echo '```json
{"key":"value"}
```' | strip_json_fences)
assert_eq "strip_json_fences: removes fences" '{"key":"value"}' "$val"

val=$(echo '{"key":"value"}' | strip_json_fences)
assert_eq "strip_json_fences: plain JSON unchanged" '{"key":"value"}' "$val"

# === check_memory_available tests ===

# This test just verifies the function exists and returns 0/1
# We can't control actual memory, so test the interface
assert_exit "check_memory_available: runs without error" 0 \
    check_memory_available 0

# === require_command tests ===

assert_exit "require_command: bash exists" 0 \
    require_command "bash"

assert_exit "require_command: nonexistent-binary-xyz fails" 1 \
    require_command "nonexistent-binary-xyz"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-common.sh`
Expected: FAIL — `common.sh` does not exist yet

**Step 3: Write minimal implementation**

Create `scripts/lib/common.sh`:

```bash
#!/usr/bin/env bash
# common.sh — Shared utility functions for Code Factory scripts
#
# Source this in any script: source "$SCRIPT_DIR/lib/common.sh"
#
# Functions:
#   detect_project_type <dir>              -> "python"|"node"|"make"|"unknown"
#   strip_json_fences                      -> stdin filter: remove ```json wrappers
#   check_memory_available <threshold_gb>  -> exit 0 if available >= threshold, 1 otherwise
#   require_command <cmd> [install_hint]   -> exit 1 with message if cmd not found

detect_project_type() {
    local dir="$1"
    if [[ -f "$dir/pyproject.toml" || -f "$dir/setup.py" || -f "$dir/pytest.ini" ]]; then
        echo "python"
    elif [[ -f "$dir/package.json" ]]; then
        echo "node"
    elif [[ -f "$dir/Makefile" ]]; then
        echo "make"
    else
        echo "unknown"
    fi
}

strip_json_fences() {
    sed '/^```json$/d; /^```$/d'
}

check_memory_available() {
    local threshold_gb="${1:-4}"
    local available_gb
    available_gb=$(free -g 2>/dev/null | awk '/Mem:/{print $7}' || echo "999")
    if [[ "$available_gb" -ge "$threshold_gb" ]]; then
        return 0
    else
        echo "WARNING: Low memory (${available_gb}G available, need ${threshold_gb}G)" >&2
        return 1
    fi
}

require_command() {
    local cmd="$1"
    local hint="${2:-}"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $cmd" >&2
        if [[ -n "$hint" ]]; then
            echo "  Install with: $hint" >&2
        fi
        return 1
    fi
}
```

**Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test-common.sh`
Expected: ALL PASSED

**Step 5: Commit**

```bash
git add scripts/lib/common.sh scripts/tests/test-common.sh
git commit -m "feat: create scripts/lib/common.sh shared library with tests"
```

### Task 2: Create ollama.sh shared library

**Files:**
- Create: `scripts/lib/ollama.sh`
- Create: `scripts/tests/test-ollama.sh`

**Step 1: Write the failing test**

Create `scripts/tests/test-ollama.sh`. Note: Ollama tests must work offline (mock the HTTP call). Test the URL construction and JSON parsing, not the actual API call.

```bash
#!/usr/bin/env bash
# Test ollama.sh shared library functions
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/ollama.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

# === ollama_build_payload tests ===

val=$(ollama_build_payload "deepseek-r1:8b" "Hello world")
model=$(echo "$val" | jq -r '.model')
assert_eq "ollama_build_payload: model set" "deepseek-r1:8b" "$model"

stream=$(echo "$val" | jq -r '.stream')
assert_eq "ollama_build_payload: stream false" "false" "$stream"

# === ollama_parse_response tests ===

val=$(echo '{"response":"hello"}' | ollama_parse_response)
assert_eq "ollama_parse_response: extracts response" "hello" "$val"

val=$(echo '{}' | ollama_parse_response)
assert_eq "ollama_parse_response: empty on missing field" "" "$val"

# === ollama_extract_json tests ===

val=$(echo '```json
{"key":"value"}
```' | ollama_extract_json)
key=$(echo "$val" | jq -r '.key')
assert_eq "ollama_extract_json: strips fences and validates" "value" "$key"

val=$(echo 'not json at all' | ollama_extract_json)
assert_eq "ollama_extract_json: returns empty on invalid" "" "$val"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-ollama.sh`
Expected: FAIL — `ollama.sh` does not exist

**Step 3: Write minimal implementation**

Create `scripts/lib/ollama.sh`:

```bash
#!/usr/bin/env bash
# ollama.sh — Shared Ollama API interaction for Code Factory scripts
#
# Requires: common.sh sourced first (for strip_json_fences)
#
# Functions:
#   ollama_build_payload <model> <prompt>  -> JSON payload string
#   ollama_parse_response                  -> stdin filter: extract .response from Ollama JSON
#   ollama_extract_json                    -> stdin filter: parse response, strip fences, validate JSON
#   ollama_query <model> <prompt>          -> full query: build payload, call API, return response text
#   ollama_query_json <model> <prompt>     -> full query + JSON extraction

OLLAMA_DIRECT_URL="${OLLAMA_DIRECT_URL:-http://localhost:11434}"
OLLAMA_QUEUE_URL="${OLLAMA_QUEUE_URL:-http://localhost:7683}"

ollama_build_payload() {
    local model="$1" prompt="$2"
    jq -n --arg model "$model" --arg prompt "$prompt" \
        '{model: $model, prompt: $prompt, stream: false}'
}

ollama_parse_response() {
    jq -r '.response // empty'
}

ollama_extract_json() {
    local text
    text=$(cat)
    # Strip fences
    text=$(echo "$text" | strip_json_fences)
    # Validate JSON
    if echo "$text" | jq . >/dev/null 2>&1; then
        echo "$text"
    else
        echo ""
    fi
}

ollama_query() {
    local model="$1" prompt="$2"
    local payload api_url response

    payload=$(ollama_build_payload "$model" "$prompt")

    # Prefer queue if available
    if curl -s -o /dev/null -w '%{http_code}' "$OLLAMA_QUEUE_URL/health" 2>/dev/null | grep -q "200"; then
        api_url="$OLLAMA_QUEUE_URL/api/generate"
    else
        api_url="$OLLAMA_DIRECT_URL/api/generate"
    fi

    response=$(curl -s "$api_url" -d "$payload" --max-time 300)
    echo "$response" | ollama_parse_response
}

ollama_query_json() {
    local model="$1" prompt="$2"
    ollama_query "$model" "$prompt" | ollama_extract_json
}
```

**Step 4: Run test to verify it passes**

Run: `bash scripts/tests/test-ollama.sh`
Expected: ALL PASSED

**Step 5: Commit**

```bash
git add scripts/lib/ollama.sh scripts/tests/test-ollama.sh
git commit -m "feat: create scripts/lib/ollama.sh shared Ollama API library with tests"
```

### Task 3: Create telegram.sh shared library

**Files:**
- Create: `scripts/lib/telegram.sh`
- Modify: `scripts/lib/run-plan-notify.sh` (remove `_load_telegram_env` and `_send_telegram`, source telegram.sh)

**Step 1: Write the failing test**

Create `scripts/tests/test-telegram.sh`:

```bash
#!/usr/bin/env bash
# Test telegram.sh shared library
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/telegram.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_exit() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    "$@" || actual_exit=$?
    TESTS=$((TESTS + 1))
    if [[ "$expected_exit" != "$actual_exit" ]]; then
        echo "FAIL: $desc"
        echo "  expected exit: $expected_exit"
        echo "  actual exit:   $actual_exit"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT

# === _load_telegram_env tests ===

# Missing file
assert_exit "_load_telegram_env: missing file returns 1" 1 \
    _load_telegram_env "$WORK/nonexistent"

# File without keys
echo "SOME_OTHER_KEY=value" > "$WORK/empty.env"
assert_exit "_load_telegram_env: missing keys returns 1" 1 \
    _load_telegram_env "$WORK/empty.env"

# File with both keys
cat > "$WORK/valid.env" << 'ENVFILE'
TELEGRAM_BOT_TOKEN=test-token-123
TELEGRAM_CHAT_ID=test-chat-456
ENVFILE
assert_exit "_load_telegram_env: valid file returns 0" 0 \
    _load_telegram_env "$WORK/valid.env"
assert_eq "_load_telegram_env: token loaded" "test-token-123" "$TELEGRAM_BOT_TOKEN"
assert_eq "_load_telegram_env: chat_id loaded" "test-chat-456" "$TELEGRAM_CHAT_ID"

# === _send_telegram without credentials ===

unset TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
assert_exit "_send_telegram: no creds returns 0 (skip)" 0 \
    _send_telegram "test message"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-telegram.sh`
Expected: FAIL — `telegram.sh` does not exist

**Step 3: Write implementation**

Create `scripts/lib/telegram.sh` — extract from `run-plan-notify.sh` lines 27-63:

```bash
#!/usr/bin/env bash
# telegram.sh — Shared Telegram notification helpers
#
# Functions:
#   _load_telegram_env [env_file]  -> load TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
#   _send_telegram <message>       -> send via Telegram Bot API

_load_telegram_env() {
    local env_file="${1:-$HOME/.env}"

    if [[ ! -f "$env_file" ]]; then
        echo "WARNING: env file not found: $env_file" >&2
        return 1
    fi

    TELEGRAM_BOT_TOKEN=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$env_file" | head -1 | cut -d= -f2-)
    TELEGRAM_CHAT_ID=$(grep -E '^TELEGRAM_CHAT_ID=' "$env_file" | head -1 | cut -d= -f2-)

    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        echo "WARNING: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID not found in $env_file" >&2
        return 1
    fi

    export TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID
}

_send_telegram() {
    local message="$1"

    if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
        echo "WARNING: Telegram credentials not set — skipping notification" >&2
        return 0
    fi

    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"

    curl -s -X POST "$url" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d text="$message" \
        -d parse_mode="Markdown" \
        --max-time 10 > /dev/null 2>&1 || {
        echo "WARNING: Failed to send Telegram notification" >&2
        return 0
    }
}
```

Then update `scripts/lib/run-plan-notify.sh` — replace `_load_telegram_env` and `_send_telegram` with a source line:

```bash
#!/usr/bin/env bash
# run-plan-notify.sh — Telegram notification helpers for run-plan
#
# Functions:
#   format_success_message <plan_name> <batch_num> <test_count> <prev_count> <duration> <mode>
#   format_failure_message <plan_name> <batch_num> <test_count> <failing_count> <error> <action>
#   notify_success (same args as format_success_message) — format + send
#   notify_failure (same args as format_failure_message) — format + send

# Source shared telegram functions
_NOTIFY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_NOTIFY_SCRIPT_DIR/telegram.sh"

format_success_message() {
    local plan_name="$1" batch_num="$2" test_count="$3" prev_count="$4" duration="$5" mode="$6"
    local delta=$(( test_count - prev_count ))

    printf '%s — Batch %s ✓\nTests: %s (↑%s)\nDuration: %s\nMode: %s' \
        "$plan_name" "$batch_num" "$test_count" "$delta" "$duration" "$mode"
}

format_failure_message() {
    local plan_name="$1" batch_num="$2" test_count="$3" failing_count="$4" error="$5" action="$6"

    printf '%s — Batch %s ✗\nTests: %s (%s failing)\nError: %s\nAction: %s' \
        "$plan_name" "$batch_num" "$test_count" "$failing_count" "$error" "$action"
}

notify_success() {
    local msg
    msg=$(format_success_message "$@")
    _send_telegram "$msg"
}

notify_failure() {
    local msg
    msg=$(format_failure_message "$@")
    _send_telegram "$msg"
}
```

**Step 4: Run tests to verify they pass**

Run: `bash scripts/tests/test-telegram.sh && bash scripts/tests/test-run-plan-notify.sh`
Expected: ALL PASSED (both)

**Step 5: Commit**

```bash
git add scripts/lib/telegram.sh scripts/tests/test-telegram.sh scripts/lib/run-plan-notify.sh
git commit -m "feat: extract scripts/lib/telegram.sh from run-plan-notify.sh"
```

## Batch 2: Refactor Scripts to Use Shared Libraries

Refactor all 5 scripts (`auto-compound.sh`, `quality-gate.sh`, `entropy-audit.sh`, `analyze-report.sh`, `run-plan.sh`) to use the shared libraries from Batch 1. No behavior changes — pure deduplication.

### Task 4: Refactor quality-gate.sh to use common.sh

**Files:**
- Modify: `scripts/quality-gate.sh:29-45` (arg parsing), `scripts/quality-gate.sh:79-91` (project detection), `scripts/quality-gate.sh:97-107` (memory check)

**Step 1: Read current quality-gate.sh**

Identify the three sections to replace:
- Lines 79-91: inline project type detection → `detect_project_type()`
- Lines 100-106: inline memory check → `check_memory_available()`

**Step 2: Add source line and refactor**

Add after line 6 (`SCRIPT_DIR=...`):
```bash
source "$SCRIPT_DIR/lib/common.sh"
```

Replace lines 79-91 (test suite detection) with:
```bash
project_type=$(detect_project_type "$PROJECT_ROOT")
case "$project_type" in
    python)
        echo "Detected: pytest project"
        .venv/bin/python -m pytest --timeout=120 -x -q
        test_ran=1
        ;;
    node)
        if grep -q '"test"' "$PROJECT_ROOT/package.json" 2>/dev/null; then
            echo "Detected: npm project"
            npm test
            test_ran=1
        fi
        ;;
    make)
        if grep -q '^test:' "$PROJECT_ROOT/Makefile" 2>/dev/null; then
            echo "Detected: Makefile project"
            make test
            test_ran=1
        fi
        ;;
esac
```

Replace lines 100-106 (memory check) with:
```bash
if check_memory_available 4; then
    available_gb=$(free -g | awk '/Mem:/{print $7}')
    echo "Memory OK (${available_gb}G available)"
else
    echo "WARNING: Consider -n 0 for pytest"
fi
```

**Step 3: Run quality gate test (existing tests must still pass)**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 4: Verify line count**

Run: `wc -l scripts/quality-gate.sh`
Expected: Under 300 lines

**Step 5: Commit**

```bash
git add scripts/quality-gate.sh
git commit -m "refactor: quality-gate.sh uses common.sh for project detection and memory check"
```

### Task 5: Refactor auto-compound.sh to use common.sh and ollama.sh

**Files:**
- Modify: `scripts/auto-compound.sh:17` (add source lines), `scripts/auto-compound.sh:127` (fix PRD discard), `scripts/auto-compound.sh:144-163` (replace inline project detection)

**Step 1: Read and identify sections**

Three changes:
1. Add source lines after `SCRIPT_DIR` (line 17)
2. Fix line 127: `> /dev/null 2>&1 || true` discards PRD output — capture it and log errors (lesson-7 fix)
3. Replace lines 144-163 (fallback quality checks detection) with `detect_project_type()`

**Step 2: Apply changes**

After line 17, add:
```bash
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ollama.sh"
```

Replace line 127:
```bash
  # OLD: claude --print "/create-prd $PRIORITY. Context from analysis: $(cat analysis.json)" > /dev/null 2>&1 || true
  prd_output=$(claude --print "/create-prd $PRIORITY. Context from analysis: $(cat analysis.json)" 2>&1) || {
      echo "WARNING: PRD generation failed:" >&2
      echo "$prd_output" | tail -10 >&2
  }
```

Replace lines 144-163 (fallback detection) with:
```bash
  local project_type
  project_type=$(detect_project_type "$PROJECT_DIR")
  case "$project_type" in
    python)  QUALITY_CHECKS="pytest --timeout=120 -x -q" ;;
    node)
      QUALITY_CHECKS=""
      grep -q '"test"' package.json 2>/dev/null && QUALITY_CHECKS+="npm test"
      grep -q '"lint"' package.json 2>/dev/null && { [[ -n "$QUALITY_CHECKS" ]] && QUALITY_CHECKS+=";"; QUALITY_CHECKS+="npm run lint"; }
      ;;
    make)    QUALITY_CHECKS="make test" ;;
    *)       QUALITY_CHECKS="" ;;
  esac
  echo "  Fallback mode — quality-gate.sh not found"
```

**Step 3: Verify no test regressions**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 4: Verify line count**

Run: `wc -l scripts/auto-compound.sh`
Expected: Under 300 lines (was 230, should be ~220 now)

**Step 5: Commit**

```bash
git add scripts/auto-compound.sh
git commit -m "refactor: auto-compound.sh uses common.sh, fixes PRD output discard (lesson-7)"
```

### Task 6: Refactor analyze-report.sh to use ollama.sh

**Files:**
- Modify: `scripts/analyze-report.sh:75-111` (replace inline Ollama call and JSON stripping)

**Step 1: Identify replacement sections**

Lines 75-88: Ollama API call logic → `ollama_query()`
Lines 100-111: JSON fence stripping → `strip_json_fences` + `ollama_extract_json()`

**Step 2: Apply changes**

Add after the `set -euo pipefail` line:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/ollama.sh"
```

Replace lines 75-111 with:
```bash
# Query Ollama
ANALYSIS=$(ollama_query "$MODEL" "$PROMPT")

if [[ -z "$ANALYSIS" ]]; then
  echo "Error: Empty response from Ollama" >&2
  exit 1
fi

# Parse as JSON
CLEANED=$(echo "$ANALYSIS" | ollama_extract_json)
if [[ -n "$CLEANED" ]]; then
    echo "$CLEANED" | jq . > "$OUTPUT_DIR/analysis.json"
else
    echo "Warning: Could not parse LLM response as JSON, saving raw" >&2
    echo "{\"raw_response\": $(echo "$ANALYSIS" | jq -Rs .)}" > "$OUTPUT_DIR/analysis.json"
fi
```

**Step 3: Run tests**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 4: Verify line count**

Run: `wc -l scripts/analyze-report.sh`
Expected: Under 100 lines (was 114, trimmed ~30 lines of Ollama logic)

**Step 5: Commit**

```bash
git add scripts/analyze-report.sh
git commit -m "refactor: analyze-report.sh uses ollama.sh shared library"
```

### Task 7: Refactor entropy-audit.sh — remove hardcoded path

**Files:**
- Modify: `scripts/entropy-audit.sh:17` (replace hardcoded path with env var + arg)

**Step 1: Identify the fix**

Line 17: `PROJECTS_DIR="$HOME/Documents/projects"` is hardcoded. Replace with `--projects-dir` arg that defaults to `PROJECTS_DIR` env var, then `$HOME/Documents/projects`.

**Step 2: Apply changes**

Add after `set -euo pipefail`:
```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
```

Replace line 17:
```bash
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Documents/projects}"
```

Add `--projects-dir` to the arg parser (after `--fix` case):
```bash
    --projects-dir) PROJECTS_DIR="$2"; shift 2 ;;
```

**Step 3: Run tests**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 4: Commit**

```bash
git add scripts/entropy-audit.sh
git commit -m "refactor: entropy-audit.sh uses env var/arg instead of hardcoded projects path"
```

### Task 8: Extract run-plan-headless.sh from run-plan.sh

**Files:**
- Create: `scripts/lib/run-plan-headless.sh`
- Modify: `scripts/run-plan.sh:229-376` (replace `run_mode_headless()` with source + call)

**Step 1: Extract `run_mode_headless()` from run-plan.sh**

Move lines 229-376 of `scripts/run-plan.sh` (the entire `run_mode_headless()` function) into `scripts/lib/run-plan-headless.sh`. The function reads these globals: `WORKTREE`, `RESUME`, `START_BATCH`, `END_BATCH`, `NOTIFY`, `PLAN_FILE`, `QUALITY_GATE_CMD`, `PYTHON`, `MAX_RETRIES`, `ON_FAILURE`, `VERIFY`, `MODE`. These are all set before the function is called.

**Step 2: Create `scripts/lib/run-plan-headless.sh`**

```bash
#!/usr/bin/env bash
# run-plan-headless.sh — Headless batch execution loop for run-plan
#
# Extracted from run-plan.sh to keep the main script under 300 lines.
#
# Requires these globals set before calling:
#   WORKTREE, RESUME, START_BATCH, END_BATCH, NOTIFY, PLAN_FILE,
#   QUALITY_GATE_CMD, PYTHON, MAX_RETRIES, ON_FAILURE, VERIFY, MODE
#
# Requires these libs sourced:
#   run-plan-parser.sh, run-plan-state.sh, run-plan-quality-gate.sh,
#   run-plan-notify.sh, run-plan-prompt.sh

run_mode_headless() {
    # (paste the entire function body from run-plan.sh lines 230-376 here verbatim)
}
```

Copy the function body exactly from lines 230-376. Do not modify any logic.

**Step 3: Update run-plan.sh**

Add source line after the other source statements (line 21):
```bash
source "$SCRIPT_DIR/lib/run-plan-headless.sh"
```

Remove lines 229-376 (the old `run_mode_headless` function).

**Step 4: Run all tests**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED (existing tests exercise run-plan.sh and should still work)

**Step 5: Verify line counts**

Run: `wc -l scripts/run-plan.sh scripts/lib/run-plan-headless.sh`
Expected: `run-plan.sh` ~260 lines (under 300), `run-plan-headless.sh` ~150 lines

**Step 6: Commit**

```bash
git add scripts/lib/run-plan-headless.sh scripts/run-plan.sh
git commit -m "refactor: extract run_mode_headless() into scripts/lib/run-plan-headless.sh"
```

## Batch 3: Accuracy Fixes — Test Count Parsing and Cross-Batch Context

Fix the two most impactful accuracy bugs: test count parsing that only works for pytest, and missing cross-batch context that causes agents to repeat work.

### Task 9: Fix test count parsing for multiple test frameworks

**Files:**
- Modify: `scripts/lib/run-plan-quality-gate.sh:19-29` (replace `extract_test_count`)
- Modify: `scripts/tests/test-run-plan-quality-gate.sh` (add new test cases)

**Step 1: Add failing tests for jest, go, and unknown formats**

Add to `scripts/tests/test-run-plan-quality-gate.sh` after the existing `extract_test_count` tests (before the `check_test_count_regression` section):

```bash
# --- Test: extract from jest output ---
output="Tests:       3 failed, 45 passed, 48 total"
val=$(extract_test_count "$output")
assert_eq "extract_test_count: jest output" "45" "$val"

# --- Test: extract from jest all-pass output ---
output="Tests:       12 passed, 12 total"
val=$(extract_test_count "$output")
assert_eq "extract_test_count: jest all-pass" "12" "$val"

# --- Test: extract from go test output ---
output="ok  	github.com/foo/bar	0.123s
ok  	github.com/foo/baz	0.456s
FAIL	github.com/foo/qux	0.789s"
val=$(extract_test_count "$output")
assert_eq "extract_test_count: go test (2 ok of 3)" "2" "$val"

# --- Test: unrecognized format returns -1 ---
val=$(extract_test_count "Some random build output with no test results")
assert_eq "extract_test_count: unrecognized format" "-1" "$val"
```

**Step 2: Run test to verify failures**

Run: `bash scripts/tests/test-run-plan-quality-gate.sh`
Expected: FAIL on jest, go, and unrecognized format tests

**Step 3: Update extract_test_count implementation**

Replace `extract_test_count()` in `scripts/lib/run-plan-quality-gate.sh`:

```bash
extract_test_count() {
    local output="$1"
    local count

    # 1. pytest: "N passed" (e.g., "85 passed" in "3 failed, 85 passed, 2 skipped in 30.1s")
    count=$(echo "$output" | grep -oP '\b(\d+) passed\b' | tail -1 | grep -oP '^\d+' || true)
    if [[ -n "$count" ]]; then
        echo "$count"
        return
    fi

    # 2. jest: "Tests: N passed" (e.g., "Tests:       45 passed, 48 total")
    count=$(echo "$output" | grep -oP 'Tests:\s+(\d+ failed, )?\K\d+(?= passed)' || true)
    if [[ -n "$count" ]]; then
        echo "$count"
        return
    fi

    # 3. go test: count "ok" lines (each = one passing package)
    count=$(echo "$output" | grep -c '^ok' || true)
    if [[ "$count" -gt 0 ]]; then
        echo "$count"
        return
    fi

    # 4. No recognized format — return -1 to signal "skip regression check"
    echo "-1"
}
```

Also update `check_test_count_regression()` to handle `-1`:
```bash
check_test_count_regression() {
    local new_count="$1" previous_count="$2"
    # -1 means unrecognized format — skip regression check
    if [[ "$new_count" == "-1" || "$previous_count" == "-1" ]]; then
        echo "INFO: Skipping test count regression check (unrecognized test format)" >&2
        return 0
    fi
    if [[ "$new_count" -ge "$previous_count" ]]; then
        return 0
    else
        echo "WARNING: Test count regression: $new_count < $previous_count (previous)" >&2
        return 1
    fi
}
```

**Step 4: Run tests**

Run: `bash scripts/tests/test-run-plan-quality-gate.sh`
Expected: ALL PASSED

Also add a regression test for `check_test_count_regression` with -1:
```bash
# --- Test: -1 skips regression check ---
assert_exit "check_test_count_regression: -1 new skips check" 0 \
    check_test_count_regression -1 150

assert_exit "check_test_count_regression: -1 previous skips check" 0 \
    check_test_count_regression 50 -1
```

**Step 5: Commit**

```bash
git add scripts/lib/run-plan-quality-gate.sh scripts/tests/test-run-plan-quality-gate.sh
git commit -m "fix: test count parsing supports jest, go test, and returns -1 for unknown formats"
```

### Task 10: Add cross-batch context to prompts

**Files:**
- Modify: `scripts/lib/run-plan-prompt.sh` (add git log, progress.txt, quality gate context)
- Modify: `scripts/tests/test-run-plan-prompt.sh` (add assertions for new context)

**Step 1: Read existing prompt test**

Read `scripts/tests/test-run-plan-prompt.sh` to understand current test structure.

**Step 2: Add failing test**

Add assertion that the prompt output contains cross-batch context markers:

```bash
# --- Test: prompt includes cross-batch context ---
# Create a state file with previous quality gate
echo '{"last_quality_gate":{"batch":1,"passed":true,"test_count":42}}' > "$WORK/.run-plan-state.json"
# Create progress.txt
echo "Batch 1: Implemented auth module" > "$WORK/progress.txt"
# Create a git commit in the work dir
echo "file" > "$WORK/code.py"
git -C "$WORK" add code.py && git -C "$WORK" commit -q -m "feat: add auth"

prompt=$(build_batch_prompt "$PLAN" 2 "$WORK" "python3" "scripts/quality-gate.sh" 42)
echo "$prompt" | grep -q "Recent commits" || {
    echo "FAIL: prompt missing 'Recent commits' section"
    FAILURES=$((FAILURES + 1))
}
TESTS=$((TESTS + 1))
echo "$prompt" | grep -q "progress.txt" || echo "$prompt" | grep -q "Previous progress" || {
    echo "FAIL: prompt missing progress.txt context"
    FAILURES=$((FAILURES + 1))
}
TESTS=$((TESTS + 1))
```

**Step 3: Run test to verify failure**

Run: `bash scripts/tests/test-run-plan-prompt.sh`
Expected: FAIL on cross-batch context assertions

**Step 4: Update build_batch_prompt**

Replace `build_batch_prompt()` in `scripts/lib/run-plan-prompt.sh`:

```bash
build_batch_prompt() {
    local plan_file="$1"
    local batch_num="$2"
    local worktree="$3"
    local python="$4"
    local quality_gate_cmd="$5"
    local prev_test_count="$6"

    local title branch batch_text recent_commits progress_tail prev_gate

    title=$(get_batch_title "$plan_file" "$batch_num")
    branch=$(git -C "$worktree" branch --show-current 2>/dev/null || echo "unknown")
    batch_text=$(get_batch_text "$plan_file" "$batch_num")

    # Cross-batch context: recent commits
    recent_commits=$(git -C "$worktree" log --oneline -5 2>/dev/null || echo "(no commits)")

    # Cross-batch context: progress.txt tail
    progress_tail=""
    if [[ -f "$worktree/progress.txt" ]]; then
        progress_tail=$(tail -20 "$worktree/progress.txt" 2>/dev/null || true)
    fi

    # Cross-batch context: previous quality gate result
    prev_gate=""
    if [[ -f "$worktree/.run-plan-state.json" ]]; then
        prev_gate=$(jq -r '.last_quality_gate // empty' "$worktree/.run-plan-state.json" 2>/dev/null || true)
    fi

    cat <<PROMPT
You are implementing Batch ${batch_num}: ${title} from ${plan_file}.

Working directory: ${worktree}
Python: ${python}
Branch: ${branch}

Tasks in this batch:
${batch_text}

Recent commits:
${recent_commits}
$(if [[ -n "$progress_tail" ]]; then
echo "
Previous progress:
${progress_tail}"
fi)
$(if [[ -n "$prev_gate" && "$prev_gate" != "null" ]]; then
echo "
Previous quality gate: ${prev_gate}"
fi)

Requirements:
- TDD: write test -> verify fail -> implement -> verify pass -> commit each task
- After all tasks: run quality gate (${quality_gate_cmd})
- Update progress.txt with batch summary and commit
- All ${prev_test_count}+ tests must pass
PROMPT
}
```

**Step 5: Run tests**

Run: `bash scripts/tests/test-run-plan-prompt.sh`
Expected: ALL PASSED

**Step 6: Commit**

```bash
git add scripts/lib/run-plan-prompt.sh scripts/tests/test-run-plan-prompt.sh
git commit -m "feat: add cross-batch context (git log, progress.txt, gate result) to prompts"
```

### Task 11: Add duration tracking to state

**Files:**
- Modify: `scripts/lib/run-plan-state.sh` (add `duration_seconds` field to `complete_batch`)
- Modify: `scripts/lib/run-plan-headless.sh` (pass duration to `complete_batch`)
- Modify: `scripts/tests/test-run-plan-state.sh` (add duration assertions)

**Step 1: Add failing test**

Add to `scripts/tests/test-run-plan-state.sh`:

```bash
# --- Test: complete_batch stores duration ---
complete_batch "$WORK" 1 42 120
duration=$(jq -r '.durations["1"]' "$WORK/.run-plan-state.json")
assert_eq "complete_batch: stores duration" "120" "$duration"
```

**Step 2: Run test to verify failure**

Run: `bash scripts/tests/test-run-plan-state.sh`
Expected: FAIL — `complete_batch` only takes 3 args currently

**Step 3: Update complete_batch to accept optional duration**

In `scripts/lib/run-plan-state.sh`, update `complete_batch()`:

```bash
complete_batch() {
    local worktree="$1" batch_num="$2" test_count="$3" duration="${4:-0}"
    local sf tmp
    sf=$(_state_file "$worktree")
    tmp=$(mktemp)

    jq \
        --argjson batch "$batch_num" \
        --argjson tc "$test_count" \
        --argjson dur "$duration" \
        '
        .completed_batches += [$batch] |
        .current_batch = ($batch + 1) |
        .test_counts[($batch | tostring)] = $tc |
        .durations[($batch | tostring)] = $dur
        ' "$sf" > "$tmp" && mv "$tmp" "$sf"
}
```

Update `init_state()` to include `durations: {}`:
```bash
    jq -n \
        --arg plan_file "$plan_file" \
        --arg mode "$mode" \
        --arg started_at "$now" \
        '{
            plan_file: $plan_file,
            mode: $mode,
            current_batch: 1,
            completed_batches: [],
            test_counts: {},
            durations: {},
            started_at: $started_at,
            last_quality_gate: null
        }' > "$sf"
```

Update `run_mode_headless()` in `run-plan-headless.sh` — pass duration to `complete_batch`. Find the line `complete_batch "$WORKTREE" "$batch_num" "$test_count"` inside `run_quality_gate` and also ensure the headless loop passes duration. The duration is already computed as `$duration` variable.

**Step 4: Run tests**

Run: `bash scripts/tests/test-run-plan-state.sh && bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 5: Commit**

```bash
git add scripts/lib/run-plan-state.sh scripts/lib/run-plan-headless.sh scripts/tests/test-run-plan-state.sh
git commit -m "feat: add per-batch duration tracking to run-plan state"
```

## Batch 4: Quality Gate Expansion

Add lint checking and prior-art search to the quality gate pipeline.

### Task 12: Add ruff lint step to quality-gate.sh

**Files:**
- Modify: `scripts/quality-gate.sh` (add lint check between lesson-check and test suite)

**Step 1: Verify ruff is installed**

Run: `ruff --version`
If not installed: `pip install ruff` (or `brew install ruff`)

**Step 2: Add lint check to quality-gate.sh**

Insert after the lesson check section (after the `fi` on line ~72), before the test suite section:

```bash
# === Check 2: Lint (ruff for Python, eslint for Node) ===
echo ""
echo "=== Quality Gate: Lint Check ==="
project_type=$(detect_project_type "$PROJECT_ROOT")
lint_ran=0

case "$project_type" in
    python)
        if command -v ruff >/dev/null 2>&1; then
            echo "Running: ruff check --select E,W,F"
            if ! ruff check --select E,W,F "$PROJECT_ROOT"; then
                echo ""
                echo "quality-gate: FAILED at lint check"
                exit 1
            fi
            lint_ran=1
        else
            echo "ruff not installed — skipping Python lint"
        fi
        ;;
    node)
        if [[ -f "$PROJECT_ROOT/.eslintrc" || -f "$PROJECT_ROOT/.eslintrc.js" || -f "$PROJECT_ROOT/.eslintrc.json" || -f "$PROJECT_ROOT/eslint.config.js" ]]; then
            echo "Running: npx eslint"
            if ! npx eslint "$PROJECT_ROOT" 2>/dev/null; then
                echo ""
                echo "quality-gate: FAILED at lint check"
                exit 1
            fi
            lint_ran=1
        else
            echo "No eslint config found — skipping Node lint"
        fi
        ;;
esac

if [[ $lint_ran -eq 0 ]]; then
    echo "No linter configured — skipped"
fi
```

Renumber the subsequent checks (test suite becomes Check 3, memory becomes Check 4).

**Step 3: Run tests**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 4: Verify line count**

Run: `wc -l scripts/quality-gate.sh`
Expected: Under 300 lines (~145 now)

**Step 5: Commit**

```bash
git add scripts/quality-gate.sh
git commit -m "feat: add ruff/eslint lint step to quality-gate.sh"
```

### Task 13: Create prior-art-search.sh

**Files:**
- Create: `scripts/prior-art-search.sh`
- Create: `scripts/tests/test-prior-art-search.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# Test prior-art-search.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_SCRIPT="$SCRIPT_DIR/../prior-art-search.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

assert_exit() {
    local desc="$1" expected_exit="$2"
    shift 2
    local actual_exit=0
    "$@" || actual_exit=$?
    TESTS=$((TESTS + 1))
    if [[ "$expected_exit" != "$actual_exit" ]]; then
        echo "FAIL: $desc"
        echo "  expected exit: $expected_exit"
        echo "  actual exit:   $actual_exit"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

# --- Test: --help exits 0 ---
assert_exit "prior-art-search --help exits 0" 0 \
    bash "$SEARCH_SCRIPT" --help

# --- Test: --dry-run produces output without calling gh ---
output=$(bash "$SEARCH_SCRIPT" --dry-run "implement webhook handler" 2>&1)
echo "$output" | grep -q "Search query:" && TESTS=$((TESTS + 1)) && echo "PASS: dry-run shows search query" || {
    TESTS=$((TESTS + 1)); echo "FAIL: dry-run missing search query"; FAILURES=$((FAILURES + 1))
}

# --- Test: missing query shows usage ---
assert_exit "prior-art-search: no args exits 1" 1 \
    bash "$SEARCH_SCRIPT"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test to verify it fails**

Run: `bash scripts/tests/test-prior-art-search.sh`
Expected: FAIL — script does not exist

**Step 3: Write implementation**

Create `scripts/prior-art-search.sh`:

```bash
#!/usr/bin/env bash
# prior-art-search.sh — Search GitHub and local codebase for prior art
#
# Usage: prior-art-search.sh [--dry-run] [--local-only] [--github-only] <query>
#
# Searches:
#   1. GitHub repos (gh search repos)
#   2. GitHub code (gh search code)
#   3. Local ~/Documents/projects/ (grep -r)
#
# Output: Ranked results with source, relevance, and URL/path
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

DRY_RUN=false
LOCAL_ONLY=false
GITHUB_ONLY=false
QUERY=""
MAX_RESULTS=10
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/Documents/projects}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --local-only) LOCAL_ONLY=true; shift ;;
        --github-only) GITHUB_ONLY=true; shift ;;
        --max-results) MAX_RESULTS="$2"; shift 2 ;;
        --projects-dir) PROJECTS_DIR="$2"; shift 2 ;;
        -h|--help)
            cat <<'USAGE'
prior-art-search.sh — Search for prior art before building

Usage: prior-art-search.sh [OPTIONS] <query>

Options:
  --dry-run          Show what would be searched without executing
  --local-only       Only search local projects
  --github-only      Only search GitHub
  --max-results N    Max results per source (default: 10)
  --projects-dir P   Local projects directory

Output: Results ranked by relevance with source attribution
USAGE
            exit 0
            ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) QUERY="$1"; shift ;;
    esac
done

if [[ -z "$QUERY" ]]; then
    echo "Error: Query required" >&2
    echo "Usage: prior-art-search.sh <query>" >&2
    exit 1
fi

echo "=== Prior Art Search ==="
echo "Search query: $QUERY"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] Would search:"
    [[ "$LOCAL_ONLY" != true ]] && echo "  - GitHub repos: gh search repos '$QUERY' --limit $MAX_RESULTS"
    [[ "$LOCAL_ONLY" != true ]] && echo "  - GitHub code: gh search code '$QUERY' --limit $MAX_RESULTS"
    [[ "$GITHUB_ONLY" != true ]] && echo "  - Local projects: grep -rl in $PROJECTS_DIR"
    exit 0
fi

# Search 1: GitHub repos
if [[ "$LOCAL_ONLY" != true ]]; then
    echo "--- GitHub Repos ---"
    if command -v gh >/dev/null 2>&1; then
        gh search repos "$QUERY" --limit "$MAX_RESULTS" --json name,url,description,stargazersCount \
            --jq '.[] | "★ \(.stargazersCount) | \(.name) — \(.description // "no description") | \(.url)"' \
            2>/dev/null || echo "  (GitHub search unavailable)"
    else
        echo "  gh CLI not installed — skipping"
    fi
    echo ""

    echo "--- GitHub Code ---"
    if command -v gh >/dev/null 2>&1; then
        gh search code "$QUERY" --limit "$MAX_RESULTS" --json repository,path \
            --jq '.[] | "\(.repository.nameWithOwner)/\(.path)"' \
            2>/dev/null || echo "  (GitHub code search unavailable)"
    else
        echo "  gh CLI not installed — skipping"
    fi
    echo ""
fi

# Search 2: Local projects
if [[ "$GITHUB_ONLY" != true ]]; then
    echo "--- Local Projects ---"
    if [[ -d "$PROJECTS_DIR" ]]; then
        grep -rl --include='*.py' --include='*.sh' --include='*.ts' --include='*.js' \
            "$QUERY" "$PROJECTS_DIR" 2>/dev/null | head -"$MAX_RESULTS" || echo "  No local matches"
    else
        echo "  Projects directory not found: $PROJECTS_DIR"
    fi
    echo ""
fi

echo "=== Search Complete ==="
```

**Step 4: Run tests**

Run: `bash scripts/tests/test-prior-art-search.sh`
Expected: ALL PASSED

**Step 5: Commit**

```bash
chmod +x scripts/prior-art-search.sh
git add scripts/prior-art-search.sh scripts/tests/test-prior-art-search.sh
git commit -m "feat: create prior-art-search.sh for GitHub and local code search"
```

### Task 14: Create pipeline-status.sh

**Files:**
- Create: `scripts/pipeline-status.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
# pipeline-status.sh — Single-command view of Code Factory pipeline status
#
# Usage: pipeline-status.sh [--project-root <dir>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="${1:-.}"

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "pipeline-status.sh — Show Code Factory pipeline status"
    echo "Usage: pipeline-status.sh [project-root]"
    exit 0
fi

echo "═══════════════════════════════════════════════"
echo "  Code Factory Pipeline Status"
echo "═══════════════════════════════════════════════"
echo "Project: $(basename "$(realpath "$PROJECT_ROOT")")"
echo "Type:    $(detect_project_type "$PROJECT_ROOT")"
echo ""

# Run-plan state
STATE_FILE="$PROJECT_ROOT/.run-plan-state.json"
if [[ -f "$STATE_FILE" ]]; then
    echo "--- Run Plan ---"
    plan=$(jq -r '.plan_file // "unknown"' "$STATE_FILE")
    mode=$(jq -r '.mode // "unknown"' "$STATE_FILE")
    current=$(jq -r '.current_batch // 0' "$STATE_FILE")
    completed=$(jq -r '.completed_batches | length' "$STATE_FILE")
    started=$(jq -r '.started_at // "unknown"' "$STATE_FILE")
    echo "  Plan:      $(basename "$plan")"
    echo "  Mode:      $mode"
    echo "  Progress:  $completed batches completed (current: $current)"
    echo "  Started:   $started"

    # Last quality gate
    gate_passed=$(jq -r '.last_quality_gate.passed // "n/a"' "$STATE_FILE")
    gate_tests=$(jq -r '.last_quality_gate.test_count // "n/a"' "$STATE_FILE")
    echo "  Last gate: passed=$gate_passed, tests=$gate_tests"
    echo ""
else
    echo "--- Run Plan ---"
    echo "  No active run-plan state found"
    echo ""
fi

# PRD status
if [[ -f "$PROJECT_ROOT/tasks/prd.json" ]]; then
    echo "--- PRD ---"
    total=$(jq 'length' "$PROJECT_ROOT/tasks/prd.json")
    passing=$(jq '[.[] | select(.passes == true)] | length' "$PROJECT_ROOT/tasks/prd.json")
    echo "  Tasks: $passing/$total passing"
    echo ""
else
    echo "--- PRD ---"
    echo "  No PRD found (tasks/prd.json)"
    echo ""
fi

# Progress file
if [[ -f "$PROJECT_ROOT/progress.txt" ]]; then
    echo "--- Progress ---"
    tail -5 "$PROJECT_ROOT/progress.txt" | sed 's/^/  /'
    echo ""
fi

# Git status
echo "--- Git ---"
branch=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
uncommitted=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null | wc -l || echo 0)
echo "  Branch:      $branch"
echo "  Uncommitted: $uncommitted files"

echo ""
echo "═══════════════════════════════════════════════"
```

**Step 2: Test manually**

Run: `bash scripts/pipeline-status.sh .`
Expected: Shows status output without errors

**Step 3: Commit**

```bash
chmod +x scripts/pipeline-status.sh
git add scripts/pipeline-status.sh
git commit -m "feat: create pipeline-status.sh for single-command pipeline overview"
```

### Task 15: Wire prior-art search into auto-compound.sh

**Files:**
- Modify: `scripts/auto-compound.sh` (add prior-art search step before PRD generation)

**Step 1: Add search step**

Insert after Step 2 (branch creation, ~line 117) and before Step 3 (PRD generation):

```bash
# Step 2.5: Prior art search
echo "🔎 Step 2.5: Searching for prior art..."
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  [dry-run] Would search: $PRIORITY"
else
  PRIOR_ART=$("$SCRIPT_DIR/prior-art-search.sh" "$PRIORITY" 2>&1 || true)
  echo "$PRIOR_ART" | head -20
  # Save for PRD context
  echo "$PRIOR_ART" > prior-art-results.txt
  echo "  Saved to prior-art-results.txt"

  # Append to progress.txt
  mkdir -p "$(dirname progress.txt)"
  echo "## Prior Art Search: $PRIORITY" >> progress.txt
  echo "$PRIOR_ART" | head -10 >> progress.txt
  echo "" >> progress.txt
fi
echo ""
```

Update Step 3 (PRD generation) to include prior art context:

```bash
  # Include prior art if available
  local prior_art_context=""
  if [[ -f "prior-art-results.txt" ]]; then
      prior_art_context="Prior art found: $(head -20 prior-art-results.txt)"
  fi
  prd_output=$(claude --print "/create-prd $PRIORITY. Context from analysis: $(cat analysis.json). $prior_art_context" 2>&1) || {
      echo "WARNING: PRD generation failed:" >&2
      echo "$prd_output" | tail -10 >&2
  }
```

**Step 2: Verify no regressions**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 3: Verify line count**

Run: `wc -l scripts/auto-compound.sh`
Expected: Under 300 lines

**Step 4: Commit**

```bash
git add scripts/auto-compound.sh
git commit -m "feat: wire prior-art search into auto-compound.sh before PRD generation"
```

## Batch 5: New Capabilities — Failure Digest and Structured Context

Add intelligent failure analysis and structured cross-batch dependencies.

### Task 16: Create failure-digest.sh

**Files:**
- Create: `scripts/failure-digest.sh`
- Create: `scripts/tests/test-failure-digest.sh`

**Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# Test failure-digest.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIGEST_SCRIPT="$SCRIPT_DIR/../failure-digest.sh"

FAILURES=0
TESTS=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    TESTS=$((TESTS + 1))
    if [[ "$expected" != "$actual" ]]; then
        echo "FAIL: $desc"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAILURES=$((FAILURES + 1))
    else
        echo "PASS: $desc"
    fi
}

WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT

# Create a fake log with errors
cat > "$WORK/batch-1-attempt-1.log" << 'LOG'
Some setup output...
FAILED tests/test_auth.py::test_login - AssertionError: expected 200 got 401
FAILED tests/test_auth.py::test_signup - KeyError: 'email'
Traceback (most recent call last):
  File "src/auth.py", line 42, in login
    token = generate_token(user)
TypeError: generate_token() missing 1 required argument: 'secret'
3 failed, 10 passed in 5.2s
LOG

# --- Test: extracts failed test names ---
output=$(bash "$DIGEST_SCRIPT" "$WORK/batch-1-attempt-1.log")
echo "$output" | grep -q "test_login" && echo "PASS: found test_login" && TESTS=$((TESTS + 1)) || {
    echo "FAIL: missing test_login"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1))
}

echo "$output" | grep -q "test_signup" && echo "PASS: found test_signup" && TESTS=$((TESTS + 1)) || {
    echo "FAIL: missing test_signup"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1))
}

# --- Test: extracts error types ---
echo "$output" | grep -q "TypeError" && echo "PASS: found TypeError" && TESTS=$((TESTS + 1)) || {
    echo "FAIL: missing TypeError"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1))
}

# --- Test: help flag ---
bash "$DIGEST_SCRIPT" --help >/dev/null 2>&1
TESTS=$((TESTS + 1))
echo "PASS: --help exits cleanly"

# === Summary ===
echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
```

**Step 2: Run test to verify failure**

Run: `bash scripts/tests/test-failure-digest.sh`
Expected: FAIL — script does not exist

**Step 3: Write implementation**

Create `scripts/failure-digest.sh`:

```bash
#!/usr/bin/env bash
# failure-digest.sh — Parse failed batch logs into structured failure digest
#
# Usage: failure-digest.sh <log-file>
#
# Extracts:
#   - Failed test names (FAILED pattern)
#   - Error types and messages (Traceback, Error:, Exception:)
#   - Test summary line (N failed, M passed)
#
# Output: Structured text digest suitable for retry prompts
set -euo pipefail

LOG_FILE="${1:-}"

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "failure-digest.sh — Parse batch log into structured failure digest"
    echo "Usage: failure-digest.sh <log-file>"
    exit 0
fi

if [[ -z "$LOG_FILE" || ! -f "$LOG_FILE" ]]; then
    echo "Error: Log file required" >&2
    exit 1
fi

echo "=== Failure Digest ==="
echo "Log: $(basename "$LOG_FILE")"
echo ""

# Extract failed test names
echo "--- Failed Tests ---"
grep -E '^FAILED ' "$LOG_FILE" 2>/dev/null | sed 's/^FAILED /  /' || echo "  (none found)"
echo ""

# Extract error types and messages
echo "--- Errors ---"
grep -E '(Error|Exception|FAIL):' "$LOG_FILE" 2>/dev/null | grep -v '^FAILED ' | head -20 | sed 's/^/  /' || echo "  (none found)"
echo ""

# Extract tracebacks (last frame + error line)
echo "--- Stack Traces (last frame) ---"
grep -B1 -E '^\w+Error:|^\w+Exception:' "$LOG_FILE" 2>/dev/null | head -20 | sed 's/^/  /' || echo "  (none found)"
echo ""

# Extract test summary
echo "--- Summary ---"
grep -E '\d+ (failed|passed|error)' "$LOG_FILE" 2>/dev/null | tail -1 | sed 's/^/  /' || echo "  (no summary found)"
echo ""

echo "=== End Digest ==="
```

**Step 4: Run tests**

Run: `bash scripts/tests/test-failure-digest.sh`
Expected: ALL PASSED

**Step 5: Wire into run-plan-headless.sh**

In `scripts/lib/run-plan-headless.sh`, replace the naive `tail -50` in the retry prompt (the section that builds `log_tail` for attempt >= 3):

```bash
            elif [[ $attempt -ge 3 ]]; then
                local prev_log="$WORKTREE/logs/batch-${batch}-attempt-$((attempt - 1)).log"
                local log_digest=""
                if [[ -f "$prev_log" ]]; then
                    log_digest=$("$SCRIPT_DIR/failure-digest.sh" "$prev_log" 2>/dev/null || tail -50 "$prev_log" 2>/dev/null || true)
                fi
```

**Step 6: Commit**

```bash
chmod +x scripts/failure-digest.sh
git add scripts/failure-digest.sh scripts/tests/test-failure-digest.sh scripts/lib/run-plan-headless.sh
git commit -m "feat: create failure-digest.sh, wire into retry prompts replacing naive tail -50"
```

### Task 17: Add context_refs support to plan parser

**Files:**
- Modify: `scripts/lib/run-plan-parser.sh` (add `get_batch_context_refs` function)
- Modify: `scripts/lib/run-plan-prompt.sh` (include context_refs file contents in prompt)
- Modify: `scripts/tests/test-run-plan-parser.sh` (add context_refs tests)

**Step 1: Add failing test**

Add to `scripts/tests/test-run-plan-parser.sh`:

```bash
# === get_batch_context_refs tests ===

# Create a plan with context_refs
cat > "$WORK/refs-plan.md" << 'PLAN'
## Batch 1: Setup

### Task 1: Create base
Content here.

## Batch 2: Build on base
context_refs: src/auth.py, tests/test_auth.py

### Task 2: Extend
Uses auth module from batch 1.
PLAN

# Batch 1 has no refs
val=$(get_batch_context_refs "$WORK/refs-plan.md" 1)
assert_eq "get_batch_context_refs: batch 1 has no refs" "" "$val"

# Batch 2 has refs
val=$(get_batch_context_refs "$WORK/refs-plan.md" 2)
echo "$val" | grep -q "src/auth.py" && echo "PASS: batch 2 refs include src/auth.py" && TESTS=$((TESTS + 1)) || {
    echo "FAIL: batch 2 refs missing src/auth.py"; TESTS=$((TESTS + 1)); FAILURES=$((FAILURES + 1))
}
```

**Step 2: Run test to verify failure**

Run: `bash scripts/tests/test-run-plan-parser.sh`
Expected: FAIL — `get_batch_context_refs` does not exist

**Step 3: Add function to parser**

Add to `scripts/lib/run-plan-parser.sh`:

```bash
get_batch_context_refs() {
    local plan_file="$1" batch_num="$2"
    local batch_text
    batch_text=$(get_batch_text "$plan_file" "$batch_num")
    # Extract "context_refs: file1, file2, ..." line
    local refs_line
    refs_line=$(echo "$batch_text" | grep -E '^context_refs:' | head -1 || true)
    if [[ -z "$refs_line" ]]; then
        echo ""
        return
    fi
    # Strip "context_refs: " prefix and split on comma
    echo "${refs_line#context_refs: }" | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//'
}
```

**Step 4: Update prompt builder to include context_refs**

In `scripts/lib/run-plan-prompt.sh`, add after the `progress_tail` section:

```bash
    # Cross-batch context: referenced files from context_refs
    local context_refs_content=""
    local refs
    refs=$(get_batch_context_refs "$plan_file" "$batch_num")
    if [[ -n "$refs" ]]; then
        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            if [[ -f "$worktree/$ref" ]]; then
                context_refs_content+="
--- $ref ---
$(head -100 "$worktree/$ref")
"
            fi
        done <<< "$refs"
    fi
```

And add to the prompt output:
```bash
$(if [[ -n "$context_refs_content" ]]; then
echo "
Referenced files from prior batches:
${context_refs_content}"
fi)
```

**Step 5: Run tests**

Run: `bash scripts/tests/test-run-plan-parser.sh && bash scripts/tests/test-run-plan-prompt.sh`
Expected: ALL PASSED

**Step 6: Commit**

```bash
git add scripts/lib/run-plan-parser.sh scripts/lib/run-plan-prompt.sh scripts/tests/test-run-plan-parser.sh
git commit -m "feat: add context_refs support for cross-batch file dependencies in plans"
```

## Batch 6: License Check and Final Wiring

Add license checking, wire all new gates, and ensure the full pipeline works end-to-end.

### Task 18: Create license-check.sh

**Files:**
- Create: `scripts/license-check.sh`

**Step 1: Write the script**

```bash
#!/usr/bin/env bash
# license-check.sh — Check dependencies for license compatibility
#
# Usage: license-check.sh [--project-root <dir>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="."

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project-root) PROJECT_ROOT="$2"; shift 2 ;;
        -h|--help)
            echo "license-check.sh — Check dependency licenses"
            echo "Usage: license-check.sh [--project-root <dir>]"
            echo "Flags GPL/AGPL in MIT-licensed projects."
            exit 0 ;;
        *) echo "Unknown: $1" >&2; exit 1 ;;
    esac
done

cd "$PROJECT_ROOT"
project_type=$(detect_project_type ".")

echo "=== License Check ==="
violations=0

case "$project_type" in
    python)
        if [[ -d ".venv" ]] && command -v pip-licenses >/dev/null 2>&1; then
            echo "Checking Python dependencies..."
            gpl_deps=$(.venv/bin/python -m pip-licenses --format=csv 2>/dev/null | grep -iE 'GPL|AGPL' | grep -v 'LGPL' || true)
            if [[ -n "$gpl_deps" ]]; then
                echo "WARNING: GPL/AGPL dependencies found:"
                echo "$gpl_deps" | sed 's/^/  /'
                violations=$((violations + 1))
            else
                echo "  No GPL/AGPL dependencies"
            fi
        else
            echo "  pip-licenses not available — skipping"
        fi
        ;;
    node)
        if command -v npx >/dev/null 2>&1; then
            echo "Checking Node dependencies..."
            gpl_deps=$(npx license-checker --csv 2>/dev/null | grep -iE 'GPL|AGPL' | grep -v 'LGPL' || true)
            if [[ -n "$gpl_deps" ]]; then
                echo "WARNING: GPL/AGPL dependencies found:"
                echo "$gpl_deps" | head -10 | sed 's/^/  /'
                violations=$((violations + 1))
            else
                echo "  No GPL/AGPL dependencies"
            fi
        else
            echo "  license-checker not available — skipping"
        fi
        ;;
    *)
        echo "  No license check for project type: $project_type"
        ;;
esac

if [[ $violations -gt 0 ]]; then
    echo ""
    echo "license-check: $violations issue(s) found"
    exit 1
fi

echo "license-check: CLEAN"
exit 0
```

**Step 2: Test manually**

Run: `bash scripts/license-check.sh --help`
Expected: Help text, exit 0

**Step 3: Commit**

```bash
chmod +x scripts/license-check.sh
git add scripts/license-check.sh
git commit -m "feat: create license-check.sh for dependency license auditing"
```

### Task 19: Wire all new gates into quality-gate.sh

**Files:**
- Modify: `scripts/quality-gate.sh` (add `--with-license` and `--quick` flags)

**Step 1: Add flag parsing**

Add `QUICK=false` and `WITH_LICENSE=false` to defaults. Add to arg parser:
```bash
        --quick) QUICK=true; shift ;;
        --with-license) WITH_LICENSE=true; shift ;;
```

**Step 2: Add conditional checks**

If `--quick` is set, skip lint and license checks. If `--with-license` is set, add license check after tests:

```bash
# === Optional: License Check ===
if [[ "$WITH_LICENSE" == true ]]; then
    echo ""
    echo "=== Quality Gate: License Check ==="
    if ! "$SCRIPT_DIR/license-check.sh" --project-root "$PROJECT_ROOT"; then
        echo "quality-gate: FAILED at license check"
        exit 1
    fi
fi
```

If `--quick`, wrap the lint section in:
```bash
if [[ "$QUICK" != true ]]; then
    # lint check here
fi
```

**Step 3: Run tests**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED

**Step 4: Verify line count**

Run: `wc -l scripts/quality-gate.sh`
Expected: Under 300 lines

**Step 5: Commit**

```bash
git add scripts/quality-gate.sh
git commit -m "feat: add --quick and --with-license flags to quality-gate.sh"
```

### Task 20: Update run-all-tests.sh to discover new test files

**Files:**
- Modify: `scripts/tests/run-all-tests.sh` (expand glob to include non-run-plan tests)

**Step 1: Update test discovery**

Change line 13 from:
```bash
mapfile -t TEST_FILES < <(find "$SCRIPT_DIR" -maxdepth 1 -name "test-run-plan-*.sh" -type f | sort)
```
to:
```bash
mapfile -t TEST_FILES < <(find "$SCRIPT_DIR" -maxdepth 1 -name "test-*.sh" -type f | sort)
```

This picks up `test-common.sh`, `test-ollama.sh`, `test-telegram.sh`, `test-prior-art-search.sh`, and `test-failure-digest.sh`.

**Step 2: Run full test suite**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL new and existing tests discovered and PASSED

**Step 3: Commit**

```bash
git add scripts/tests/run-all-tests.sh
git commit -m "fix: run-all-tests.sh discovers all test-*.sh files, not just run-plan tests"
```

## Batch 7: Integration Wiring + Final Verification

Wire all components together and verify the full pipeline works end-to-end.

### Task 21: Verify all scripts under 300 lines

**Step 1: Check line counts**

Run: `wc -l scripts/*.sh scripts/lib/*.sh | sort -n`

Expected: Every file under 300 lines. If any violations remain, refactor.

**Step 2: Commit any fixes**

```bash
git add -A && git commit -m "fix: ensure all scripts under 300-line limit"
```

### Task 22: Run full test suite and verify

**Step 1: Run all tests**

Run: `bash scripts/tests/run-all-tests.sh`
Expected: ALL PASSED with zero failures

**Step 2: Run quality gate on this project**

Run: `bash scripts/quality-gate.sh --project-root .`
Expected: ALL PASSED

### Task 23: Run pipeline-status.sh to verify integration

**Step 1: Run pipeline status**

Run: `bash scripts/pipeline-status.sh .`
Expected: Shows project status without errors

### Task 24: Update progress.txt with final summary

**Step 1: Append summary**

```bash
echo "## Code Factory v2 — Implementation Complete

### Phase 1: Foundation
- Created scripts/lib/common.sh (detect_project_type, strip_json_fences, check_memory_available, require_command)
- Created scripts/lib/ollama.sh (ollama_query, ollama_extract_json)
- Created scripts/lib/telegram.sh (extracted from run-plan-notify.sh)
- Refactored: quality-gate.sh, auto-compound.sh, analyze-report.sh, entropy-audit.sh
- Extracted run-plan-headless.sh from run-plan.sh (412 -> ~260 lines)

### Phase 2: Accuracy
- Fixed test count parsing for jest, go test, and unknown formats
- Added cross-batch context (git log, progress.txt, quality gate result) to prompts
- Added per-batch duration tracking to state
- Fixed PRD output discard in auto-compound.sh (lesson-7)

### Phase 3: Quality Gates
- Added ruff/eslint lint step to quality-gate.sh
- Created prior-art-search.sh (GitHub + local search)
- Created license-check.sh
- Created pipeline-status.sh
- Wired prior-art search into auto-compound.sh

### Phase 4: New Capabilities
- Created failure-digest.sh (replaces naive tail -50 in retries)
- Added context_refs support for cross-batch file dependencies
- All scripts under 300 lines
" >> progress.txt
```

**Step 2: Commit**

```bash
git add progress.txt
git commit -m "docs: update progress.txt with Code Factory v2 implementation summary"
```

### Task 25: Vertical pipeline trace

**Step 1: End-to-end dry run**

Run the full auto-compound pipeline in dry-run mode to verify all components are wired:

```bash
bash scripts/auto-compound.sh . --dry-run --report reports/daily.md
```

Verify output shows: analyze → search → PRD → quality gate → Ralph loop → PR

If no report file exists, create a minimal one for the trace:
```bash
echo "# Test Report\n## Issue: Test pipeline integration" > /tmp/test-report.md
bash scripts/auto-compound.sh . --dry-run --report /tmp/test-report.md
```

**Step 2: Final commit**

```bash
git add -A && git commit -m "feat: Code Factory v2 complete — all phases implemented and verified"
```
