---
id: 71
title: "Positive instructions outperform negative ones for LLMs"
severity: should-fix
languages: [all]
scope: [universal]
category: specification-drift
pattern:
  type: semantic
  description: "Instructions phrased as 'don't do X' instead of 'do Y'. Negative instructions trigger the Pink Elephant Problem — the model encodes the forbidden pattern and may reproduce it."
fix: "Rephrase negative instructions as positive alternatives: instead of 'don't use var', write 'use const or let'."
example:
  bad: |
    # Don't use bare except clauses
    # Don't hardcode test counts
    # Don't use .venv/bin/pip
  good: |
    # Always catch specific exception classes and log
    # Use threshold assertions (>=) for extensible collections
    # Use .venv/bin/python -m pip for correct site-packages
---

## Observation
When lesson files and instructions used negative phrasing ("don't do X"), agents occasionally reproduced the exact anti-pattern described — the Pink Elephant Problem. Positive phrasing ("do Y instead") consistently produced better compliance.

## Insight
LLMs process instructions by encoding all tokens, including the forbidden pattern. "Don't use bare except" encodes "bare except" as a salient concept. "Always catch specific exception classes" encodes the correct pattern directly. The model follows what it encodes most strongly.

## Lesson
Write instructions as positive alternatives: "do Y" outperforms "don't do X" for LLM compliance. When writing lessons, always include a `positive_alternative` that the agent can follow directly.
