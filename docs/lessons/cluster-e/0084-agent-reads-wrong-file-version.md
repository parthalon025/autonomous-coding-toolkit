---
id: 84
title: "Agent reads cached or pre-patch file version, implements against stale API"
severity: should-fix
languages: [all]
scope: [universal]
category: context-retrieval
pattern:
  type: semantic
  description: "An agent reads a file at the start of a batch. That file is modified by a previous task in the same batch or by a parallel agent. The agent's subsequent work is based on the version it read at the start, not the current state."
fix: "Re-read files immediately before using them, not at context-load time. For multi-task batches, each task should explicitly re-read files it depends on. Treat cached reads as potentially stale."
positive_alternative: "Before using any file's content to make a decision, state which version you are reading: 'Reading current state of src/api.py'. Re-read at the decision point, not at batch start."
example:
  bad: |
    # Batch start: reads src/api.py — has 3 endpoints
    # Task 1: adds endpoint 4 to src/api.py
    # Task 2: writes frontend using 3-endpoint API (stale read)
    # Frontend is missing endpoint 4 from day 1
  good: |
    # Task 1: adds endpoint 4 to src/api.py
    # Task 2: re-reads src/api.py — sees 4 endpoints
    # Frontend correctly uses all 4 endpoints
---

## Observation

A two-task batch read all relevant files at the start. Task 1 added a new API endpoint to `src/api.py`. Task 2 wrote a frontend component — but the agent used the file contents from the batch-start read, which showed only the original endpoints. Task 2's frontend was correct for the old API and wrong for the new API. The quality gate didn't catch it because tests mocked the API.

## Insight

LLM agents load context at the beginning of their turn. Within a multi-task batch, if Task 1 modifies a file, Task 2 typically cannot see that modification unless it explicitly re-reads the file. The agent is working from a snapshot taken before the batch started. This is especially dangerous in multi-task batches where early tasks set up structure that later tasks depend on.

## Lesson

Multi-task batches where Task N modifies a file that Task N+1 must read are a retrieval hazard. The batch prompt must instruct the agent to re-read modified files before consuming them: "Before implementing Task 2, re-read src/api.py to see the current state." Alternatively, break the dependency — put file-reading tasks and file-consuming tasks in separate batches.
