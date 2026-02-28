---
id: 91
title: "Plan tasks with no verification command cannot be quality-gated"
severity: should-fix
languages: [all]
scope: [universal]
category: planning-control-flow
pattern:
  type: semantic
  description: "A batch task describes work to be done but provides no verification command. The quality gate runs generic checks (lint, tests) but cannot verify this specific task was completed correctly. The task passes the gate by not failing it — a gate that does not check is not a gate."
fix: "Every task must include a verification command that exits 0 on success. If you cannot write a shell command that verifies completion, the task is not specific enough."
positive_alternative: "Write verification before implementation: 'This task is done when: [command] exits 0 with output [expected].' If you cannot write this before implementing, the requirement is unclear."
example:
  bad: |
    ### Task 2: Improve error messages
    Update error messages to be more descriptive.
    # No verification command — how is "more descriptive" measured?
    # Quality gate: generic tests pass, lint passes
    # Task marked complete — but error messages weren't changed
  good: |
    ### Task 2: Improve error messages
    Update error messages to include the failing field name.
    Verify: python -c "from src.validator import validate; validate({'age': 'abc'})"
    Expected output contains: "age: expected integer, got 'abc'"
---

## Observation

A plan included a task to "improve error messages." The batch executed, the quality gate passed (no new test failures, lint clean, git clean). But reviewing the output showed the error messages were unchanged — the agent made a different improvement it thought was more impactful. Without a concrete verification command, there was no way for the quality gate to catch the deviation. The task was marked complete because nothing explicitly failed.

## Insight

Quality gates are only as specific as the checks they run. Generic gates (lint, tests, git clean) verify the codebase is not broken — they do not verify that this specific task produced its intended output. A task that cannot be verified with a command has no machine-checkable acceptance criterion. The agent will complete it to its own satisfaction, which may not match the spec author's intent.

## Lesson

Every task in a plan must include an explicit verification command: a shell one-liner that exits 0 if and only if the task is complete. Write the verification command before writing the task description — if you cannot express completion as a command, the task is not specific enough. A plan task without a verification command is a wish, not a requirement.
