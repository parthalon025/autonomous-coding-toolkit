#!/usr/bin/env bash
# Test validate-all.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

VALIDATOR="$SCRIPT_DIR/../validate-all.sh"

# === Test: Runs on actual toolkit with --warn and reports summary ===
output=$(bash "$VALIDATOR" --warn 2>&1 || echo "EXIT:$?")
assert_contains "actual toolkit --warn: shows summary" "validators passed" "$output"
assert_not_contains "actual toolkit --warn: exit 0" "EXIT:" "$output"

# === Test: Reports individual validator names ===
output=$(bash "$VALIDATOR" --warn 2>&1 || echo "EXIT:$?")
assert_contains "shows lessons" "validate-lessons" "$output"
assert_contains "shows skills" "validate-skills" "$output"
assert_contains "shows commands" "validate-commands" "$output"
assert_contains "shows plugin" "validate-plugin" "$output"
assert_contains "shows hooks" "validate-hooks" "$output"

# === Test: --help exits 0 ===
output=$(bash "$VALIDATOR" --help 2>&1 || echo "EXIT:$?")
assert_contains "--help: shows usage" "Usage:" "$output"
assert_not_contains "--help: exit 0" "EXIT:" "$output"

# === Test: Reports FAIL and exits 1 when a validator fails ===
# Run without --warn — validate-skills has pre-existing issues
output=$(bash "$VALIDATOR" 2>&1 || echo "EXIT:$?")
assert_contains "reports failures: exit 1" "EXIT:1" "$output"
assert_contains "reports failures: shows Failed" "Failed:" "$output"

report_results
