#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

ARCH_MAP="$SCRIPT_DIR/../architecture-map.sh"

# --- Test: --help exits 0 and mentions ARCHITECTURE-MAP.json ---
help_output=$("$ARCH_MAP" --help 2>&1) || true
assert_exit "--help exits 0" 0 "$ARCH_MAP" --help
assert_contains "--help mentions ARCHITECTURE-MAP.json" "ARCHITECTURE-MAP.json" "$help_output"

# --- Test: generates valid JSON from a temp project ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Create a minimal project with shell + python files
mkdir -p "$TMPDIR/lib" "$TMPDIR/src"
cat > "$TMPDIR/main.sh" <<'SH'
#!/usr/bin/env bash
source lib/helpers.sh
echo "hello"
SH
cat > "$TMPDIR/lib/helpers.sh" <<'SH'
#!/usr/bin/env bash
helper_func() { echo "help"; }
SH
cat > "$TMPDIR/src/app.py" <<'PY'
from src.utils import do_thing
import os

def main():
    do_thing()
PY
cat > "$TMPDIR/src/utils.py" <<'PY'
def do_thing():
    pass
PY

# Run architecture-map on the temp project
map_exit=0
"$ARCH_MAP" --project-root "$TMPDIR" > /dev/null 2>&1 || map_exit=$?
assert_eq "generates map exit 0" "0" "$map_exit"

# Check output file exists
output_file="$TMPDIR/docs/ARCHITECTURE-MAP.json"
TESTS=$((TESTS + 1))
if [[ -f "$output_file" ]]; then
    echo "PASS: creates docs/ARCHITECTURE-MAP.json"
else
    echo "FAIL: docs/ARCHITECTURE-MAP.json not found"
    FAILURES=$((FAILURES + 1))
fi

# Check JSON is valid
json_valid=0
jq . "$output_file" > /dev/null 2>&1 || json_valid=1
assert_eq "output is valid JSON" "0" "$json_valid"

# Check required fields
has_generated=$(jq 'has("generated_at")' "$output_file" 2>/dev/null)
assert_eq "JSON has generated_at field" "true" "$has_generated"

has_modules=$(jq 'has("modules")' "$output_file" 2>/dev/null)
assert_eq "JSON has modules field" "true" "$has_modules"

# Check shell source dependency detected
source_deps=$(jq -r '[.modules[].files[]? | select(.dependencies[]? | contains("lib/helpers.sh"))] | length' "$output_file" 2>/dev/null || echo "0")
TESTS=$((TESTS + 1))
if [[ "$source_deps" -gt 0 ]]; then
    echo "PASS: detects shell source dependencies"
else
    echo "FAIL: did not detect shell source dependency on lib/helpers.sh"
    echo "  JSON: $(cat "$output_file")"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: empty project produces empty modules, exits 0 ---
EMPTY_DIR=$(mktemp -d)
empty_exit=0
"$ARCH_MAP" --project-root "$EMPTY_DIR" > /dev/null 2>&1 || empty_exit=$?
assert_eq "empty project exits 0" "0" "$empty_exit"

empty_modules=$(jq '.modules | length' "$EMPTY_DIR/docs/ARCHITECTURE-MAP.json" 2>/dev/null || echo "-1")
assert_eq "empty project has 0 modules" "0" "$empty_modules"
rm -rf "$EMPTY_DIR"

report_results
