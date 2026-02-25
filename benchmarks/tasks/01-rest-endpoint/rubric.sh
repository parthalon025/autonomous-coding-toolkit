#!/usr/bin/env bash
# Rubric for 01-rest-endpoint benchmark
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
