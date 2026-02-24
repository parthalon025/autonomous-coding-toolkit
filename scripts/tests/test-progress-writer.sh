#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
source "$SCRIPT_DIR/../lib/progress-writer.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# === write_batch_progress tests ===

# Test: writes batch header with timestamp
write_batch_progress "$WORK" 1 "Foundation setup"
content=$(cat "$WORK/progress.txt")
assert_contains "write_batch_progress: creates progress.txt" "## Batch 1: Foundation setup" "$content"
assert_contains "write_batch_progress: includes timestamp" "T" "$content"

# Test: appending second batch header
write_batch_progress "$WORK" 2 "Add tests"
content=$(cat "$WORK/progress.txt")
assert_contains "write_batch_progress: batch 2 header present" "## Batch 2: Add tests" "$content"
assert_contains "write_batch_progress: batch 1 still present" "## Batch 1: Foundation setup" "$content"

# === append_progress_section tests ===

# Test: append Files Modified section
append_progress_section "$WORK" "Files Modified" "- scripts/lib/foo.sh (created)
- scripts/lib/bar.sh (modified)"
content=$(cat "$WORK/progress.txt")
assert_contains "append_progress_section: Files Modified header" "### Files Modified" "$content"
assert_contains "append_progress_section: file list content" "scripts/lib/foo.sh (created)" "$content"

# Test: append Decisions section
append_progress_section "$WORK" "Decisions" "- Used awk for parsing: simpler than sed for multi-line extraction"
content=$(cat "$WORK/progress.txt")
assert_contains "append_progress_section: Decisions header" "### Decisions" "$content"
assert_contains "append_progress_section: decision content" "Used awk for parsing" "$content"

# Test: append Issues Encountered section
append_progress_section "$WORK" "Issues Encountered" "- shellcheck warning → added quotes"
content=$(cat "$WORK/progress.txt")
assert_contains "append_progress_section: Issues header" "### Issues Encountered" "$content"

# Test: append State section
append_progress_section "$WORK" "State" "- Tests: 12 passing
- Duration: 45s
- Cost: \$0.03"
content=$(cat "$WORK/progress.txt")
assert_contains "append_progress_section: State header" "### State" "$content"
assert_contains "append_progress_section: test count" "Tests: 12 passing" "$content"

# === read_batch_progress tests ===

# Test: read batch 1
batch1=$(read_batch_progress "$WORK" 1)
assert_contains "read_batch_progress: returns batch 1 header" "## Batch 1: Foundation setup" "$batch1"
assert_not_contains "read_batch_progress: excludes batch 2" "## Batch 2" "$batch1"

# Test: read batch 2 — should include all sections we appended
batch2=$(read_batch_progress "$WORK" 2)
assert_contains "read_batch_progress: returns batch 2 header" "## Batch 2: Add tests" "$batch2"
assert_contains "read_batch_progress: includes Files Modified" "### Files Modified" "$batch2"
assert_contains "read_batch_progress: includes Decisions" "### Decisions" "$batch2"
assert_contains "read_batch_progress: includes State" "### State" "$batch2"
assert_not_contains "read_batch_progress: excludes batch 1" "## Batch 1" "$batch2"

# Test: read nonexistent batch — returns empty, exit 1
batch99=""
batch99_exit=0
batch99=$(read_batch_progress "$WORK" 99) || batch99_exit=$?
assert_eq "read_batch_progress: nonexistent batch returns exit 1" "1" "$batch99_exit"
assert_eq "read_batch_progress: nonexistent batch returns empty" "" "$batch99"

# Test: read from nonexistent worktree — returns empty, exit 2
batch_none=""
batch_none_exit=0
batch_none=$(read_batch_progress "/tmp/nonexistent-worktree-$$" 1) || batch_none_exit=$?
assert_eq "read_batch_progress: missing progress.txt returns exit 2" "2" "$batch_none_exit"
assert_eq "read_batch_progress: missing progress.txt returns empty" "" "$batch_none"

# Test: invalid batch_num — returns exit 1 with error message
invalid_exit=0
invalid_out=""
invalid_out=$(read_batch_progress "$WORK" "abc" 2>&1) || invalid_exit=$?
assert_eq "read_batch_progress: invalid batch_num exits 1" "1" "$invalid_exit"
assert_contains "read_batch_progress: invalid batch_num prints error" "batch_num must be a positive integer" "$invalid_out"

# === Round-trip test with fresh worktree ===

WORK2=$(mktemp -d)
trap 'rm -rf "$WORK2"' EXIT
write_batch_progress "$WORK2" 1 "Round trip test"
append_progress_section "$WORK2" "Files Modified" "- a.sh (created)"
append_progress_section "$WORK2" "State" "- Tests: 5 passing"

roundtrip=$(read_batch_progress "$WORK2" 1)
assert_contains "round-trip: header preserved" "## Batch 1: Round trip test" "$roundtrip"
assert_contains "round-trip: files preserved" "a.sh (created)" "$roundtrip"
assert_contains "round-trip: state preserved" "Tests: 5 passing" "$roundtrip"

# === Multi-batch isolation test ===

WORK3=$(mktemp -d)
trap 'rm -rf "$WORK3"' EXIT
write_batch_progress "$WORK3" 1 "First"
append_progress_section "$WORK3" "State" "- Tests: 3 passing"
write_batch_progress "$WORK3" 2 "Second"
append_progress_section "$WORK3" "State" "- Tests: 7 passing"
write_batch_progress "$WORK3" 3 "Third"
append_progress_section "$WORK3" "State" "- Tests: 12 passing"

b1=$(read_batch_progress "$WORK3" 1)
b2=$(read_batch_progress "$WORK3" 2)
b3=$(read_batch_progress "$WORK3" 3)

assert_contains "multi-batch: batch 1 has 3 tests" "Tests: 3 passing" "$b1"
assert_not_contains "multi-batch: batch 1 excludes batch 2 state" "Tests: 7 passing" "$b1"
assert_contains "multi-batch: batch 2 has 7 tests" "Tests: 7 passing" "$b2"
assert_not_contains "multi-batch: batch 2 excludes batch 3 state" "Tests: 12 passing" "$b2"
assert_contains "multi-batch: batch 3 has 12 tests" "Tests: 12 passing" "$b3"

# === False-match prevention: content that looks like a batch header ===
# Content mentioning "## Batch N:" should NOT stop extraction early
# because the timestamp anchoring prevents it (#55)

WORK4=$(mktemp -d)
trap 'rm -rf "$WORK4"' EXIT
write_batch_progress "$WORK4" 1 "Content test"
# Manually write content that looks like a batch header (without timestamp)
echo "## Batch 2: This is just a note, not a real header" >> "$WORK4/progress.txt"
echo "- some progress note" >> "$WORK4/progress.txt"
write_batch_progress "$WORK4" 2 "Real second batch"
append_progress_section "$WORK4" "State" "- Tests: 9 passing"

b1_content=$(read_batch_progress "$WORK4" 1)
assert_contains "false-match: batch 1 includes embedded note" "This is just a note" "$b1_content"
assert_not_contains "false-match: batch 1 stops at real batch 2 header" "Tests: 9 passing" "$b1_content"

report_results
