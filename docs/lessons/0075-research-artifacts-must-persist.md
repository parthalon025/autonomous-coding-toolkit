---
id: 75
title: "Research artifacts must persist — ephemeral research is wasted research"
severity: should-fix
languages: [all]
scope: [universal]
category: context-retrieval
pattern:
  type: semantic
  description: "Research findings discussed in conversation but never written to a file. When context resets (new session, /clear, context compression), all research is lost and must be redone."
fix: "Every research activity must produce a durable file artifact. Write findings to tasks/research-<slug>.md immediately. Never rely on conversation context for research persistence."
example:
  bad: |
    # Agent researches 3 libraries, compares trade-offs
    # Findings exist only in conversation
    # User does /clear
    # Next session: "What libraries did we evaluate?" — gone
  good: |
    # Agent researches 3 libraries, writes tasks/research-auth-libs.md
    # File includes: comparison table, recommendation, blocking issues
    # User does /clear
    # Next session reads the file — full context preserved
---

## Observation
Research conducted during brainstorming or planning was discussed in conversation but never written to a file. When the session ended or context compressed, all research findings were lost. The next session had to redo the same research, often reaching different conclusions.

## Insight
Conversation context is ephemeral by design — context windows compress, sessions end, `/clear` resets everything. Research that exists only in conversation has the same durability as spoken words. File artifacts are the only mechanism that survives context boundaries.

## Lesson
Always make a file. Every research activity, design decision, and investigation produces a durable artifact at `tasks/research-<slug>.md`. No ephemeral research — files survive context resets, conversation context doesn't.
