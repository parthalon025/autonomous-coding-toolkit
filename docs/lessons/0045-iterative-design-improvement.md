---
id: 0045
title: "Iterative 'how would you improve' catches 35% more design gaps"
severity: should-fix
languages: [all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Single-pass design review misses gaps that iterative improvement rounds would catch"
fix: "Ask 'how would you improve this section?' after each design section; 5 rounds is the sweet spot"
example:
  bad: |
    # Single design pass
    Review once. Approve. Start building.
    # Later: discover missing error handling, untested edge case
  good: |
    # Iterative design
    Round 1: "What could break here?" -> Add timeout handling
    Round 2: "How scale this to 10K items?" -> Add pagination
    Round 3: "What if database is down?" -> Add circuit breaker
    Round 4: "How to monitor this?" -> Add metrics
    Round 5: "Any security risks?" -> Add auth validation
---

## Observation
Design review done in a single pass typically covers the happy path. Iterative rounds of "how would you improve this section?" reveal gaps: edge cases, scale limits, failure modes, monitoring, and security issues that a single review missed.

## Insight
Single-pass review relies on reviewers catching everything. Iterative rounds make gaps explicit by forcing the designer to consider improvements from different angles. Each round builds on the previous one and surfaces new concerns.

## Lesson
After each major design section, ask "How would you improve this section?" Require at least 3 rounds; 5 is optimal. Each round should surface a new category: performance, fault tolerance, monitoring, security, or operational concerns. Document improvements and rationale. This catches design gaps before implementation and reduces rework later.
