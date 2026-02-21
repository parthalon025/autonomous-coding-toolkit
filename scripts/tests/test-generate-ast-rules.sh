#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

assert_contains() {
    local desc="$1" needle="$2" haystack="$3"
    TESTS=$((TESTS + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "PASS: $desc"
    else
        echo "FAIL: $desc"
        echo "  expected to contain: $needle"
        FAILURES=$((FAILURES + 1))
    fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Create test lesson files
mkdir -p "$WORK/lessons"

# Syntactic lesson (should be SKIPPED — grep handles these)
cat > "$WORK/lessons/0001-test.md" << 'LESSON'
---
id: 1
title: "Bare except"
severity: blocker
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "^\\s*except\\s*:"
  description: "bare except"
fix: "Use specific exception"
example:
  bad: |
    except:
        pass
  good: |
    except Exception as e:
        logger.error(e)
---
LESSON

# Semantic lesson with supported language (should generate rule)
cat > "$WORK/lessons/0033-async.md" << 'LESSON'
---
id: 33
title: "Async iteration mutable"
severity: blocker
languages: [python]
category: async-traps
pattern:
  type: semantic
  description: "async loop iterates over mutable instance attribute"
fix: "Snapshot with list()"
example:
  bad: |
    async for item in self.connections:
        await item.send(data)
  good: |
    for item in list(self.connections):
        await item.send(data)
---
LESSON

# Unsupported language lesson (should be skipped)
cat > "$WORK/lessons/0099-go.md" << 'LESSON'
---
id: 99
title: "Go error ignore"
severity: blocker
languages: [go]
category: silent-failures
pattern:
  type: semantic
  description: "ignoring error return value"
fix: "Handle the error"
example:
  bad: |
    result, _ := doThing()
  good: |
    result, err := doThing()
---
LESSON

# Test: generates pattern files from lessons
"$SCRIPT_DIR/../generate-ast-rules.sh" --lessons-dir "$WORK/lessons" --output-dir "$WORK/patterns"

# Syntactic lessons should NOT generate ast-grep rules (grep handles them)
assert_eq "generate-ast-rules: skips syntactic patterns" "false" \
    "$(test -f "$WORK/patterns/0001-test.yml" && echo true || echo false)"

# Semantic lesson with supported language should generate a rule
assert_eq "generate-ast-rules: generates for semantic python lesson" "true" \
    "$(test -f "$WORK/patterns/0033-async.yml" && echo true || echo false)"

# Unsupported language lesson should NOT generate
assert_eq "generate-ast-rules: skips unsupported language" "false" \
    "$(test -f "$WORK/patterns/0099-go.yml" && echo true || echo false)"

# Generated rule should contain lesson metadata
if [[ -f "$WORK/patterns/0033-async.yml" ]]; then
    rule_content=$(cat "$WORK/patterns/0033-async.yml")
    assert_contains "generate-ast-rules: rule has id" "0033-async" "$rule_content"
    assert_contains "generate-ast-rules: rule has message" "Async iteration mutable" "$rule_content"
    assert_contains "generate-ast-rules: rule has language" "python" "$rule_content"
fi

# Test: --list flag shows what would be generated
output=$("$SCRIPT_DIR/../generate-ast-rules.sh" --lessons-dir "$WORK/lessons" --list 2>&1)
assert_contains "generate-ast-rules: list shows lesson info" "lesson" "$output"
assert_contains "generate-ast-rules: list shows summary" "syntactic" "$output"

echo ""
echo "Results: $((TESTS - FAILURES))/$TESTS passed"
if [[ $FAILURES -gt 0 ]]; then
    echo "FAILURES: $FAILURES"
    exit 1
fi
echo "ALL PASSED"
