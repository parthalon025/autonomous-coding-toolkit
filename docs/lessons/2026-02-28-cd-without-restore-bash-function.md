# Lesson: cd Without Restore in a Bash Function Leaks Working Directory to Subsequent Calls

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** cd, working directory, pushd, popd, subshell, function, cwd leak, bash, restore, directory
**Files:** scripts/batch-test.sh

---

## Observation (What Happened)

`batch-test.sh:39` called `cd "$project_dir"` inside `run_project_tests` without restoring the working directory afterward. Because this is a bash function (not a subshell), the directory change persists across the function's return. When the outer loop calls `run_project_tests` for the next project, the function starts in the previous project's directory instead of the intended one. If any `cd` fails (directory doesn't exist), subsequent iterations run in a completely wrong location (#11).

## Analysis (Root Cause — 5 Whys)

**Why #1:** `cd` in a bash function modifies the shell's global working directory, not a function-local copy.
**Why #2:** The developer assumed functions have isolated state — they do for local variables (when declared with `local`) but not for the working directory.
**Why #3:** No `pushd`/`popd` pair or subshell `(...)` was used to isolate the directory change.
**Why #4:** The error path when `cd` fails was not considered — if `cd "$project_dir"` fails and the script continues (with `|| true`), all subsequent commands run in the wrong directory.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Wrap the `cd` and everything that depends on it in a subshell: `( cd "$project_dir" && run_tests )` — the subshell's cwd change is never visible to the parent | proposed | Justin | issue #11 |
| 2 | Use `pushd "$project_dir" && ... && popd` if the subshell approach is inconvenient — but always ensure `popd` runs even on failure (pair with trap) | proposed | Justin | — |
| 3 | Use `git -C "$dir"` and equivalent `-C` / `--directory` flags for tools that support them, eliminating the need to cd at all | proposed | Justin | — |
| 4 | Rule: any `cd` inside a bash function that is NOT in a subshell must be immediately followed by a corresponding `popd` or the function must use a trap to restore | proposed | Justin | — |

## Key Takeaway

`cd` in a bash function leaks the working directory change to all subsequent calls — always isolate directory changes with a subshell `( cd "$dir" && ... )` or a `pushd`/`popd` pair; never rely on inline `cd` without restore in loop-called functions.
