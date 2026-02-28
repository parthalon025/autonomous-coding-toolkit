---
id: 86
title: "Most-relevant lessons injected too early lose impact by task execution"
severity: nice-to-have
languages: [all]
scope: [universal]
category: context-retrieval
pattern:
  type: semantic
  description: "Lesson summaries injected at the start of a long batch context lose attention strength by the time the agent reaches the task they guard against. The agent has processed thousands of tokens since reading the lesson and the pattern is no longer in active attention."
fix: "Inject lessons close to the task they guard. If a lesson guards against a pattern in Task 3 of a batch, inject the lesson summary immediately before Task 3's description, not at batch start."
positive_alternative: "Co-locate lesson reminders with the task they apply to. Use the pattern: [task description] → [relevant lesson reminder] → [acceptance criteria] rather than [all lessons] → [all tasks]."
example:
  bad: |
    # Context start: 10 lesson summaries (2000 chars)
    # ... 4000 chars of other content ...
    # Task 3: implement database writes ← lesson 0001 (bare except) relevant here
    # Agent has 6000 chars between lesson reminder and the task
  good: |
    # Task 3: implement database writes
    # Reminder: lesson 0001 — every except block must log before returning
    # Acceptance: writes log to stderr on DB failure (test with DB offline)
---

## Observation

A batch injected all relevant lesson summaries at the start of context (standard ordering). The batch contained 5 tasks. By the time the agent reached Task 4 (which involved exception handling), it had processed 5,000+ characters since the bare-exception lesson was injected. The agent wrote a bare `except: pass` in Task 4 — the exact pattern the lesson guards against. The lesson was in the context; it just wasn't near the vulnerable code.

## Insight

Context injection order affects behavior, not just readability. The "Lost in the Middle" effect applies to lessons too: a lesson injected 5,000 characters before the code it guards is in the weak-attention zone when the agent writes that code. Co-location is the fix — inject the lesson at the point where it's relevant, not at the batch preamble.

## Lesson

For batches longer than 2 tasks, inject relevant lesson reminders immediately before the task they guard. A one-line reminder at the point of risk is more effective than a comprehensive summary 3,000 characters earlier. Structure batch prompts as: [task N description] → [lessons relevant to task N] → [task N acceptance criteria], for each task.
