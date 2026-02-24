---
id: 26
title: "Linter with no rules enabled = false enforcement"
severity: should-fix
languages: [all]
scope: [universal]
category: silent-failures
pattern:
  type: semantic
  description: "Linter installed with zero rules configured reports 0 issues regardless of code quality"
fix: "Always configure rules explicitly; test that the linter catches a known-bad sample"
example:
  bad: |
    # pylint installed, no .pylintrc
    $ pylint mymodule.py
    Your code has been rated at 10.00/10 (previous run: 10.00/10)
    # No issues reported, but code is full of undefined variables and bad practices

    # .pylintrc exists but all rules disabled
    [MESSAGES CONTROL]
    disable=all
  good: |
    # .pylintrc with explicit rules
    [MESSAGES CONTROL]
    disable=fixme,too-many-arguments,line-too-long

    # Test the linter catches known issues
    $ cat > test_bad.py << 'EOF'
    x = undefined_variable
    EOF
    $ pylint test_bad.py
    E0602: Undefined variable 'undefined_variable'
---

## Observation

Linters installed but misconfigured (no config file, or config with all rules disabled) report perfect scores on any code. Teams believe they have linting enforcement when they have none.

## Insight

Linting is a visibility layer — it surfaces code quality issues. An unconfigured or disabled linter creates false visibility: problems exist but the linter doesn't report them. This is worse than no linting, because teams act on the false signal.

## Lesson

When setting up a linter:

1. **Explicit configuration**: Create a config file (`.pylintrc`, `.eslintrc.json`, etc.) with at least one rule enabled.
2. **Baseline test**: Create a file with a known-bad pattern (undefined variable, unused import, etc.), run the linter, verify it catches it.
3. **Disable intentionally**: Start with defaults, then disable rules that conflict with your style (not all rules).
4. **CI integration**: Run the linter in CI/pre-commit hooks; fail builds on lint errors.

Don't disable large categories of rules unless you have a specific reason. "We don't care about line length" is a reason; "linting is too strict" is not. If the default rules feel too strict, discuss as a team and pick the ones that matter.

Verify linting is working by occasionally committing code that violates an enabled rule and confirming CI catches it.
