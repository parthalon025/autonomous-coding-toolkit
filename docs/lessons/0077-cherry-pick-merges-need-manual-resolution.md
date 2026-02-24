---
id: 77
title: "Cherry-pick merges from parallel worktrees need manual conflict resolution"
severity: should-fix
languages: [all]
scope: [project:autonomous-coding-toolkit]
category: planning-control-flow
pattern:
  type: semantic
  description: "Multiple agents work in parallel worktrees on the same files. Cherry-picking the winner's commits into main creates merge conflicts that automated tools cannot resolve correctly because they lack the semantic context of why each change was made."
fix: "When cherry-picking from parallel worktrees, always use interactive conflict resolution. Never auto-resolve with --theirs or --ours. Review each conflict with the judge agent's scoring context."
example:
  bad: |
    git cherry-pick abc123 --strategy-option theirs  # blindly takes one side
    # Loses valuable changes from the other worktree
  good: |
    git cherry-pick abc123  # stops on conflict
    # Review each conflict with context from judge's scoring
    # Manually merge best-of-both changes
    git add resolved-file.py && git cherry-pick --continue
---

## Observation
In competitive mode, two agents implemented the same batch in separate worktrees. The judge picked a winner, but cherry-picking the winner's commits into the main worktree produced merge conflicts in 3 files. Using `--theirs` to auto-resolve discarded valuable fixes from the losing agent that the judge had flagged for best-of-both synthesis.

## Insight
Cherry-pick conflicts between parallel implementations are semantically rich — each side made deliberate, different choices. Automated resolution strategies (`--theirs`, `--ours`) discard information. Only a reviewer with the judge's scoring context can correctly merge the best of both.

## Lesson
Never auto-resolve cherry-pick conflicts from parallel worktrees. Use interactive resolution with the judge agent's scoring context. The mandatory best-of-both synthesis in competitive mode means both sides have value — the conflict resolution is where that value is captured.
