---
id: 55
title: "LLM agents compensate for garbled batch prompts using cross-batch context"
severity: nice-to-have
languages: [all]
category: integration-boundaries
pattern:
  type: semantic
  description: "An agent receives a malformed or empty batch prompt but successfully infers the correct work from progress.txt, recent git commits, and the full plan file"
fix: "Design for resilience: include progress notes, recent commits, and the full plan in every batch prompt so agents can self-correct when the parsed batch content is wrong."
example:
  bad: |
    # Batch prompt: "Batch 9: (empty)" with no tasks
    # Agent has no context -> does nothing or hallucinates
  good: |
    # Batch prompt: "Batch 9: (empty)" BUT includes:
    # - progress.txt with completed tasks listed
    # - Recent git log showing what's been done
    # - Full plan file reference
    # -> Agent reads plan, deduces remaining work, implements correctly
---

## Observation
During Phase 4, batches 2 and 9 received garbled prompts — Batch 2 got fake content from a test fixture ("Task 2: Do more / Write more code"), and Batch 9 got an empty batch title. Despite this, both agents successfully implemented the correct plan tasks. Batch 2 implemented Tasks 7-9 (context assembler), and Batch 9 implemented Tasks 10, 11, 12, 15, and 17 (ast-grep + team mode).

## Insight
The cross-batch context system (progress.txt, recent commits in the prompt, and the plan file reference) provides enough information for agents to self-correct. The agent reads what's been done, compares it to the full plan, and picks up the next logical tasks. This resilience is an emergent property of including redundant context — no single source needs to be correct as long as the ensemble is informative.

## Lesson
Always include multiple context signals in batch prompts: (1) progress notes listing completed work, (2) recent git commits showing actual changes, (3) the full plan file path for reference. This creates graceful degradation — even when the parser sends wrong batch content, agents can figure out what work remains. The cost is slightly larger prompts; the benefit is resilience to parser bugs.
