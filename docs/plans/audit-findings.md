# Shellcheck & Lesson Scanner Audit Findings

> Generated: 2026-02-21 | shellcheck 0.9.0 | Batch 1 of hardening pass

---

## Shellcheck Findings

### Notes (SC1091 — source not followed)

These are informational — shellcheck can't follow relative `source` paths without `-x` flag. Not actionable.

| File | Line | Code | Description | Disposition |
|------|------|------|-------------|-------------|
| `scripts/run-plan.sh` | 17 | SC1091 | Not following: `./lib/run-plan-parser.sh` | SUPPRESS — relative source, use `-x` flag |
| `scripts/run-plan.sh` | 18 | SC1091 | Not following: `./lib/run-plan-state.sh` | SUPPRESS — same |
| `scripts/run-plan.sh` | 19 | SC1091 | Not following: `./lib/run-plan-quality-gate.sh` | SUPPRESS — same |
| `scripts/run-plan.sh` | 20 | SC1091 | Not following: `./lib/run-plan-notify.sh` | SUPPRESS — same |
| `scripts/run-plan.sh` | 21 | SC1091 | Not following: `./lib/run-plan-prompt.sh` | SUPPRESS — same |

### Warnings

| File | Line | Code | Description | Disposition |
|------|------|------|-------------|-------------|
| `scripts/run-plan.sh` | 111 | SC2034 | `COMPETITIVE_BATCHES` appears unused | SUPPRESS — used by sourced lib modules |
| `scripts/run-plan.sh` | 123 | SC2034 | `MAX_BUDGET` appears unused | SUPPRESS — used by sourced lib modules |
| `scripts/run-plan.sh` | 305 | SC1007 | Remove space after `=` in `CLAUDECODE= claude` | SUPPRESS — intentional: unsetting env var for subcommand |
| `scripts/lesson-check.sh` | 20 | SC2034 | `lesson_severity` appears unused | FIX — either use it or remove from parse output |
| `scripts/entropy-audit.sh` | 28 | SC2034 | `FIX_MODE` appears unused | FIX — parsed but never checked; add `--fix` implementation or remove |
| `scripts/lib/run-plan-quality-gate.sh` | 65 | SC2034 | `passed` appears unused | FIX — declared but never read |

### Info/Style

| File | Line | Code | Description | Disposition |
|------|------|------|-------------|-------------|
| `scripts/setup-ralph-loop.sh` | 112 | SC2086 | Double quote to prevent globbing/word splitting: `$MAX_ITERATIONS` | FIX — quote variable |
| `scripts/auto-compound.sh` | 73 | SC2012 | Use `find` instead of `ls` for non-alphanumeric filenames | FIX — replace `ls -t` with `find`+`sort` |
| `scripts/entropy-audit.sh` | 73 | SC2016 | Expressions don't expand in single quotes | SUPPRESS — intentional: regex pattern uses literal `$` |
| `scripts/entropy-audit.sh` | 201 | SC2016 | Expressions don't expand in single quotes | SUPPRESS — same, grep pattern with literal backticks |
| `scripts/entropy-audit.sh` | 214 | SC2012 | Use `find` instead of `ls` | FIX — replace `ls` with `find` |
| `scripts/lib/run-plan-parser.sh` | 32 | SC2295 | Expansions inside `${..}` need separate quoting | FIX — quote inner expansion |
| `hooks/stop-hook.sh` | 78 | SC2181 | Check exit code directly instead of `$?` | FIX — restructure to `if ! cmd; then` |

---

## Summary

| Severity | Total | FIX | SUPPRESS |
|----------|-------|-----|----------|
| Note (SC1091 source) | 5 | 0 | 5 |
| Warning | 6 | 3 | 3 |
| Info/Style | 7 | 5 | 2 |
| **Total** | **18** | **8** | **10** |

---

## Lesson Scanner Results

*(Appended in Task 2)*
