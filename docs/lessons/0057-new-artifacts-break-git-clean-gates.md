---
id: 57
title: "New generated artifacts break git-clean quality gates"
severity: should-fix
languages: [all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Adding a new generated file to a pipeline without updating gitignore and E2E tests"
fix: "When adding generated artifacts, update .gitignore AND all E2E test gitignore fixtures"
example:
  bad: |
    # Added generate_agents_md() to startup
    # AGENTS.md created in worktree
    # E2E test fails: "uncommitted changes in worktree"
  good: |
    # Added generate_agents_md() to startup
    # Updated E2E test .gitignore to include AGENTS.md
    # E2E test passes: git-clean check ignores AGENTS.md
---

## Observation

Adding `generate_agents_md()` to the headless runner startup created
AGENTS.md in the worktree. The function's own unit test passed. But the
E2E test failed because its git worktree now had an untracked file,
and the quality gate's `check_git_clean` rejected it.

## Insight

This is Cluster B (Integration Boundaries). When a pipeline generates
new files, the git-clean check sees them as uncommitted work. Every
generated artifact needs a corresponding gitignore entry — both in the
real project AND in test fixtures that simulate the worktree.

## Lesson

Whenever you add a new generated file to a pipeline: (1) add it to the
project's `.gitignore`, (2) add it to every E2E test fixture's
`.gitignore`, (3) run the E2E test before committing. The unit test for
the generator won't catch this because it doesn't run the quality gate.
