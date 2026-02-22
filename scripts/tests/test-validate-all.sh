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

# === Test: Actual toolkit passes strict (no --warn) ===
output=$(bash "$VALIDATOR" 2>&1 || echo "EXIT:$?")
assert_contains "actual toolkit strict: shows summary" "validators passed" "$output"
assert_not_contains "actual toolkit strict: exit 0" "EXIT:" "$output"

# === Test: --help exits 0 ===
output=$(bash "$VALIDATOR" --help 2>&1 || echo "EXIT:$?")
assert_contains "--help: shows usage" "Usage:" "$output"
assert_not_contains "--help: exit 0" "EXIT:" "$output"

# === Test: Reports FAIL and exits 1 when a validator fails ===
# Create a controlled fixture with an invalid skill to trigger failure
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
# Create a minimal toolkit structure with a broken skill
mkdir -p "$TMP_DIR/skills/broken-skill"
# Empty dir = missing SKILL.md → validate-skills fails
# Create stub validators that pass, except skills points to our broken fixture
mkdir -p "$TMP_DIR/scripts"
for v in validate-lessons validate-commands validate-plugin validate-hooks; do
    echo '#!/usr/bin/env bash' > "$TMP_DIR/scripts/${v}.sh"
    echo 'echo "'"$v"': PASS"; exit 0' >> "$TMP_DIR/scripts/${v}.sh"
done
# validate-skills uses SKILLS_DIR env — point to broken fixture
echo '#!/usr/bin/env bash' > "$TMP_DIR/scripts/validate-skills.sh"
echo 'echo "broken-skill: Missing SKILL.md"; echo "validate-skills: FAIL"; exit 1' >> "$TMP_DIR/scripts/validate-skills.sh"
# Copy validate-all.sh to the temp dir
cp "$VALIDATOR" "$TMP_DIR/scripts/validate-all.sh"
output=$(bash "$TMP_DIR/scripts/validate-all.sh" 2>&1 || echo "EXIT:$?")
assert_contains "reports failures: exit 1" "EXIT:1" "$output"
assert_contains "reports failures: shows Failed" "Failed:" "$output"

report_results
