---
id: 69
title: "Plan quality dominates execution quality 3:1"
severity: should-fix
languages: [all]
scope: [universal]
category: specification-drift
pattern:
  type: semantic
  description: "Investing heavily in execution optimization (retries, sampling, model routing) while the plan itself has gaps, ambiguities, or wrong decomposition. A bad plan executed perfectly still produces wrong output."
fix: "Invest in plan quality first: scorecard the plan for completeness, correctness of decomposition, and dependency ordering before starting execution."
example:
  bad: |
    # Plan says "add authentication" with no detail
    # Execution uses MAB + competitive mode + 3 retries
    # Result: perfectly executed wrong authentication scheme
  good: |
    # Plan specifies: JWT with refresh tokens, 15min access TTL
    # Plan scorecard: all tasks have acceptance criteria
    # Simple headless execution gets it right first try
---

## Observation
Across multiple autonomous coding runs, the correlation between plan quality and final output quality was 3x stronger than the correlation between execution quality (retries, model choice, sampling) and output quality. The best execution infrastructure cannot compensate for a plan that decomposes the work incorrectly or omits critical requirements.

## Insight
Plan quality and execution quality are not interchangeable investments. A well-specified plan with simple execution beats a vague plan with sophisticated execution infrastructure. The plan is the specification — if it's wrong, every downstream batch inherits the error.

## Lesson
Score your plan before executing it. Check: Does every task have clear acceptance criteria? Are dependencies correctly ordered? Are there any ambiguous requirements? A 30-minute plan review saves hours of execution rework.
