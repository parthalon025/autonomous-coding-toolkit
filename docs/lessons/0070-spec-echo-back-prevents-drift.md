---
id: 70
title: "Spec echo-back prevents 60% of agent failures"
severity: should-fix
languages: [all]
scope: [universal]
category: specification-drift
pattern:
  type: semantic
  description: "Agent proceeds directly from requirements to implementation without restating the requirements in its own words and confirming understanding with the user."
fix: "Add an echo-back gate: agent restates requirements, user confirms or corrects, only then proceed to implementation."
example:
  bad: |
    User: "Add rate limiting to the API"
    Agent: *immediately starts coding*
  good: |
    User: "Add rate limiting to the API"
    Agent: "I'll add token bucket rate limiting at 100 req/min per IP,
            with 429 responses and Retry-After header. Correct?"
    User: "Yes, but 60 req/min"
    Agent: *now implements with correct limit*
---

## Observation
Analysis of autonomous coding failures showed that 60%+ of failures stemmed from spec misunderstanding, not from coding errors. The agent understood the words but not the intent — implementing a technically correct solution to the wrong problem.

## Insight
Spec misunderstanding is invisible until late in the process because the agent's implementation is internally consistent. Tests pass because they test the agent's interpretation. The echo-back step forces the misunderstanding to surface before any code is written.

## Lesson
Before implementing any feature, restate the requirements in your own words and confirm with the user. This single step prevents more failures than any amount of testing or code review.
