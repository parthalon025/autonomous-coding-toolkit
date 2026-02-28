---
id: 83
title: "A single example in the spec is not a complete specification"
severity: should-fix
languages: [all]
scope: [universal]
category: specification-drift
pattern:
  type: semantic
  description: "The plan provides one concrete example of desired behavior and the agent generalizes from it. The example does not cover edge cases, error paths, or boundary conditions, so the agent's generalization is incomplete or wrong."
fix: "Include at least 3 examples per behavior: the happy path, an error case, and a boundary condition. State explicitly what is NOT supported."
positive_alternative: "For every behavior, specify: normal case, error case (what the output/exit code must be), and at least one boundary value. State what the function does NOT need to handle."
example:
  bad: |
    # Spec: "parse dates like '2024-01-15'"
    # Agent handles ISO format perfectly
    # No tests for: '01/15/2024', '', None, '2024-13-01'
    # Production input: mostly '01/15/2024' — all fails
  good: |
    # Spec: parse ISO dates (YYYY-MM-DD only)
    # '2024-01-15' → datetime(2024,1,15)
    # '' → raise ValueError("empty date string")
    # '01/15/2024' → raise ValueError("unsupported format")
    # NOT required: timezone handling, fuzzy parsing
---

## Observation

A plan specified date parsing with the example `"2024-01-15" → datetime(2024, 1, 15)`. The agent implemented ISO-8601 parsing correctly and wrote tests covering the example. Production data contained US-format dates (`01/15/2024`), empty strings, and null values — none of which the plan addressed. The agent had no basis to handle them because the spec contained only one example.

## Insight

A single example tells the agent the happy path. It does not tell the agent what to do when the input is wrong, empty, or formatted differently. Agents interpolate from examples — if one example shows `"2024-01-15"`, the agent implements a parser for that format and does not consider alternatives unless explicitly told. The burden is on the spec writer, not the agent, to enumerate the error space.

## Lesson

Every behavior in a spec needs at least three examples: the happy path, an explicit error case with the expected error output, and a boundary condition. Add a "NOT required" statement to prevent the agent from gold-plating. A spec with only one example is a spec with 90% of its requirements unwritten.
