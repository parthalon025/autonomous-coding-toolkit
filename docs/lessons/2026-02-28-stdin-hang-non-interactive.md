# Lesson: Bash Scripts Hang When Reading stdin in Non-Interactive Environments

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** stdin, hang, non-interactive, socket, CI, Claude Code, read, bash, blocking, /dev/null, redirect
**Files:** scripts/lesson-check.sh

---

## Observation (What Happened)

`lesson-check.sh` hung indefinitely when invoked from Claude Code's shell environment (where stdin is a Unix socket, not a terminal). The process blocked on `unix_stream_read_generic` — a command inside the script was reading from stdin without explicit redirection, waiting for input that would never arrive in a non-interactive context (#34).

This manifests in any environment where stdin is not a terminal: CI pipelines, background jobs, subshells spawned by agents, and any shell where stdin is connected to a socket or pipe.

## Analysis (Root Cause — 5 Whys)

**Why #1:** A command in the script reads from stdin implicitly (no explicit `< /dev/null` or `< "$file"` redirect).
**Why #2:** The script was tested interactively where stdin is a terminal — hitting EOF or Ctrl-D stops the read immediately.
**Why #3:** In non-interactive environments, stdin stays open indefinitely (Unix socket connection, open pipe), so `read` never returns.
**Why #4:** No timeout (`read -t`) was used, and no `< /dev/null` was added to commands that don't need stdin.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Audit any script invoked from non-interactive contexts (CI, agents, background jobs) for implicit stdin reads; redirect with `< /dev/null` for commands that don't need it | proposed | Justin | issue #34 |
| 2 | Use `read -t TIMEOUT` for any intentional stdin reads in scripts that might run non-interactively | proposed | Justin | — |
| 3 | Explicitly redirect stdin when spawning background scripts: `lesson-check.sh "$file" < /dev/null` | proposed | Justin | — |
| 4 | Test all scripts with `stdin < /dev/null` as a standard CI smoke test to catch blocking reads early | proposed | Justin | — |

## Key Takeaway

Any bash script with an implicit stdin read will hang forever when invoked non-interactively (CI, agents, sockets) — redirect stdin with `< /dev/null` on any invocation where stdin is not needed, and use `read -t` when timeout is required.
