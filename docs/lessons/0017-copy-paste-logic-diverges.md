---
id: 17
title: "Copy-pasted logic between modules diverges silently"
severity: should-fix
languages: [all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Two modules independently implement the same logic and diverge when only one is updated"
fix: "Extract shared logic to a single module imported by both consumers"
example:
  bad: |
    # module_a.py
    def parse_date(s):
        return datetime.strptime(s, "%Y-%m-%d").date()

    # module_b.py (copy-paste)
    def parse_date(s):
        return datetime.strptime(s, "%Y-%m-%d").date()

    # Later, module_a is updated to handle ISO format
    # module_b is forgotten and still only handles %Y-%m-%d
  good: |
    # utils.py (shared)
    def parse_date(s):
        return datetime.strptime(s, "%Y-%m-%d").date()

    # module_a.py
    from utils import parse_date

    # module_b.py
    from utils import parse_date
---

## Observation
Two modules that compute the same thing independently will diverge silently over time. One module gets updated to handle a new case or bug fix, the other doesn't. Now they behave differently for the same input, and there's no error — both modules are "working" within their own scope.

## Insight
The root cause is code duplication at creation time. Copy-pasting logic is faster initially but creates a maintenance burden: every fix must be applied twice. If the person fixing module_a doesn't know module_b exists, the fix isn't applied there. The divergence is invisible until the different behaviors cause a bug.

## Lesson
Never copy-paste logic between modules. Extract it to a shared utility that both import. This ensures changes are made once and benefit both consumers. If you find the same logic in two places, refactor immediately — treat it as a red flag that future divergence is likely.
