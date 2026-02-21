---
id: 0037
title: "Parallel agents sharing worktree corrupt staging area"
severity: blocker
languages: [all]
category: integration-boundaries
pattern:
  type: semantic
  description: "Multiple agents or CI jobs commit to the same git worktree, corrupting the staging area"
fix: "Each parallel agent gets its own git worktree; never share a worktree between concurrent processes"
example:
  bad: |
    # Both agents write to same repo
    Agent A: git add file1.py && git commit -m "feat: A"
    Agent B: git add file2.py && git commit -m "feat: B"  # corrupts A's staging
  good: |
    # Each agent has isolated worktree
    git worktree add agent-a-branch
    git worktree add agent-b-branch
    # Agents work in separate directories
---

## Observation
When multiple agents or CI processes write to the same git repository directory concurrently, they interfere with each other's staging area, index locks, and commit state. This results in "fatal: cannot lock ref" errors, lost commits, or commits with wrong file combinations.

## Insight
Git's index is a single file (`.git/index`) shared across all operations in a repository. The staging area is not thread-safe by design. Concurrent writes to this file corrupt it.

## Lesson
Never share a git worktree between concurrent processes. Use `git worktree add` to create isolated working directories for each parallel agent. Each worktree has its own index and staging area. Verify worktrees are cleaned up and removed after use.
