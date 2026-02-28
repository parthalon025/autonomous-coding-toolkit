---
id: 85
title: "Long context overload silences late-injected requirements"
severity: should-fix
languages: [all]
scope: [universal]
category: context-retrieval
pattern:
  type: semantic
  description: "The batch context is large (CLAUDE.md chain, lessons, prior batch summaries, referenced files). A critical requirement injected late in the context — near the token limit — is processed with degraded attention. The agent completes the batch without satisfying it."
fix: "Keep batch context under 6000 characters. Move critical requirements to the top of the context (before reference material). Use XML section tags to make structure explicit."
positive_alternative: "Place batch task description first, acceptance criteria last. Reference material goes in the middle. If context exceeds 6000 chars, trim reference files first, never requirements."
example:
  bad: |
    # Context: 8000 chars
    # Position 1: lessons (2000 chars)
    # Position 2: prior progress (2000 chars)
    # Position 3: referenced files (3000 chars)
    # Position 4: task description + requirements (1000 chars) ← lost in middle
  good: |
    # Context: 6000 chars
    # Position 1: task description (500 chars) ← top = strongest attention
    # Position 2: reference material (4500 chars)
    # Position 3: acceptance criteria (1000 chars) ← bottom = strong attention
---

## Observation

A batch context assembled CLAUDE.md, lesson summaries, three prior batch summaries, and two large referenced files before appending the task description and acceptance criteria. Total context was ~9,000 characters. The agent implemented most of the batch correctly but missed a non-functional requirement (request timeout ≤500ms) that appeared near the end of the context, past the 6,000 character mark.

## Insight

LLM attention follows a U-shape: strongest at the beginning, second-strongest at the end, weakest in the middle. A requirement placed after 7,000 characters of other content is in the weakest attention zone. The agent is not ignoring it — it is literally less likely to process it accurately due to the architecture of the attention mechanism. Context budget management is a correctness concern, not just a cost concern.

## Lesson

Set a strict context budget (6000 chars is a safe limit for most models). Apply the U-shape principle: task first, acceptance criteria last, reference material in the middle. When the budget is tight, trim reference files before trimming requirements. A trimmed reference file reduces quality; a trimmed requirement produces wrong code.
