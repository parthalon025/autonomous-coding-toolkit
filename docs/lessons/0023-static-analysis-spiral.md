---
id: 23
title: "Static analysis spiral -- chasing lint fixes creates more bugs"
severity: should-fix
languages: [all]
scope: [universal]
category: test-anti-patterns
pattern:
  type: semantic
  description: "Implementing lint fixes triggers new warnings in a cascading spiral"
fix: "Set a lint baseline, only fix violations in code you're actively changing"
example:
  bad: |
    # Run linter, find 150 issues
    pylint mymodule.py  # 150 violations
    # Start fixing: add type hints, remove unused imports, refactor
    # After 1 hour: 140 violations, but 3 bugs introduced in refactoring
    # Keep fixing: now 120 violations, but more subtle bugs
  good: |
    # Establish baseline
    pylint mymodule.py > baseline.txt  # 150 violations recorded
    # Only fix violations in code you touch during feature work
    # When implementing a function, clean that function's lints
    # New commits don't expand scope beyond the feature
---

## Observation

Linting systems are designed to improve code quality incrementally, but aggressive lint-chasing creates a secondary spiral: fixing style violations in unrelated code introduces logic bugs, which are harder to catch than style violations.

## Insight

Linting has two modes:

1. **Prophylactic** (new code): enforce rules as you write
2. **Curative** (old code): bulk-fix accumulated violations

Curative mode is expensive when applied to a large codebase. Each refactor is a chance to introduce bugs, and scope expands unbounded. The instinct is to "make the codebase better while I'm at it," but that trades quality for coverage and usually loses the trade.

## Lesson

Set a lint baseline and fix violations only in code you're actively changing:

1. Run the linter and record the baseline (e.g., `pylint mymodule.py > baseline.txt`)
2. During feature work, when you touch a function, also fix that function's lints
3. Never expand scope to fix unrelated violations
4. New commits should show code cleanup *in the changed regions only*

If you want to tackle accumulated tech debt, do it in a separate PR with a clear scope: "Refactor payment module for clarity — no logic changes." Run tests before and after to verify behavior is identical. Otherwise, lint fixes stay scoped to feature work.

Avoid automated "fix all lints" commits — they're high-risk, low-review, and merge conflicts nightmare. Humans fix code they understand; linters fix code they can parse.
