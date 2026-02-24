---
id: 78
title: "Static review without live test optimizes for the wrong risk class"
severity: should-fix
languages: [all]
scope: [universal]
category: planning-control-flow
pattern:
  type: semantic
  description: "Relying solely on static code review (reading code, checking patterns) without running the code in a live environment. Static review catches structural issues but misses behavioral bugs that only manifest at runtime."
fix: "Always combine static review with at least one live integration test. One live test catches more real bugs than six static reviewers."
example:
  bad: |
    # 6 review agents read the code
    # All report "looks good"
    # Deploy → runtime error on first request
  good: |
    # 2 review agents read the code
    # 1 integration test runs the actual pipeline
    # Runtime error caught before deploy
---

## Observation
A code change was reviewed by six static analysis agents. All reported the code was correct. On deployment, the first real request triggered a runtime error that none of the static reviewers could have caught — the bug was in the interaction between two components at runtime, not in either component's code.

## Insight
Static review and live testing catch non-overlapping bug classes. Static review finds structural issues (wrong patterns, missing imports, type errors). Live testing finds behavioral issues (wrong data flow, timing bugs, environment-dependent failures). Investing only in static review creates a false sense of confidence.

## Lesson
Always combine static review (at most 2 agents — diminishing returns after that) with at least one live integration test. The audit method should always be: static review for structural correctness + live test for behavioral correctness. One live test is worth six static reviewers.
