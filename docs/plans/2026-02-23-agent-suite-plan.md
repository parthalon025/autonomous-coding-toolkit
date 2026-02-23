# Agent Suite + Tooling Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create 6 new agents, improve 8 existing agents, and integrate shellcheck/shfmt/shellharden/semgrep into the Makefile and CI pipeline.

**Architecture:** Agents are markdown files in `~/.claude/agents/` with YAML frontmatter. Tooling integrates via new `make lint` target wired into `make ci`. No code compilation — all files are markdown or config.

**Tech Stack:** Markdown (agents), Bash (Makefile), YAML (CI), shellcheck/shfmt/shellharden/semgrep (linting)

**Design doc:** `docs/plans/2026-02-23-agent-suite-design.md`
**Research:** 7 docs at `docs/plans/2026-02-23-research-*.md`

---

## Batch 1: Linting Tooling

Install tools, create configs, wire into Makefile and CI.

### Task 1: Install shfmt and shellharden

**Step 1: Install tools**

Run: `brew install shfmt shellharden`
Expected: Both install successfully

**Step 2: Install semgrep**

Run: `pip3 install semgrep`
Expected: semgrep installs successfully

**Step 3: Verify all 4 tools available**

Run: `which shellcheck shfmt shellharden semgrep`
Expected: All 4 paths printed

### Task 2: Create .shellcheckrc

**Files:**
- Create: `~/Documents/projects/autonomous-coding-toolkit/.shellcheckrc`

**Step 1: Write the config file**

```
# Enable all optional checks
enable=all
# Follow sourced files
external-sources=true
```

**Step 2: Verify shellcheck picks it up**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && shellcheck scripts/quality-gate.sh 2>&1 | head -5`
Expected: ShellCheck runs (may show warnings — that's fine, confirms the config is loaded)

### Task 3: Update Makefile with lint target

**Files:**
- Modify: `~/Documents/projects/autonomous-coding-toolkit/Makefile`

**Step 1: Replace Makefile contents**

```makefile
.PHONY: test validate lint ci

