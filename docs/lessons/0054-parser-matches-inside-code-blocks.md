---
id: 54
title: "Markdown parser matches headers inside code blocks and test fixtures"
severity: should-fix
languages: [shell]
scope: [project:autonomous-coding-toolkit]
category: silent-failures
pattern:
  type: semantic
  description: "A markdown parser using simple regex (grep/awk) matches ## headers that appear inside fenced code blocks, heredocs, or test fixture content — inflating batch/task counts"
fix: "Track fenced code block state (``` toggles) and skip matches inside code blocks. Or use a proper markdown AST parser."
example:
  bad: |
    # count_batches uses: grep -c '^## Batch'
    # Plan has a test fixture with '## Batch 2: Also Real' inside a heredoc
    # -> Parser counts 19 batches for a 5-batch plan
  good: |
    count_batches() {
        awk '/^```/{fence=!fence} !fence && /^## Batch/{n++} END{print n}' "$1"
    }
---

## Observation
The Phase 4 plan had 5 real batches, but `count_batches` found 19. The extra 14 came from `## Batch` and `### Task` headers inside test fixtures, code examples, and plan documentation sections. Each phantom batch spawned a `claude -p` process (~30-50s each), wasting ~7 minutes and API credits.

## Insight
Simple `grep '^## Batch'` treats all lines equally — it cannot distinguish a real plan header from one inside a fenced code block (` ``` `), a heredoc, or an inline example. This is a fundamental limitation of line-by-line regex parsing of markdown. The problem compounds: the plan's own test (Task 1) includes sample plan content with headers, creating a recursive parsing trap.

## Lesson
Any markdown parser that affects execution (batch counting, task extraction) must be code-block-aware. Minimum viable fix: track ` ``` ` fence state with a toggle variable and skip matches inside fences. Better: use a dedicated markdown heading extraction that respects the CommonMark spec. The empty-batch-skip mitigates the cost but doesn't prevent the API calls for the initial `claude -p` attempt on each phantom batch.
