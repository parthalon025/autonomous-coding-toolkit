---
id: 7
title: "Runner state file rejected by own git-clean check"
severity: should-fix
languages: [shell, all]
category: integration-boundaries
pattern:
  type: semantic
  description: "Tool-generated state files rejected by the tool's own git-clean check"
fix: "Add tool-generated state files to .gitignore before the first run"
example:
  bad: |
    #!/bin/bash
    # Runner creates state file
    echo '{"batch":1}' > .run-plan-state.json
    # Later, quality gate rejects it
    git status --porcelain | grep -q . && echo "ERROR: untracked files"
  good: |
    # .gitignore includes state file
    echo ".run-plan-state.json" >> .gitignore
    # Runner creates state file (now ignored)
    echo '{"batch":1}' > .run-plan-state.json
    # Quality gate passes
    git status --porcelain | grep -q . || echo "OK: repo clean"
---

## Observation
A tool (e.g., plan runner) creates a state file (e.g., `.run-plan-state.json`) to persist execution progress. The tool's own quality gate includes a git-clean check that rejects untracked files. The tool creates the file, then its quality gate fails because the file is untracked.

## Insight
The root cause is a missing `.gitignore` entry. Tool-generated state files are not version-controlled artifacts — they're runtime metadata. If the tool creates them but the `.gitignore` doesn't exclude them, every tool run will create a file that the next quality gate rejects. This is a self-inflicted tooling loop.

## Lesson
Any tool that generates state files must add those files to `.gitignore` before the tool's first run. State files (`.state.json`, `.run-plan-state.json`, progress markers) are never version-controlled. The `.gitignore` is part of the tool's bootstrap, not the tool's runtime.
