---
id: 61
title: "Context injection into tracked files creates dirty git state when subprocess commits"
severity: should-fix
languages: [shell]
scope: [project:autonomous-coding-toolkit]
category: integration-boundaries
pattern:
  type: semantic
  description: "Script injects temporary content into a tracked file (e.g., CLAUDE.md), runs a subprocess that may commit that file, then tries to restore from backup — creating a diff against the committed version."
fix: "Use git checkout -- <file> to restore to HEAD state instead of backup-based restoration. Fall back to backup only if file was never tracked."
example:
  bad: |
    backup=$(cat "$file")
    echo "$context" >> "$file"
    run_subprocess  # subprocess commits $file with injected content
    echo "$backup" > "$file"  # now differs from HEAD — dirty state
  good: |
    echo "$context" >> "$file"
    run_subprocess
    git checkout -- "$file" 2>/dev/null || {
        # fallback: file was never tracked
        if [[ "$existed_before" == false ]]; then
            rm -f "$file"
        fi
    }
---

## Observation

`run-plan.sh` injects per-batch context into `CLAUDE.md` before each batch (a `## Run-Plan: Batch N` section with failure patterns, prior batch summaries, and referenced files). After the batch completes, it restores CLAUDE.md from a backup taken before injection.

Batch 5 failed the quality gate with "uncommitted changes to CLAUDE.md" even though the batch itself passed all tests. The issue: the Claude subprocess committed CLAUDE.md with the injected context as part of its work. The restoration code then wrote the pre-injection backup, creating a diff against the now-committed HEAD that included the injected content.

## Insight

This is an integration boundary bug between two phases that both touch the same file:

1. **Orchestrator phase** — injects context into CLAUDE.md, expects to restore it after
2. **Subprocess phase** — sees CLAUDE.md as a project file, may commit it with its changes

The backup-based restoration assumes CLAUDE.md's HEAD hasn't changed during the subprocess run. But if the subprocess commits the file (which is correct behavior — it should commit its changes), the backup is now out of date. Writing the backup creates a diff between HEAD (with injected content) and the working tree (without it).

The fix is to use `git checkout -- CLAUDE.md` which always restores to whatever HEAD currently is — regardless of whether the subprocess committed the injected version.

Edge case: if CLAUDE.md was never tracked (created fresh by injection), `git checkout` fails. Fall back to `rm -f` in that case.

## Lesson

When injecting temporary content into tracked files before running a subprocess that may commit, never restore from an in-memory backup. The subprocess may commit the modified version, making the backup stale. Use `git checkout -- <file>` to restore to HEAD state, which is always correct regardless of whether the subprocess committed. Guard the edge case where the file wasn't previously tracked.
