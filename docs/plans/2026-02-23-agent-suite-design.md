# Agent Suite + Tooling Integration Design

**Date:** 2026-02-23
**Status:** Draft — awaiting user approval
**Scope:** 6 new agents, improvements to 8 existing agents, linting tooling in Makefile + CI
**Research:** 7 documents at `docs/plans/2026-02-23-research-*.md` (3,451 lines total)

---

## Part 1: New Agents (6)

All placed in `~/.claude/agents/` (global — cross-project).

### 1.1 bash-expert.md

**Purpose:** Review, write, and debug bash scripts. Dual-mode: audit existing scripts for bugs + write new scripts following best practices.

**Model:** sonnet | **Tools:** Read, Grep, Glob, Bash

**Knowledge base:**
- Google Shell Style Guide (naming, structure, functions)
- ShellCheck rules (quoting SC2086, eval SC2091, glob SC2035, subshell SC2012)
- BashPitfalls wiki (61+ common mistakes)
- Shellharden quoting rules
- Toolkit lessons (bare-except #7, async-no-await #25, hardcoded-localhost)

**Scan workflow (audit mode):**
1. Read target file(s)
2. Run `shellcheck --enable=all --external-sources <file>` if available
3. Grep for Priority 1 patterns: unquoted variables in command args, `eval` on variables, `|| true` masking errors, `cd` without error handling, missing `set -euo pipefail`
4. Grep for Priority 2 patterns: `#!/bin/bash` instead of `#!/usr/bin/env bash`, `grep -P` (non-portable), `ls` for file existence, `cat` in pipelines (UUOC)
5. Check script size (>300 lines = recommend splitting)

**Writing mode rules:**
- Always start with `set -euo pipefail`
- Quote all variable expansions
- Use arrays for file lists, never word-split strings
- `mktemp` + trap for temp files
- `printf` over `echo`
- `[[ ]]` for conditionals
- Functions for anything called twice
- `local` for function variables

**Output format:** BLOCKING / SHOULD-FIX / CLEAN table with file:line references.

### 1.2 shell-expert.md

**Purpose:** Diagnose systemd service failures, PATH/environment issues, package management, permissions, and environment configuration. Investigation and remediation, NOT script writing.

**Model:** sonnet | **Tools:** Read, Grep, Glob, Bash

**Relationship to infra-auditor:**
- `infra-auditor` = monitoring (is everything up?)
- `shell-expert` = investigation (why did it fail, how to fix?)

**Five diagnostic domains:**

1. **Service Lifecycle** — `systemctl --user show <svc> -p ActiveState,SubState,NRestarts,Result,ExecMainStartTimestamp --value` (never parse `status` text). Triage by Result: `exit-code` → check logs, `oom-kill` → check MemoryMax, `start-limit-hit` → needs `systemctl --user reset-failed`.
2. **Environment & PATH** — Four-step: `which <cmd>`, `type -a <cmd>`, `echo $PATH | tr : '\n'`, check EnvironmentFile quoting. Detect version manager shims (nvm, pyenv).
3. **Hardening Audit** — `systemd-analyze security <svc>` → exposure score → top-5 directives to add.
4. **Package Management** — `apt-get check`, held packages, security updates (`apt list --upgradable`), orphaned packages.
5. **Permissions** — `~/.env` mode check (should be 600), SUID/SGID audit, world-writable scan, service user ownership.

**Key rule:** Use `systemctl show` properties, NEVER parse `systemctl status` text output.

### 1.3 python-expert.md

**Purpose:** Review and write Python code with focus on async discipline, resource lifecycle, type safety, and production patterns specific to the project ecosystem (HA, Telegram, Notion, Ollama).

**Model:** sonnet | **Tools:** Read, Grep, Glob, Bash

**Two modes:**

**Mode A: Extend lesson-scanner (default).** Add scan groups:
- Scan 7: WebSocket send without `try/except ConnectionClosed` (Lesson #34)
- Scan 8: `sqlite3.connect()` inside `async def` — blocking I/O (Lesson #33)
- Scan 9: External data (MQTT, HA state, Telegram updates) entering business logic without Pydantic validation
- Scan 10: `create_task()` without `add_done_callback` (Lesson #43) — RUF006 catches missing ref, not missing callback

**Mode B: Full architectural review** (when asked). Class structure analysis, cross-file subscriber lifecycle, type coverage, async flow tracing. Uses opus model.

**Ruff config to push to all Python projects:**
```toml
[tool.ruff.lint]
select = ["E", "W", "F", "B", "ASYNC", "RUF006", "UP", "SIM"]
```

**Key patterns from research:**
- `async def` without I/O → RUF029 (preview, enable when stable)
- ASYNC210/230/251 → blocking HTTP/file/sleep in async context
- `pickle.loads()`, `eval()`, `exec()`, `subprocess(shell=True)` → security flags
- HA subscriber pattern: `self._unsub = subscribe(...)`, call in `shutdown()`

### 1.4 integration-tester.md

**Purpose:** Verify data flows correctly across service seams. Catches Cluster B bugs where each service passes its own tests but handoffs fail.

**Model:** opus | **Tools:** Read, Grep, Glob, Bash

**Operating principles:**
1. Black box only — never read source to infer behavior; only check external observables
2. Evidence-based assertions — every PASS/FAIL includes quoted evidence
3. One probe per seam — failures must be unambiguously attributable
4. Fail fast with cause — if health check fails, SKIP with reason
5. No side effects — test artifacts go to `/tmp/integration-tester-results/`

**Seam registry (from projects/CLAUDE.md cross-project dependency table):**

| Seam | Producer | Consumer | Probe |
|------|----------|----------|-------|
| HA logbook | ha-log-sync | aria engine | File freshness < 15min, valid JSON lines |
| Intelligence | aria engine | aria hub | File exists, schema matches hub's expected fields |
| Hub cache | aria hub | — | SQLite opens, table schema matches |
| Notion replica | notion-tools | telegram-brief | File count > 0, last-modified < 6h |
| Capture DB | telegram-capture | capture-sync | Row count increasing, last insert < 1h |
| Ollama queue | queue daemon | 10 timers | Queue endpoint responds, job format valid |
| Shared env | ~/.env | all consumers | Each consumer's required vars are set and non-empty |

**Output:** Per-seam PASS/FAIL/SKIP table with evidence timestamps.

### 1.5 dependency-auditor.md

**Purpose:** Scan all 8 repos for outdated packages, known CVEs, and license issues. Read-only — never runs install/fix commands.

**Model:** haiku | **Tools:** Read, Grep, Glob, Bash

**Three-layer tool stack:**
1. **Per-ecosystem:** `pip-audit --format json` (Python), `npm audit --json` (Node)
2. **Cross-language:** `osv-scanner` over all repos (unified severity)
3. **Docker-specific:** `trivy image` for gpt-researcher container

**License compliance:** `pip-licenses --format json` per Python repo, `npx license-checker --json` for Node.

**Design rule from research:** Separate `/dep-audit` (read-only detection) from `/dep-upgrade` (state-changing fixes). This agent is audit only.

**Output:** BLOCKER (CRITICAL/HIGH CVE) / SHOULD-FIX (MEDIUM, outdated >6mo) / NICE-TO-HAVE (LOW, minor version behind) table per repo.

### 1.6 service-monitor.md

**Purpose:** Check 12 services and 21 timers for error patterns, restart loops, and Cluster A silent failures.

**Model:** sonnet | **Tools:** Read, Grep, Glob, Bash

**Architecture:** 80% bash (deterministic checks), 20% AI (pattern reasoning on summaries).

**Per-service checks:**
- `systemctl --user show <svc> -p ActiveState,SubState,NRestarts,Result,ExecMainStartTimestamp --value`
- `NRestarts` + `ActiveEnterTimestamp` → restart frequency
- `journalctl --user -u <svc> --since "24 hours ago" -q | wc -l` → if active + 0 lines = Cluster A silent failure
- Top 20 error messages (deduplicated)

**Per-timer checks:**
- `LastTriggerUSec` via `systemctl --user show` → compare against expected interval
- Timers not fired in 2x their interval = STALE

**Known patterns to detect:**
- Telegram 409 → `grep "409"` in telegram-*.service logs
- MQTT disconnect loop → `grep -i "disconnect\|reconnect"` in aria-hub
- OOM kills → `Result == oom-kill` + `journalctl -k --since "24h ago" | grep oom`

**State taxonomy per service:** OK / RECOVERED / RESTARTING / FAILED / ANOMALY (Cluster A: active but silent)

**Output:** Service health table + timer freshness table + anomaly details.

---

## Part 2: Existing Agent Improvements (8)

### P0 — Correctness (prevents wrong output)

| Agent | Change | Why |
|-------|--------|-----|
| security-reviewer | Add hallucination guard: "Only report findings grounded in specific file:line evidence" | Prevents false findings that drive unnecessary work |
| security-reviewer | Remove Bash tool → Read, Grep, Glob only | Read-only review should not have shell execution |
| security-reviewer | Add Python/bash attack categories: `pickle.loads`, `eval`, `subprocess(shell=True)`, hardcoded secrets | Currently web-focused, misses 75% of codebase |
| infra-auditor | Fix sync freshness: add `$(date +%s)` delta math to `stat -c '%Y'` | Current comparison is broken |
| lesson-scanner | Update description: "53 lessons" → "66 lessons" | Stale count |

### P1 — Quality (prevents waste)

| Agent | Change | Why |
|-------|--------|-----|
| All 6 missing | Add `model` field | Prevents wrong model routing |
| All agents | Add `maxTurns` (infra-auditor: 15, counter: 20, others: 25) | Prevents runaway execution |
| security-reviewer | Add explicit trigger phrases to description | Improves delegation accuracy |
| doc-updater | Fix git diff: `HEAD~1` → `git status --short && git diff HEAD` | Misses uncommitted changes |

### P2 — Capability (meaningful new features)

| Agent | Change | Why |
|-------|--------|-----|
| lesson-scanner | Add Scan Group 7: Plan Quality (Lessons #60-66) | Research-derived lessons not currently scanned |
| lesson-scanner | Add Scan 3f: `.venv/bin/pip` (Lesson #51) | Hookify warns but scanner should also flag |
| counter | Add Clusters E and F to Bias Detection lens | Lesson regression check incomplete |
| notion-researcher | Add vector search fallback behavior | Zero-result behavior undefined |
| notion-writer | Add pre-flight API key check | Currently discovers missing key on first 401 |

### P3 — Polish

| Agent | Change | Why |
|-------|--------|-----|
| doc-updater | Add structured output summary | Currently returns no summary of changes made |
| counter-daily | Add "acknowledge once and stop" rule | Prevents morphing into full counter session |
| security-reviewer | Add `memory: project` | Baseline known-safe patterns across sessions |

### Agent Chains (future)

**Chain 1: Post-commit audit** — security-reviewer → lesson-scanner → doc-updater (single `/post-commit-audit` command)

**Chain 2: Service triage** — infra-auditor (detect) → shell-expert (investigate) → service-monitor (verify fix)

**Chain 3: Pre-release** — dependency-auditor → integration-tester → lesson-scanner

---

## Part 3: Linting Tooling

### Tools to Install

| Tool | Install | Purpose |
|------|---------|---------|
| shellcheck | Already installed (0.9.0) | Static analysis |
| shfmt | `brew install shfmt` | Formatting |
| shellharden | `brew install shellharden` | Quoting hardening |
| semgrep | `pip3 install semgrep` | Security pattern matching |

### Makefile Changes

```makefile
.PHONY: test validate lint ci

lint:
	@echo "=== ShellCheck ==="
	@shellcheck scripts/*.sh scripts/lib/*.sh
	@echo "=== shfmt ==="
	@shfmt -d -i 2 -ci scripts/*.sh scripts/lib/*.sh
	@echo "=== Shellharden ==="
	@shellharden --check scripts/*.sh scripts/lib/*.sh 2>/dev/null || true
	@echo "=== Semgrep ==="
	@semgrep --config "p/bash" --quiet scripts/ 2>/dev/null || true

test:
	@bash scripts/tests/run-all-tests.sh

validate:
	@bash scripts/validate-all.sh

ci: lint validate test
	@echo "CI: ALL PASSED"
```

### CI Changes (.github/workflows/ci.yml)

Add shellcheck + shfmt to the CI job:

```yaml
- name: Install linting tools
  run: |
    sudo apt-get install -y jq shellcheck
    GO_VERSION=1.21 && curl -sS https://webi.sh/shfmt | sh
    pip install semgrep
- name: Run CI
  run: make ci
```

### .shellcheckrc (new file in repo root)

```
# Enable all optional checks
enable=all
# Exclude specific rules we've explicitly decided to ignore
# SC2086 — we have intentional word-splitting in quality-gate.sh (tracked as issue #5)
```

---

## Implementation Order

1. **Install tools** (shfmt, shellharden, semgrep) — 5 min
2. **Add .shellcheckrc + Makefile lint target** — 10 min
3. **Update CI** — 5 min
4. **Create 6 new agents** — using research docs as source material
5. **Apply P0 improvements to existing agents** — correctness fixes first
6. **Apply P1-P3 improvements** — quality, capability, polish
7. **Symlink research docs to ~/Documents/research/** — per workspace convention

---

## Research Sources

| Document | Lines | Path |
|----------|-------|------|
| Bash expert | 543 | `docs/plans/2026-02-23-research-bash-expert-agent.md` |
| Shell expert | 533 | `docs/plans/2026-02-23-research-shell-expert-agent.md` |
| Python expert | 429 | `docs/plans/2026-02-23-research-python-expert-agent.md` |
| Integration tester | 454 | `docs/plans/2026-02-23-research-integration-tester-agent.md` |
| Dependency auditor | 564 | `docs/plans/2026-02-23-research-dependency-auditor-agent.md` |
| Service monitor | 425 | `docs/plans/2026-02-23-research-service-monitor-agent.md` |
| Existing improvements | 503 | `docs/plans/2026-02-23-research-improving-existing-agents.md` |
