# Lesson: eval on User-Controlled Command Strings Enables Shell Injection

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** security
**Keywords:** eval, command injection, shell injection, user input, quality gate, bash -c, security, exec
**Files:** scripts/lib/run-plan-quality-gate.sh

---

## Observation (What Happened)

`run-plan-quality-gate.sh` used `eval` to execute a user-supplied quality gate command string:

```bash
gate_output=$(cd "$worktree" && eval "$quality_gate_cmd" 2>&1)
```

`$quality_gate_cmd` is passed in via the `--quality-gate` CLI argument. Any shell metacharacters in the argument (semicolons, backticks, `$()`, `&&`, redirects) execute as shell code with the script's permissions. A value like `make test; rm -rf /` would execute the deletion (#3).

## Analysis (Root Cause — 5 Whys)

**Why #1:** `eval` treats its argument as a shell program, not as a command name with arguments — every metacharacter is active.
**Why #2:** The developer needed to support parameterized commands like `pytest --timeout=30`, and `eval` seemed like the simplest way to split the string into command + args.
**Why #3:** The correct tool for running a user-supplied command string is `bash -c "$cmd"` with proper quoting OR an array built from the user input — but both require understanding the security boundary.
**Why #4:** The `--quality-gate` argument comes from a config file or CLI flag, which a developer might control — but the same interface can be set by a compromised plan file.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Replace `eval "$quality_gate_cmd"` with `bash -c "$quality_gate_cmd"` — same behavior, explicit subprocess boundary, and easier to audit | proposed | Justin | issue #3 |
| 2 | For higher security: parse the command into an array and use direct invocation: `read -ra cmd_arr <<< "$quality_gate_cmd"; "${cmd_arr[@]}"` | proposed | Justin | — |
| 3 | Validate `quality_gate_cmd` against an allowlist of known-safe commands before execution | proposed | Justin | — |
| 4 | Treat `eval` as a code smell in bash scripts — it should almost never appear; replace with `bash -c`, function dispatch tables, or array-based invocation | proposed | Justin | — |

## Key Takeaway

`eval` on any string containing user input (CLI args, config files, plan files) is a shell injection vulnerability — replace with `bash -c` for subprocess isolation or array-based direct invocation; treat `eval` as a red flag in any bash script review.
