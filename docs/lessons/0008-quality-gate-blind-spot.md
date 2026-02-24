---
id: 8
title: "Quality gate blind spot for non-standard test suites"
severity: should-fix
languages: [shell, all]
scope: [project:autonomous-coding-toolkit]
category: silent-failures
pattern:
  type: semantic
  description: "Quality gate auto-detects only standard test frameworks, missing custom test suites"
fix: "Detect custom test runners by convention (executable run-all-tests.sh, test-*.sh glob)"
example:
  bad: |
    # Quality gate checks only standard frameworks
    if [[ -f pytest.ini ]]; then pytest; fi
    if [[ -f package.json ]]; then npm test; fi
    if [[ -f Makefile ]]; then make test; fi
    # Custom bash suite test-*.sh is never discovered
  good: |
    # Also check for executable test runners and test globs
    if [[ -x run-all-tests.sh ]]; then ./run-all-tests.sh; fi
    if ls test-*.sh &>/dev/null; then for t in test-*.sh; do ./"$t"; done; fi
    # Plus standard framework checks...
---

## Observation
Quality gates that auto-detect test frameworks (pytest, npm test, make test) fail to discover custom test suites written as bash scripts (`test-integration.sh`, `test-smoke.sh`) or other non-standard runners. The gate reports "no tests detected" and passes, while hundreds of assertions exist and are never executed.

## Insight
The root cause is convention-based detection that assumes all projects use a standard framework. Custom runners are often ignored because they're not a recognized pattern. The gate author knows pytest/npm/make but not the project's own conventions, leading to a blind spot.

## Lesson
Quality gates must detect tests by multiple conventions: (1) standard frameworks (pytest, npm test, make), (2) executable scripts matching `test-*.sh`, and (3) a convention file like `run-all-tests.sh` that the project defines. If a gate only knows standard frameworks, it will miss half the projects using custom runners.
