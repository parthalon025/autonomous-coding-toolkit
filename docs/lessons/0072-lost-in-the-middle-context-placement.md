---
id: 72
title: "Lost in the Middle — context placement affects accuracy 20pp"
severity: should-fix
languages: [all]
scope: [universal]
category: context-retrieval
pattern:
  type: semantic
  description: "Critical instructions or requirements placed in the middle of a long context window, where LLM attention is weakest. Task description buried after long preambles or between large code blocks."
fix: "Place the task at the top of the context and requirements at the bottom. Keep the middle for reference material that's useful but not critical."
example:
  bad: |
    [500 lines of project context]
    [task description buried here]
    [300 lines of code examples]
  good: |
    [task description — FIRST]
    [reference material in middle]
    [requirements and constraints — LAST]
---

## Observation
Research on LLM context windows shows a U-shaped attention curve: models attend most strongly to the beginning and end of context, with accuracy dropping up to 20 percentage points for information placed in the middle. When critical instructions were placed mid-context, agents missed them reliably.

## Insight
The "Lost in the Middle" effect means context order matters as much as context content. A perfectly written requirement placed in the wrong position has the same effect as a missing requirement. This is especially relevant for context injection in autonomous pipelines.

## Lesson
Structure all context injection with task at the top and requirements at the bottom. Use the middle for supplementary reference material. For `run-plan-context.sh`, this means: batch description first, prior art and warnings in the middle, acceptance criteria last.
