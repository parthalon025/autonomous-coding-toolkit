#!/usr/bin/env bash
# Test validate-hooks.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

VALIDATOR="$SCRIPT_DIR/../validate-hooks.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Helper: create hooks dir with hooks.json
create_hooks() {
    local content="$1"
    mkdir -p "$WORK/hooks"
    echo "$content" > "$WORK/hooks/hooks.json"
}

# Helper: create a script file (optionally executable)
create_script() {
    local path="$1" executable="${2:-true}"
    mkdir -p "$(dirname "$WORK/$path")"
    echo '#!/usr/bin/env bash' > "$WORK/$path"
    if [[ "$executable" == "true" ]]; then chmod +x "$WORK/$path"; fi
}

# Helper: run validator against temp dir
run_validator() {
    local exit_code=0
    HOOKS_DIR="$WORK/hooks" TOOLKIT_ROOT="$WORK" bash "$VALIDATOR" "$@" 2>&1 || exit_code=$?
    echo "EXIT:$exit_code"
}

# === Test: Valid hooks.json with existing executable script passes ===
create_hooks '{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/stop-hook.sh"}]}]
  }
}'
create_script "hooks/stop-hook.sh"

output=$(run_validator)
assert_contains "valid hooks: PASS" "validate-hooks: PASS" "$output"
assert_contains "valid hooks: exit 0" "EXIT:0" "$output"

# === Test: Nonexistent script fails ===
create_hooks '{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/missing.sh"}]}]
  }
}'

output=$(run_validator)
assert_contains "missing script: reports violation" "script not found" "$output"
assert_contains "missing script: exit 1" "EXIT:1" "$output"

# === Test: Non-executable script fails ===
create_hooks '{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/not-exec.sh"}]}]
  }
}'
create_script "hooks/not-exec.sh" "false"

output=$(run_validator)
assert_contains "not executable: reports violation" "not executable" "$output"
assert_contains "not executable: exit 1" "EXIT:1" "$output"

# === Test: Invalid JSON fails ===
create_hooks '{invalid json'

output=$(run_validator)
assert_contains "invalid JSON: error" "hooks.json is not valid JSON" "$output"
assert_contains "invalid JSON: exit 1" "EXIT:1" "$output"

# === Test: Missing hooks.json fails ===
rm -rf "$WORK/hooks"
output=$(HOOKS_DIR="$WORK/nonexistent" TOOLKIT_ROOT="$WORK" bash "$VALIDATOR" 2>&1 || echo "EXIT:$?")
assert_contains "missing dir: error message" "hooks directory not found" "$output"
assert_contains "missing dir: exit 1" "EXIT:1" "$output"

# === Test: --warn exits 0 even with violations ===
create_hooks '{
  "hooks": {
    "Stop": [{"hooks": [{"type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/missing.sh"}]}]
  }
}'

output=$(run_validator --warn)
assert_contains "--warn: still reports violation" "script not found" "$output"
assert_contains "--warn: exits 0" "EXIT:0" "$output"

# === Test: --help exits 0 ===
output=$(run_validator --help)
assert_contains "--help: shows usage" "Usage:" "$output"
assert_contains "--help: exits 0" "EXIT:0" "$output"

report_results
