---
id: 0044
title: "Relative `file:` deps break in git worktrees"
severity: should-fix
languages: [javascript, typescript]
category: integration-boundaries
pattern:
  type: semantic
  description: "package.json file: dependencies use relative paths that break in git worktrees at different depths"
fix: "Use workspace protocols, absolute paths resolved at install time, or npm/yarn workspaces"
example:
  bad: |
    // package.json in monorepo/services/api
    {
      "dependencies": {
        "shared": "file:../shared"  // Breaks in worktree
      }
    }
  good: |
    {
      "workspaces": [
        "packages/*",
        "services/*"
      ],
      "dependencies": {
        "shared": "workspace:*"
      }
    }
---

## Observation
npm/yarn `file:` dependencies use relative paths. When code is checked out into a git worktree at a different depth than the main repo, the relative path resolves to the wrong location (or doesn't exist). This breaks CI in specific git workflows.

## Insight
Git worktrees can be created at arbitrary depths relative to the main repo. Relative path dependencies were designed for a single repository layout and fail when the layout changes.

## Lesson
Use workspace protocols (`workspace:*`) in monorepos instead of `file:` dependencies. If `file:` is necessary, resolve relative paths to absolute paths at install time. For standalone packages, use npm/yarn workspaces or lerna to manage dependencies. Test with `git worktree add` at different depths to verify dependencies resolve correctly.
