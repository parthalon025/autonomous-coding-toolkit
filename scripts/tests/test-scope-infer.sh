#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

INFER="$SCRIPT_DIR/../scope-infer.sh"

# --- Test: --help exits 0 ---
assert_exit "--help exits 0" 0 "$INFER" --help

# --- Test: --dry-run shows proposed scope without modifying files ---
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create a lesson with no scope field, mentioning "HA" and "entity"
cat > "$WORK/0099-test-ha-lesson.md" <<'LESSON'
---
id: 99
title: "HA entity resolution fails on restart"
severity: should-fix
languages: [python]
category: data-model
pattern:
  type: semantic
  description: "HA entity lookup returns stale area"
fix: "Refresh entity registry on restart"
---

## Observation
Home Assistant entity area resolution uses a cached registry.
LESSON

dry_output=$("$INFER" --dir "$WORK" --dry-run 2>&1 || true)
assert_contains "--dry-run mentions ha-aria" "domain:ha-aria" "$dry_output"

# Verify file was NOT modified (dry run)
TESTS=$((TESTS + 1))
if grep -q '^scope:' "$WORK/0099-test-ha-lesson.md" 2>/dev/null; then
    echo "FAIL: --dry-run should not modify lesson files"
    FAILURES=$((FAILURES + 1))
else
    echo "PASS: --dry-run does not modify lesson files"
fi

# --- Test: --apply writes scope field to lesson ---
"$INFER" --dir "$WORK" --apply > /dev/null 2>&1 || true

TESTS=$((TESTS + 1))
if grep -q '^scope:' "$WORK/0099-test-ha-lesson.md" 2>/dev/null; then
    echo "PASS: --apply writes scope field to lesson"
else
    echo "FAIL: --apply should write scope field to lesson"
    FAILURES=$((FAILURES + 1))
fi

# Verify inferred scope is correct
scope_line=$(grep '^scope:' "$WORK/0099-test-ha-lesson.md" 2>/dev/null || true)
assert_contains "--apply infers domain:ha-aria" "domain:ha-aria" "$scope_line"

# --- Test: Lesson with existing scope is not modified ---
cat > "$WORK/0098-already-scoped.md" <<'LESSON'
---
id: 98
title: "Already scoped lesson"
severity: should-fix
scope: [language:python]
languages: [python]
category: silent-failures
pattern:
  type: semantic
  description: "test"
fix: "test"
---
LESSON

apply_output=$("$INFER" --dir "$WORK" --apply 2>&1 || true)
scope_line=$(grep '^scope:' "$WORK/0098-already-scoped.md" 2>/dev/null || true)
assert_contains "existing scope preserved" "language:python" "$scope_line"

# --- Test: Python-only lesson with no domain signals → language:python ---
cat > "$WORK/0097-python-only.md" <<'LESSON'
---
id: 97
title: "Generic Python anti-pattern"
severity: should-fix
languages: [python]
category: async-traps
pattern:
  type: syntactic
  regex: "some_pattern"
  description: "test"
fix: "test"
---

## Observation
This is a generic Python lesson with no domain signals.
LESSON

"$INFER" --dir "$WORK" --apply > /dev/null 2>&1 || true
scope_line=$(grep '^scope:' "$WORK/0097-python-only.md" 2>/dev/null || true)
assert_contains "python-only → language:python" "language:python" "$scope_line"

# --- Test: No signals → universal ---
cat > "$WORK/0096-universal.md" <<'LESSON'
---
id: 96
title: "Generic coding practice"
severity: nice-to-have
languages: [all]
category: test-anti-patterns
pattern:
  type: syntactic
  regex: "some_other_pattern"
  description: "test"
fix: "test"
---

## Observation
This applies to all projects everywhere.
LESSON

"$INFER" --dir "$WORK" --apply > /dev/null 2>&1 || true
scope_line=$(grep '^scope:' "$WORK/0096-universal.md" 2>/dev/null || true)
assert_contains "no signals → universal" "universal" "$scope_line"

# --- Test: Summary output shows counts ---
WORK2=$(mktemp -d)
trap 'rm -rf "$WORK" "$WORK2"' EXIT

cat > "$WORK2/0001-test.md" <<'LESSON'
---
id: 1
title: "Test lesson"
severity: should-fix
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "test"
  description: "test"
fix: "test"
---
Generic content.
LESSON

summary_output=$("$INFER" --dir "$WORK2" --dry-run 2>&1 || true)
assert_contains "summary shows count" "Inferred scope for" "$summary_output"

report_results
