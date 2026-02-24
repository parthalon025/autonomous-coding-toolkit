---
id: 67
title: "Scripts hang when stdin is a socket or pipe in non-interactive shells"
severity: should-fix
languages: [shell]
scope: [project:autonomous-coding-toolkit]
category: silent-failures
pattern:
  type: semantic
  description: "Script reads from stdin without redirection — hangs in CI, Claude Code, cron, or any environment where stdin is not a terminal"
fix: "Add </dev/null to commands that may read stdin, or redirect stdin at the test harness level"
positive_alternative: "Run subprocesses with explicit stdin: bash script.sh </dev/null"
example:
  bad: |
    # Test harness — stdin inherited from parent (may be socket/pipe)
    for t in scripts/tests/test-*.sh; do
        bash "$t" >/dev/null 2>&1
    done
  good: |
    # Test harness — stdin explicitly from /dev/null
    for t in scripts/tests/test-*.sh; do
        bash "$t" </dev/null >/dev/null 2>&1
    done
---

## Observation

Running the test suite from Claude Code's shell caused `test-lesson-check.sh` to hang indefinitely. The process was blocked on `unix_stream_read_generic` — reading from a Unix socket that served as stdin in the Claude environment. Multiple stale processes accumulated across retries.

## Insight

Claude Code (and similar environments like CI runners, cron jobs, tmux send-keys) connects stdin to non-terminal file descriptors. Any script that reads stdin — even indirectly through a command like `read`, `cat` without args, or a tool that checks for piped input — will block forever waiting for data that never arrives. This is invisible in interactive testing because the terminal provides EOF on Ctrl+D.

## Lesson

Always redirect stdin from `/dev/null` when invoking scripts in non-interactive contexts. The safest place is the test harness loop itself (`bash "$t" </dev/null`), which protects all tests regardless of what they do internally. For individual scripts, audit for stdin-reading commands and add explicit `/dev/null` redirection.