lint:
	@echo "=== ShellCheck ==="
	@shellcheck scripts/*.sh scripts/lib/*.sh 2>&1 || true
	@echo "=== shfmt ==="
	@shfmt -d -i 2 -ci scripts/*.sh scripts/lib/*.sh 2>&1 || true
	@echo "=== Shellharden ==="
	@shellharden --check scripts/*.sh scripts/lib/*.sh 2>&1 || true
	@echo "=== Semgrep ==="
	@semgrep --config "p/bash" --quiet scripts/ 2>&1 || true
	@echo "=== Lint Complete ==="

test:
	@bash scripts/tests/run-all-tests.sh

validate:
	@bash scripts/validate-all.sh

ci: lint validate test
	@echo "CI: ALL PASSED"
```

Note: `|| true` on each linter prevents one tool's warnings from blocking the rest. Individual tools exit non-zero on warnings, which would stop `make` otherwise. This is advisory-mode — future work can make specific tools blocking.

**Step 2: Verify lint target works**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && make lint 2>&1 | tail -10`
Expected: All 4 sections run, "Lint Complete" at end

**Step 3: Verify CI still passes**

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && make ci 2>&1 | tail -5`
Expected: "CI: ALL PASSED"

### Task 4: Update CI workflow

**Files:**
- Modify: `~/Documents/projects/autonomous-coding-toolkit/.github/workflows/ci.yml`

**Step 1: Update ci.yml**

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: |
          sudo apt-get install -y jq shellcheck
          sudo snap install shfmt
          pip install semgrep
      - name: Run CI
        run: make ci
```

Note: shellharden is not readily available on Ubuntu CI runners and is advisory-only. Skip it in CI — it runs locally via `make lint`.

**Step 2: Commit tooling changes**

Run:
```bash
cd ~/Documents/projects/autonomous-coding-toolkit
git add .shellcheckrc Makefile .github/workflows/ci.yml
git commit -m "feat: add lint target with shellcheck, shfmt, shellharden, semgrep"
```

---

## Batch 2: New Agents (bash-expert, shell-expert, python-expert)

### Task 5: Create bash-expert agent

**Files:**
- Create: `~/.claude/agents/bash-expert.md`

**Step 1: Write the agent file**

Use the recommended structure from `docs/plans/2026-02-23-research-bash-expert-agent.md` Section "Recommended Agent Structure". The agent must include:

- Frontmatter: `name: bash-expert`, `model: sonnet`, `tools: Read, Grep, Glob, Bash`, `maxTurns: 30`
- Description with explicit trigger contexts: `.sh` files, CI pipeline shell steps, hook scripts, systemd ExecStart, Makefile targets
- Role statement referencing Google Shell Style Guide, BashPitfalls, ShellCheck wiki
- Scan workflow (6 steps): read → grep P1 patterns → grep P2 patterns → check tooling config → run shellcheck → check scope
- Priority 1 blocking patterns (9 grep targets from research synthesis table): unquoted vars in command args, `eval` on variables, `|| true` masking errors, `cd` without error handling, missing `set -euo pipefail`, `for f in $(ls`, `local var=$(cmd)` masking exit code, `2>&1 >>` ordering, same-file pipeline
- Priority 2 quality patterns (10 targets): `#!/bin/bash` vs `#!/usr/bin/env bash`, `grep -P`, `ls` for file existence, backtick substitution, missing `--help`, no EXIT trap for temp files, `echo` where `printf` safer, `[ ]` instead of `[[ ]]`, hardcoded `/tmp/` instead of `mktemp`, `$*` instead of `$@`
- Output format: BLOCKING / QUALITY / STYLE / TOOLING table with file:line references
- Generation mode rules: `set -Eeuo pipefail`, `IFS=$'\n\t'`, `SCRIPT_DIR` detection, `err()`/`die()` functions, `trap EXIT` for cleanup, `main()` pattern, `--help` via `usage()`, `local` for function vars
- 100-line scope gate: flag scripts over 100 lines with complex control flow as Python rewrite candidates
- Hallucination guard: "Report only what Read/Grep/Bash output directly confirms"

**Step 2: Verify the file loads**

Run: `head -10 ~/.claude/agents/bash-expert.md`
Expected: YAML frontmatter with name, description, tools, model

### Task 6: Create shell-expert agent

**Files:**
- Create: `~/.claude/agents/shell-expert.md`

**Step 1: Write the agent file**

Use the recommended structure from `docs/plans/2026-02-23-research-shell-expert-agent.md` Section 9. The agent must include:

- Frontmatter: `name: shell-expert`, `model: sonnet`, `tools: Read, Grep, Glob, Bash`, `maxTurns: 30`
- Description: diagnosing systemd failures, PATH/env issues, package management, permissions, environment config. NOT script writing.
- Relationship to infra-auditor: monitoring vs investigation
- Five diagnostic domains with ordered checklists:
  1. Service Lifecycle: `systemctl --user show <svc> -p ActiveState,SubState,NRestarts,Result,ExecMainStartTimestamp --value`. Triage by Result code. Debug sequence: status → journalctl → manual repro → disable Restart= to expose errors. `systemd-analyze verify` for syntax lint.
  2. Environment & PATH: `which` → `type -a` → PATH listing → EnvironmentFile quoting check. Detect nvm/pyenv shims. Systemd EnvironmentFile does NOT strip shell quotes. Tilde/`$HOME` don't expand in ExecStart.
  3. Hardening Audit: `systemd-analyze security <svc>` → exposure score → top-5 directives. Categories: privilege escalation, filesystem, namespace, kernel, syscall, network.
  4. Package Management: `apt-get check` → `dpkg --configure -a` if broken → held packages → security updates → orphaned packages.
  5. Permissions: `~/.env` mode (600), SUID/SGID audit, world-writable scan, service user ownership.
- Key rule: "Use `systemctl show` properties, NEVER parse `systemctl status` text output"
- Output format: CRITICAL / WARNING / INFO sections with root cause + fix command + verification command per finding
- Hallucination guard: "Only recommend fixes you have confirmed through command output"

**Step 2: Verify the file loads**

Run: `head -10 ~/.claude/agents/shell-expert.md`
Expected: YAML frontmatter with name, description, tools, model

### Task 7: Create python-expert agent

**Files:**
- Create: `~/.claude/agents/python-expert.md`

**Step 1: Write the agent file**

Use the recommended structure from `docs/plans/2026-02-23-research-python-expert-agent.md` Section 8. The agent must include:

- Frontmatter: `name: python-expert`, `model: sonnet`, `tools: Read, Grep, Glob, Bash`, `maxTurns: 30`
- Description: reviewing/writing Python code with focus on async discipline, resource lifecycle, type safety. Specific to HA/Telegram/Notion/Ollama ecosystem.
- Scan groups (extending lesson-scanner numbering):
  - Scan 7: WebSocket send without `try/except ConnectionClosed` (Lesson #34). Pattern: `await.*\.(send|recv)\(` inside `async def` without surrounding try/except.
  - Scan 8: Blocking SQLite in async context (Lesson #33). Pattern: `sqlite3\.connect\(` inside `async def`. Also: `aiosqlite\.connect\(` outside `async with`.
  - Scan 9: Type boundary violations. Pattern: functions accepting MQTT/payload/state/update/event params without Pydantic BaseModel validation.
  - Scan 10: Dangling create_task (Lesson #43). Pattern: `create_task(` without storing ref AND without `add_done_callback`.
- Ruff config recommendation for Python projects (the exact toml from research doc)
- Key patterns: ASYNC210/230/251 rules, RUF006, `pickle.loads`/`eval`/`exec`/`subprocess(shell=True)` security flags
- HA subscriber pattern: `self._unsub = subscribe(...)`, call in `shutdown()`
- Mode B note: for full architectural review, use `model: opus` and add class structure analysis
- Hallucination guard: "Report only what Grep/Read confirms with file:line evidence"

**Step 2: Verify the file loads**

Run: `head -10 ~/.claude/agents/python-expert.md`
Expected: YAML frontmatter with name, description, tools, model

**Step 3: Commit batch 2**

Run:
```bash
git add ~/.claude/agents/bash-expert.md ~/.claude/agents/shell-expert.md ~/.claude/agents/python-expert.md
git commit -m "feat: add bash-expert, shell-expert, python-expert agents"
```

Note: `~/.claude/agents/` is outside the repo. These won't be committed to the toolkit repo. Instead, just verify the files exist. If you want them tracked, copy them to the toolkit's `agents/` directory too.

---

## Batch 3: New Agents (integration-tester, dependency-auditor, service-monitor)

### Task 8: Create integration-tester agent

**Files:**
- Create: `~/.claude/agents/integration-tester.md`

**Step 1: Write the agent file**

Use the recommended structure from `docs/plans/2026-02-23-research-integration-tester-agent.md` "Recommended Agent Structure". The agent must include:

- Frontmatter: `name: integration-tester`, `model: opus`, `tools: Read, Grep, Glob, Bash`, `maxTurns: 40`
- Description: verifying data flows across service seams, catching Cluster B bugs
- Five operating principles: black box only, evidence-based assertions, one probe per seam, fail fast with cause, no side effects
- Four probe strategies: `freshness_and_schema`, `sentinel_injection`, `db_row_trace`, `env_audit` — each with explicit numbered steps
- Seam registry (7 seams from design doc): HA logbook, Intelligence, Hub cache, Notion replica, Capture DB, Ollama queue, Shared env
- Output format: summary table (seam_id, status, latency) + per-seam evidence + action items
- Results written to `/tmp/integration-tester-results/`
- Key rule: "Never read service source code to infer behavior. Only check external observables."
- Hallucination guard: "Every PASS and FAIL must include quoted command output as evidence"

**Step 2: Verify**

Run: `head -10 ~/.claude/agents/integration-tester.md`
Expected: YAML frontmatter

### Task 9: Create dependency-auditor agent

**Files:**
- Create: `~/.claude/agents/dependency-auditor.md`

**Step 1: Write the agent file**

Use the recommended structure from `docs/plans/2026-02-23-research-dependency-auditor-agent.md` Section 8. The agent must include:

- Frontmatter: `name: dependency-auditor`, `model: haiku`, `tools: Read, Grep, Glob, Bash`, `maxTurns: 25`
- Description: scans 8 project repos for CVEs, outdated packages, license compliance. Read-only.
- Step 0: Tool availability check (`which pip-audit osv-scanner trivy npm npx`)
- Step 1: Repo detection (scan `~/Documents/projects/` for requirements.txt, pyproject.toml, package.json, Dockerfile)
- Step 2: CVE scanning per repo (`pip-audit -f json`, `npm audit --json`, `trivy fs --format json`)
- Step 3: Cross-language CVE aggregation (`osv-scanner scan --recursive`)
- Step 4: Outdated package detection (`pip list --outdated --format json`, `npx npm-check-updates --jsonUpgraded`)
- Step 5: License compliance (`pip-licenses --format json`, `npx license-checker --json`). Allowlist: MIT, Apache-2.0, BSD-2/3-Clause, ISC, PSF, CC0, Public Domain, Unlicense.
- Step 6: Report format (CRITICAL-HIGH / MEDIUM / Outdated / License tables)
- Key rule: "This agent is read-only. NEVER run pip install, npm audit fix, or modify any file."
- Hallucination guard: "Only report CVEs that appear in tool JSON output"

**Step 2: Verify**

Run: `head -10 ~/.claude/agents/dependency-auditor.md`
Expected: YAML frontmatter

### Task 10: Create service-monitor agent

**Files:**
- Create: `~/.claude/agents/service-monitor.md`

**Step 1: Write the agent file**

Use the recommended structure from `docs/plans/2026-02-23-research-service-monitor-agent.md` "Recommended Agent Structure". The agent must include:

- Frontmatter: `name: service-monitor`, `model: sonnet`, `tools: Read, Grep, Glob, Bash`, `maxTurns: 50`, `memory: user`
- Description: audits 12 user systemd services and 21 timers for failures, restart loops, silent errors, resource anomalies, known failure patterns
- Six inspection phases:
  1. Service state sweep: `systemctl --user show <svc> -p ActiveState,SubState,NRestarts,Result,ExecMainStartTimestamp --value` for all 12 services
  2. Timer health check: `LastTriggerUSec` via `systemctl --user show` compared against expected intervals
  3. Per-service log analysis: `journalctl --user -u <svc> --since "24 hours ago" -q` — error rates, zero-entry detection (Cluster A)
  4. Resource anomaly: memory usage vs MemoryMax, load average
  5. Known failure patterns: Telegram 409 (`grep "409"`), MQTT disconnect loop (`grep -i "disconnect\|reconnect"`), OOM kills (`Result == oom-kill`)
  6. Baseline comparison: read memory for previous NRestarts/error counts, flag >2x deviation
- State taxonomy: OK / RECOVERED / RESTARTING / FAILED / ANOMALY (Cluster A)
- Timer stale threshold: 2x expected interval
- Known limitations: NRestarts is cumulative (must combine with ActiveEnterTimestamp), LastTriggerUSec=0 means never fired, `--user` required for all user services
- Output format: CRITICAL / WARNING / ANOMALY / TIMER ISSUES / OK sections
- Memory update: persist new baselines after each run
- Hallucination guard: "Report only command output you have actually executed"

**Step 2: Verify**

Run: `head -10 ~/.claude/agents/service-monitor.md`
Expected: YAML frontmatter

**Step 3: Verify all 6 new agents exist**

Run: `ls ~/.claude/agents/*.md | wc -l`
Expected: 14 (8 existing + 6 new)

---

## Batch 4: Existing Agent Improvements (P0 — Correctness)

### Task 11: Fix security-reviewer

**Files:**
- Modify: `~/.claude/agents/security-reviewer.md`

**Step 1: Update frontmatter**

Change tools from `Read, Grep, Glob, Bash` to `Read, Grep, Glob` (remove Bash). Add `model: sonnet`, `maxTurns: 25`, `memory: project`.

Update description to: `"Reviews code for security vulnerabilities and sensitive data exposure. Use proactively after any code changes that touch authentication, data handling, file I/O, subprocess calls, or network requests."`

**Step 2: Add Python/bash attack categories**

After existing categories, add:

- **Python-specific:** `pickle.loads()`, `eval()`, `exec()`, `subprocess` with `shell=True`, `yaml.load()` without `Loader=SafeLoader`, `os.system()`, `input()` in Python 2 context
- **Cryptography:** `hashlib.md5`, `hashlib.sha1` for security purposes, `random.random()` in security-sensitive context, hardcoded salts/IVs
- **Shell-specific:** `eval` on variables, unquoted command substitution in arguments, `curl | bash` patterns

**Step 3: Add hallucination guard**

Add at end: "CRITICAL: Report ONLY findings grounded in specific file:line evidence from Read/Grep output. If a grep returns no matches for a category, record it as CLEAN — do not infer vulnerabilities. Zero grep results = zero findings for that category."

**Step 4: Add CLEAN section to output format**

```
CLEAN (no findings):
- [list of categories with zero grep matches]
```

### Task 12: Fix infra-auditor

**Files:**
- Modify: `~/.claude/agents/infra-auditor.md`

**Step 1: Update frontmatter**

Add `model: haiku`, `maxTurns: 15`.

**Step 2: Fix sync freshness math**

Replace the sync freshness section with:

```markdown
## Sync freshness

- Notion sync: compare `$(date +%s) - $(stat -c '%Y' ~/Documents/notion/.sync-metadata.json 2>/dev/null || echo 0)` — warn if delta > 43200 (12 hours)
- Telegram brief log: check `journalctl --user -u telegram-brief.timer --since "26 hours ago" -q | wc -l` — warn if 0 (missed daily run)
```

**Step 3: Add timer audit**

Add new section:

```markdown
## Timer freshness

Run: `systemctl --user list-timers --no-pager`
Check that all timers show a "NEXT" time in the future. Any timer with "n/a" for NEXT or LAST is stale.
```

**Step 4: Add hallucination guard**

Add at end: "Report only output from commands you actually executed. Do not infer service state."

### Task 13: Fix lesson-scanner description

**Files:**
- Modify: `~/.claude/agents/lesson-scanner.md`

**Step 1: Update frontmatter**

Change description count from "53 lessons" to "66 lessons". Add `model: sonnet`, `maxTurns: 25`.

**Step 2: Commit P0 fixes**

Run:
```bash
cd ~/Documents/projects/autonomous-coding-toolkit
# Note: agent files are in ~/.claude/agents/, not in repo
# If toolkit has a copy, update that too
```

---

## Batch 5: Existing Agent Improvements (P1 — Quality)

### Task 14: Add model and maxTurns to remaining agents

**Files:**
- Modify: `~/.claude/agents/doc-updater.md`
- Modify: `~/.claude/agents/counter.md`
- Modify: `~/.claude/agents/counter-daily.md`
- Modify: `~/.claude/agents/notion-researcher.md`
- Modify: `~/.claude/agents/notion-writer.md`

**Step 1: Update each agent's frontmatter**

| Agent | Add model | Add maxTurns |
|-------|-----------|-------------|
| doc-updater | `model: sonnet` | `maxTurns: 25` |
| counter | (already opus) | `maxTurns: 20` |
| counter-daily | (already sonnet) | `maxTurns: 5` |
| notion-researcher | `model: sonnet` | `maxTurns: 40` |
| notion-writer | `model: haiku` | `maxTurns: 20` |

### Task 15: Fix doc-updater git diff command

**Files:**
- Modify: `~/.claude/agents/doc-updater.md`

**Step 1: Update Process section**

Change line `1. Run \`git diff HEAD~1 --name-only\`` to:

```
1. Run `git status --short` to see uncommitted changes AND `git diff HEAD --name-only` to see committed changes
```

**Step 2: Add structured output format**

Add after Rules section:

```markdown
## Output Summary

After making changes, report:
- Files updated: [list of files touched]
- Changes made: [1-line summary per change]
- Files checked but unchanged: [count]
- Skipped (no updates needed): [if applicable]
```

### Task 16: Add follow-up rule to counter-daily

**Files:**
- Modify: `~/.claude/agents/counter-daily.md`

**Step 1: Add follow-up behavior rule**

Add to the agent body: "If Justin responds to your three questions, acknowledge his answers once with a brief reflection, then stop. Do not continue into a full counter session. The daily check is three questions, not a conversation."

---

## Batch 6: Existing Agent Improvements (P2 — Capability)

### Task 17: Add new scan groups to lesson-scanner

**Files:**
- Modify: `~/.claude/agents/lesson-scanner.md` (global copy)
- Modify: `~/Documents/projects/autonomous-coding-toolkit/agents/lesson-scanner.md` (toolkit copy)

**Step 1: Add Scan Group 7: Plan Quality (Lessons #60-66)**

After existing scan groups, add:

```markdown
## Step 3g: Plan Quality Checks (Lessons #60-66)

For each implementation plan in `docs/plans/`:
- Check batch count > 0 (plan has tasks)
- Check each batch has at least one task with a verification step
- Flag plans with > 10 batches as potentially over-scoped
- Flag tasks without explicit file paths

Report as: Nice-to-Have
```

**Step 2: Add Scan 3f: .venv/bin/pip (Lesson #51)**

```markdown
## Step 3f: Venv Pip Usage (Lesson #51)

Grep for: `\.venv/bin/pip ` (NOT `.venv/bin/python -m pip`)
Flag: "Use `.venv/bin/python -m pip` instead of `.venv/bin/pip` — Homebrew PATH corruption"
Severity: Should-Fix
```

### Task 18: Add vector search fallback to notion-researcher

**Files:**
- Modify: `~/.claude/agents/notion-researcher.md`

**Step 1: Add zero-result handling**

Add to the agent body: "If grep/glob searches return zero results for a query, try broadening the search: (1) use partial keywords, (2) search in `~/Documents/notion/` with wider patterns, (3) try the Notion MCP search tool as a fallback. Report clearly when a topic is not found in the local replica."

### Task 19: Add pre-flight check to notion-writer

**Files:**
- Modify: `~/.claude/agents/notion-writer.md`

**Step 1: Add pre-flight validation**

Add as first step in the agent body: "Before any API call, verify: (1) `NOTION_API_KEY` env var is set and non-empty, (2) target database/page ID is a valid UUID format (8-4-4-4-12 hex). If either fails, report the error immediately and stop — do not attempt the API call."

---

## Batch 7: Symlinks and Final Verification

### Task 20: Symlink research docs to ~/Documents/research/

**Step 1: Create symlinks**

Run:
```bash
cd ~/Documents/research
for f in ~/Documents/projects/autonomous-coding-toolkit/docs/plans/2026-02-23-research-*.md; do
  ln -sf "$f" "$(basename "$f")"
done
```

**Step 2: Verify**

Run: `ls -la ~/Documents/research/2026-02-23-research-*.md | wc -l`
Expected: 7

### Task 21: Verify all agents load correctly

**Step 1: Check all 14 agents have valid frontmatter**

Run:
```bash
for f in ~/.claude/agents/*.md; do
  name=$(head -10 "$f" | grep "^name:" | cut -d: -f2- | tr -d ' ')
  model=$(head -10 "$f" | grep "^model:" | cut -d: -f2- | tr -d ' ')
  tools=$(head -10 "$f" | grep "^tools:" | cut -d: -f2-)
  echo "$name | $model | $tools"
done
```

Expected: All 14 agents print name, model, and tools. No empty fields.

### Task 22: Run full CI

Run: `cd ~/Documents/projects/autonomous-coding-toolkit && make ci 2>&1 | tail -10`
Expected: "CI: ALL PASSED"

### Task 23: Commit all changes

Run:
```bash
cd ~/Documents/projects/autonomous-coding-toolkit
git add -A
git commit -m "feat: add 6 new agents, improve 8 existing agents, integrate linting tooling

- New agents: bash-expert, shell-expert, python-expert, integration-tester,
  dependency-auditor, service-monitor
- Existing improvements: P0 correctness fixes (security-reviewer, infra-auditor,
  lesson-scanner), P1 quality (model/maxTurns on all agents, doc-updater git diff),
  P2 capability (lesson-scanner scan groups, notion fallbacks)
- Tooling: shellcheck + shfmt + shellharden + semgrep via make lint, CI updated
- 7 research docs at docs/plans/2026-02-23-research-*.md"
```
