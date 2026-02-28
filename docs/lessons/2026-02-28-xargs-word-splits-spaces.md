# Lesson: xargs Word-Splits on Filenames With Spaces

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** xargs, word split, filename, spaces, -d, newline, null delimiter, bash, glob, printf
**Files:** scripts/lib/run-plan-context.sh, scripts/quality-gate.sh

---

## Observation (What Happened)

Two scripts used patterns that break on filenames containing spaces:

1. `run-plan-context.sh:72` used `echo "$ref_file" | xargs` to trim whitespace from a filename. `xargs` performs word-splitting on its input, so a filename like `my plan.md` becomes two arguments `my` and `plan.md` (#60).

2. `quality-gate.sh:92` passed `$changed_files` unquoted to `lesson-check.sh`:
```bash
if ! "$SCRIPT_DIR/lesson-check.sh" $changed_files; then
```
Filenames with spaces split into multiple arguments; a filename `fix bug.sh` becomes two separate (non-existent) paths (#5).

## Analysis (Root Cause — 5 Whys)

**Why #1:** Both patterns use shell word-splitting or xargs's default whitespace delimiter, which treats spaces as argument separators.
**Why #2:** The developer used string variables to hold what should be arrays or null-delimited streams.
**Why #3:** Plan-defined filenames "rarely" have spaces — low-probability edge case accepted implicitly.
**Why #4:** The `shellcheck disable=SC2086` comment on the quality-gate call suppresses the shellcheck warning rather than fixing the underlying issue.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Replace `echo "$file" \| xargs` whitespace trim with bash parameter expansion: `file="${file#"${file%%[! ]*}"}"; file="${file%"${file##*[! ]}"}"` | proposed | Justin | issue #60 |
| 2 | Use arrays for file lists: `changed_files_arr=(); while IFS= read -r f; do changed_files_arr+=("$f"); done < <(get_changed_files)` then `"${changed_files_arr[@]}"` | proposed | Justin | issue #5 |
| 3 | When xargs is genuinely needed, use `xargs -d '\n'` (newline delimiter) or NUL-terminated input via `find ... -print0 \| xargs -0` | proposed | Justin | — |
| 4 | Remove shellcheck disables that suppress quoting warnings — fix the underlying array usage instead | proposed | Justin | issue #5 |

## Key Takeaway

Never pass a space-separated string of filenames where an array is required — use `"${arr[@]}"` for bash arrays or `xargs -d '\n'` / `xargs -0` for streams; `$var` word-splitting is a latent bug on any path with spaces.
