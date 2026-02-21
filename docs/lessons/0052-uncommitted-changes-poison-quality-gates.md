---
id: 52
title: "Uncommitted changes from parallel work fail the quality gate git-clean check"
severity: blocker
languages: [shell]
category: integration-boundaries
pattern:
  type: semantic
  description: "Manual edits to files in a worktree where run-plan.sh is executing — the git-clean check in quality-gate.sh detects uncommitted changes and fails the batch"
fix: "Never make uncommitted changes in a worktree with an active run-plan. Use a separate worktree or commit before the next quality gate runs."
example:
  bad: |
    # run-plan.sh is executing batches in ~/project/
    # Meanwhile, manually edit scripts/lib/run-plan-notify.sh
    # -> Quality gate runs check_git_clean() -> finds dirty working tree -> FAIL
  good: |
    # Option A: Edit in a separate worktree
    git worktree add ../project-notify-fix -b fix/notifications
    # Option B: Commit immediately before next quality gate
    git add scripts/lib/run-plan-notify.sh && git commit -m "fix: ..."
---

## Observation
During Phase 4 execution, Telegram notification format was improved by editing `run-plan-notify.sh` and its test file directly in the worktree where `run-plan.sh` was running. When Batch 9 completed and the quality gate ran `check_git_clean()`, it found 3 uncommitted files and failed the batch. The batch agent then spent a full retry attempt (5+ minutes) trying to fix a problem that wasn't caused by its own work.

## Insight
The quality gate's git-clean check exists to ensure every batch's work is committed before the next batch starts. It can't distinguish between "the batch agent forgot to commit" and "a human made parallel edits." Both look the same: dirty working tree. The retry agent wastes time investigating a failure it can't fix, since the dirty files aren't part of its batch.

## Lesson
A worktree with an active run-plan is a no-edit zone. All parallel work must happen in a separate worktree or be committed immediately. If you must edit files in the active worktree, commit them before the next quality gate runs. The cost of a wasted retry (5+ minutes, API calls) far exceeds the cost of a quick commit.
