---
id: 60
title: "set -e kills long-running bash scripts silently when inter-step commands fail"
severity: blocker
languages: [shell]
scope: [project:autonomous-coding-toolkit]
category: silent-failures
pattern:
  type: semantic
  description: "Bash script uses set -euo pipefail without EXIT trap or guards around non-critical inter-step operations (notifications, logging, context injection). Any unguarded command failure silently terminates the entire script."
fix: "Add trap '_log_exit $?' EXIT for diagnostics, trap '' HUP PIPE for background survival, and wrap non-critical commands in { ... } || warn blocks"
example:
  bad: |
    set -euo pipefail
    for batch in ...; do
        context=$(generate_context) # guarded
        sed '...' "$file" > "$tmp"  # NOT guarded — kills script on failure
        run_batch
        notify_success "$batch"     # NOT guarded — kills script on failure
    done
  good: |
    set -euo pipefail
    trap '_log_exit $?' EXIT
    trap '' HUP PIPE
    for batch in ...; do
        context=$(generate_context || true)
        { sed '...' "$file" > "$tmp"; } || echo "WARNING: context injection failed" >&2
        run_batch
        { notify_success "$batch"; } || echo "WARNING: notification failed" >&2
    done
---

## Observation

`run-plan.sh` repeatedly died silently between batches during headless execution. The process simply vanished — no error output, no log entry, no state update. The script completed one batch successfully, then disappeared before starting the next.

Log files showed the last batch succeeded (quality gate passed, state updated), but the process was gone. Restarting with `--start-batch N` always worked for the next batch, then died again.

## Insight

Three compounding factors:

1. **`set -euo pipefail` with no EXIT trap.** Any command returning non-zero anywhere in the inter-batch code (CLAUDE.md sed manipulation, notification calls, failure pattern recording) kills the script instantly. Since there's no EXIT trap, the death is completely silent — no stack trace, no error message, no breadcrumb.

2. **No signal handling — specifically SIGPIPE (confirmed).** The script pipes `claude -p` output through `tee` to write to both a log file and stdout. When stdout is a pipe to a task manager (Claude Code background task), the pipe can close between batches. `tee` then receives SIGPIPE (signal 13, exit code 141), which kills the process. Background processes need `trap '' HUP PIPE` to survive both terminal disconnects and broken pipes.

3. **Non-critical operations not guarded.** The loop contained ~15 unguarded commands between the critical path (run batch → quality gate). Notifications, context injection, sed transformations, git log summaries — all could fail for transient reasons, and each failure was fatal under `set -e`.

The pattern is: `set -e` is for correctness on the *critical path*. But when a long-running script has both critical operations (batch execution, quality gates) and non-critical operations (notifications, logging, context assembly), `set -e` can't distinguish between them. Non-critical failures become critical kills.

## Lesson

Long-running bash scripts with `set -e` must: (1) add `trap '_log_exit $?' EXIT` so unexpected terminations leave diagnostic breadcrumbs, (2) add `trap '' HUP` if they run in the background, and (3) wrap every non-critical operation in `{ commands; } || warn` blocks so transient failures don't kill the entire pipeline. The rule: if losing this operation wouldn't invalidate the batch, it must not be able to kill the script.
