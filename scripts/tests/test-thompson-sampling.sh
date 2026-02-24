#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# Source the library under test
source "$SCRIPT_DIR/../lib/thompson-sampling.sh"

# --- Test: thompson_sample returns float in [0,1] ---
sample=$(thompson_sample 10 5)
TESTS=$((TESTS + 1))
# Check it's a valid float between 0 and 1 using bc
is_valid=$(echo "$sample >= 0 && $sample <= 1" | bc -l 2>/dev/null || echo "0")
if [[ "$is_valid" == "1" ]]; then
    echo "PASS: thompson_sample 10 5 returns float in [0,1] (got $sample)"
else
    echo "FAIL: thompson_sample 10 5 returned '$sample' (expected float in [0,1])"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: thompson_route returns "mab" when perf file missing ---
route_missing=$(thompson_route "new-file" "/tmp/nonexistent-perf-$$.json")
assert_eq "missing perf file → mab" "mab" "$route_missing"

# --- Test: thompson_route returns "mab" when type has < 5 data points ---
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

cat > "$TEST_TMPDIR/perf.json" <<'JSON'
{
  "new-file": {"superpowers": {"wins": 2, "losses": 1}, "ralph": {"wins": 1, "losses": 0}},
  "refactoring": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "integration": {"superpowers": {"wins": 5, "losses": 2}, "ralph": {"wins": 3, "losses": 4}},
  "test-only": {"superpowers": {"wins": 0, "losses": 0}, "ralph": {"wins": 0, "losses": 0}},
  "calibration_count": 0,
  "calibration_complete": false
}
JSON

route_few=$(thompson_route "new-file" "$TEST_TMPDIR/perf.json")
assert_eq "< 5 data points → mab" "mab" "$route_few"

# --- Test: thompson_route returns "mab" for integration type (always explore) ---
cat > "$TEST_TMPDIR/perf-int.json" <<'JSON'
{
  "new-file": {"superpowers": {"wins": 10, "losses": 2}, "ralph": {"wins": 3, "losses": 9}},
  "refactoring": {"superpowers": {"wins": 10, "losses": 2}, "ralph": {"wins": 3, "losses": 9}},
  "integration": {"superpowers": {"wins": 10, "losses": 2}, "ralph": {"wins": 3, "losses": 9}},
  "test-only": {"superpowers": {"wins": 10, "losses": 2}, "ralph": {"wins": 3, "losses": 9}},
  "calibration_count": 10,
  "calibration_complete": true
}
JSON

route_int=$(thompson_route "integration" "$TEST_TMPDIR/perf-int.json")
assert_eq "integration type → always mab" "mab" "$route_int"

# --- Test: thompson_route returns winning strategy with strong signal ---
# superpowers: 15 wins / 3 losses = 83% win rate, 18 total points
# ralph: 3 wins / 15 losses = 17% win rate
# Run 10 times and check majority goes to superpowers
superpowers_count=0
for i in $(seq 1 10); do
    result=$(thompson_route "new-file" "$TEST_TMPDIR/perf-int.json")
    if [[ "$result" == "superpowers" ]]; then
        superpowers_count=$((superpowers_count + 1))
    fi
done

TESTS=$((TESTS + 1))
if [[ "$superpowers_count" -ge 7 ]]; then
    echo "PASS: strong signal routes to winner (superpowers won $superpowers_count/10)"
else
    echo "FAIL: strong signal should route to superpowers ≥7/10 times (got $superpowers_count/10)"
    FAILURES=$((FAILURES + 1))
fi

# --- Test: init_strategy_perf creates valid JSON ---
init_file="$TEST_TMPDIR/init-perf.json"
init_strategy_perf "$init_file"

TESTS=$((TESTS + 1))
if [[ -f "$init_file" ]] && jq . "$init_file" > /dev/null 2>&1; then
    echo "PASS: init_strategy_perf creates valid JSON"
else
    echo "FAIL: init_strategy_perf did not create valid JSON"
    FAILURES=$((FAILURES + 1))
fi

# Check all 4 batch types present
for bt in "new-file" "refactoring" "integration" "test-only"; do
    has_type=$(jq --arg bt "$bt" 'has($bt)' "$init_file" 2>/dev/null)
    assert_eq "init has $bt type" "true" "$has_type"
done

# Check calibration fields
has_cal_count=$(jq 'has("calibration_count")' "$init_file" 2>/dev/null)
assert_eq "init has calibration_count" "true" "$has_cal_count"

has_cal_complete=$(jq 'has("calibration_complete")' "$init_file" 2>/dev/null)
assert_eq "init has calibration_complete" "true" "$has_cal_complete"

# --- Test: update_strategy_perf increments wins/losses ---
update_file="$TEST_TMPDIR/update-perf.json"
init_strategy_perf "$update_file"

# Superpowers wins a new-file batch
update_strategy_perf "$update_file" "new-file" "superpowers"
sp_wins=$(jq '."new-file".superpowers.wins' "$update_file" 2>/dev/null)
assert_eq "superpowers wins incremented" "1" "$sp_wins"

# Ralph loses (the other side)
ralph_losses=$(jq '."new-file".ralph.losses' "$update_file" 2>/dev/null)
assert_eq "ralph losses incremented" "1" "$ralph_losses"

# Do it again
update_strategy_perf "$update_file" "new-file" "superpowers"
sp_wins2=$(jq '."new-file".superpowers.wins' "$update_file" 2>/dev/null)
assert_eq "superpowers wins incremented again" "2" "$sp_wins2"

# --- Test: thompson_route spread-too-close returns "mab" ---
# When both strategies have similar win rates (spread < 15%), route to mab.
# superpowers: 6W/4L = 60%, ralph: 5W/5L = 50% → spread = 10% < 15% → "mab"
cat > "$TEST_TMPDIR/perf-close.json" <<'JSON'
{
  "new-file": {"superpowers": {"wins": 6, "losses": 4}, "ralph": {"wins": 5, "losses": 5}},
  "refactoring": {"superpowers": {"wins": 6, "losses": 4}, "ralph": {"wins": 5, "losses": 5}},
  "integration": {"superpowers": {"wins": 6, "losses": 4}, "ralph": {"wins": 5, "losses": 5}},
  "test-only": {"superpowers": {"wins": 6, "losses": 4}, "ralph": {"wins": 5, "losses": 5}},
  "calibration_count": 20,
  "calibration_complete": true
}
JSON

route_close=$(thompson_route "new-file" "$TEST_TMPDIR/perf-close.json")
assert_eq "spread < 15% → mab (too close to call)" "mab" "$route_close"

report_results
