# Research: Service Monitor Claude Code Agent

**Date:** 2026-02-23
**Status:** Research complete — ready for agent design
**Confidence:** High on patterns, Medium on gap between existing tools and Claude Code agent idioms

---

## BLUF

No existing tool does exactly what's needed. The closest analog is GASP (AI-first monitoring for LLM consumption) combined with systemd_mon's event-driven DBus model and pengutronix's `check-systemd-service` property enumeration. The agent should be structured as a Bash-heavy Claude Code subagent that runs a deterministic inspection suite, then applies AI pattern recognition to output a structured severity report. The key gap all existing tools miss: proactively hunting Cluster A (silent failure) patterns — services that are technically "active" but have swallowed errors and are doing nothing.

---

## Section 1: Claude Code Agent Infrastructure

**Source:** [Anthropic Claude Code Sub-agents Documentation](https://code.claude.com/docs/en/sub-agents) | [wshobson/agents](https://github.com/wshobson/agents) | [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) | [Piebald-AI/claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts)

### Agent File Format

Subagents are `.md` files with YAML frontmatter stored at `~/.claude/agents/` (user-level) or `.claude/agents/` (project-level). The frontmatter controls all behavior:

```yaml
---
name: service-monitor
description: Monitors all user systemd services and timers for failures, restart loops, silent errors, and resource anomalies. Use when asked about service health.
tools: Bash, Read, Grep
model: sonnet
memory: user
---
```

Key frontmatter fields relevant to this agent:
- `tools: Bash, Read, Grep` — Bash is essential; Read/Grep for config file inspection
- `model: sonnet` — sufficient for pattern recognition; haiku acceptable for pure data collection
- `memory: user` — enables cross-session baseline learning (stores to `~/.claude/agent-memory/service-monitor/`)
- `permissionMode: default` — standard; no need for bypassPermissions since monitoring is read-only
- `maxTurns` — consider capping at 40 to prevent runaway inspection loops

### Existing Agent Catalog Gaps

The wshobson/agents catalog has 100 agents across 9 categories. The infrastructure category includes `observability-engineer` (SLI/SLO management, distributed tracing) and `devops-incident-responder` but nothing targeting local systemd service health on a single machine. VoltAgent's collection similarly lacks systemd-specific agents — its closest entry is `sre-engineer`.

The `infra-auditor` agent already in `~/.claude/agents/infra-auditor.md` provides a template: it checks named services with `systemctl --user is-active`, runs connectivity probes, and checks resource usage. The service-monitor agent should be its successor — deeper on log analysis, more systematic on all 12 services and 21 timers, and specifically designed to find Cluster A silent failures.

---

## Section 2: Systemd Service Monitoring Tools

### 2.1 systemd_mon

**Source:** [joonty/systemd_mon](https://github.com/joonty/systemd_mon)

A Ruby daemon that monitors systemd units via DBus subscription (no polling). Relevant patterns:

- **Event-driven via DBus:** Subscribes to state-change notifications — zero CPU overhead at idle. For a Claude Code agent (which runs on-demand rather than as a daemon), the equivalent is `systemctl --user list-units` + `systemctl show` — a snapshot-based approach.
- **State aggregation:** Systemd emits granular intermediate states (activating/start-pre, activating/start) during transitions. systemd_mon queues these until a stable terminal state emerges, then classifies the outcome as: `recovered`, `automatically restarted`, or `still failed`. This three-state taxonomy is exactly right for the agent's report format.
- **Restart loop detection:** If a service cycles through activating→failed→activating repeatedly, the queue of state transitions reveals the loop before the `StartLimitBurst` threshold is hit. The agent equivalent: check `NRestarts` from `systemctl show` combined with `ActiveEnterTimestamp` to compute restart frequency.
- **Alerting channels:** Email, Slack, HipChat. Not directly applicable, but the pattern of "agent-detected event → Telegram notification" fits the existing Telegram infrastructure.

### 2.2 GASP (AI-First Linux Monitoring)

**Source:** [AcceleratedIndustries/gasp](https://github.com/AcceleratedIndustries/gasp)

The most directly relevant philosophy: monitoring designed for LLM consumption, not human dashboards. Key design principles:

- **Context-rich output format:** Structures data for AI reasoning rather than for terminal readability. Each service entry includes state, restart count, recent errors, and resource usage in a single coherent block.
- **Planned features (in development):** systemd unit states + failed services + restart tracking; 24-hour rolling baselines for anomaly detection; journal log analysis with error rate trending and pattern detection; MCP server implementation.
- **AI-first anomaly detection:** Rather than threshold alerting (PagerDuty model), GASP aims for contextual reasoning — "is this error rate unusual given time of day and service type?" This is the right model for a Claude Code agent.
- **Gap:** GASP is still early-stage and daemon-based (Go binary). The Claude Code agent gets the same benefit without a separate process by running on-demand with AI reasoning inline.

### 2.3 pengutronix/monitoring-check-systemd-service

**Source:** [pengutronix/monitoring-check-systemd-service](https://github.com/pengutronix/monitoring-check-systemd-service)

A Nagios/Icinga plugin that provides the most complete enumeration of `systemctl show` properties worth checking:

- Uses DBus (not parsing `systemctl status` text output) — stable, machine-readable
- Properties it checks: `Id`, `ActiveState`, `SubState`, `LoadState`
- State mapping (directly adoptable):
  - `LoadState != loaded` → NOT_LOADED (service missing or masked)
  - `ActiveState == failed` → CRITICAL
  - `ActiveState == active` → OK
  - `ActiveState == inactive`, `SubState == dead` → DEAD (warn)
  - `ActiveState == activating/deactivating/reloading` → CHANGING (potential restart loop)
- **Key insight:** Parsing `systemctl status` text output is explicitly discouraged by systemd developers (Lennart Poettering). Use `systemctl show -p PropertyName` or DBus. The agent should use `systemctl --user show <service> -p ActiveState,SubState,NRestarts,Result,ExecMainStartTimestamp,ActiveEnterTimestamp`.

### 2.4 systemd-doctor

**Source:** [0xkelvin/systemd-doctor](https://github.com/0xkelvin/systemd-doctor)

Embedded Linux service health tracker. Relevant patterns:
- Stores metrics in a time-series database to detect trend-based anomalies, not just point-in-time failures
- Integrates with systemd to auto-restart services when abnormalities detected
- For the agent: the equivalent of trend tracking is `memory: user` — the agent reads/writes its `MEMORY.md` to track baseline restart counts, error rates per service, and flag deviations from previous runs.

---

## Section 3: Log Pattern Analysis Tools

### 3.1 gjalves/logwatch

**Source:** [gjalves/logwatch](https://github.com/gjalves/logwatch)

Real-time log monitor (C) for syslog and systemd. Relevant patterns:
- Pattern-to-action model: define a regex → trigger a script
- Dual source support: both syslog (`/var/log/syslog`) and systemd journal (via journalctl)
- For the agent: the equivalent is running `journalctl --user -u <service> --since "24 hours ago" -p warning -o cat` per service, then scanning output for known error patterns

### 3.2 journalctl Patterns for Log Analysis

**Sources:** [DigitalOcean journalctl guide](https://www.digitalocean.com/community/tutorials/how-to-use-journalctl-to-view-and-manipulate-systemd-logs) | [Last9 journalctl cheatsheet](https://last9.io/blog/journalctl-commands-cheatsheet/) | [freedesktop.org journalctl man page](https://www.freedesktop.org/software/systemd/man/latest/journalctl.html)

The most useful journalctl invocations for the agent:

```bash
# Error count per service (last 24h)
journalctl --user -u <service> --since "24 hours ago" -p err -q --no-pager | wc -l

# Most frequent error messages (deduped)
journalctl --user -u <service> --since "24 hours ago" -p warning -o cat --no-pager \
  | sort | uniq -c | sort -rn | head -20

# Restart loop detection: look for rapid state transitions
journalctl --user -u <service> --since "1 hour ago" -o cat --no-pager \
  | grep -E "(Started|Stopped|Failed|start limit)" | tail -20

# JSON output for structured parsing
journalctl --user -u <service> --since "1 hour ago" -p err -o json --no-pager

# System-level: find ALL services with recent errors (across all services at once)
journalctl --user --since "24 hours ago" -p err --no-pager -q -o cat \
  | grep "_SYSTEMD_UNIT=" | sort | uniq -c | sort -rn
```

**Priority levels for the agent:**
- `-p err` (level 3): errors only — good for critical detection
- `-p warning` (level 4): warnings + errors — good for Cluster A silent failure hunting
- `-p info` (level 6): all messages — useful for verifying a service is actually doing work (not just alive)

**Silent failure detection pattern (Cluster A):**
A service can be `active (running)` but have produced zero log output in 24 hours — it's alive but doing nothing. Detection:
```bash
# Count of log entries in last 24h (any priority)
journalctl --user -u <service> --since "24 hours ago" --no-pager -q | wc -l
# If count == 0 AND service is active: SILENT FAILURE CANDIDATE
```

### 3.3 incident-helper

**Source:** [malikyawar/incident-helper](https://github.com/malikyawar/incident-helper)

AI-powered terminal assistant for SREs. Key architectural decisions:

- **ServiceResolver:** Runs `systemctl status <service>` + extracts structured fields (unit file, PID, memory, state, recent log lines) into a context block for LLM reasoning
- **LogResolver:** Reads log files + applies regex pattern detection before passing to LLM — reduces token usage by pre-filtering
- **Provider abstraction:** Supports multiple LLM backends (OpenAI, Anthropic, local) — for the Claude Code agent, the LLM is Claude itself, so the pre-filtering pattern still applies
- **Context-aware prompting:** Includes specialized system prompts for "service down", "high error rate", "restart loop" scenarios — each with different diagnostic questions

**Key insight:** Pre-filter log output before passing to the LLM. Running 12 services × 24h of logs = potentially hundreds of KB of text. The agent should: (1) collect raw counts and error summaries via bash, (2) extract only the top 20 most frequent error messages per service, (3) pass that structured summary to Claude for pattern reasoning.

---

## Section 4: systemctl Properties for Health Checking

**Sources:** [systemctl.com show command reference](https://www.systemctl.com/commands/show/) | [freedesktop.org systemctl man](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html) | [Baeldung NRestarts guide](https://www.baeldung.com/linux/systemd-show-times-service-restarted)

### Service Properties (via `systemctl --user show <service> -p ...`)

| Property | Use |
|----------|-----|
| `ActiveState` | active/inactive/failed/activating/deactivating |
| `SubState` | running/dead/exited/failed (substate of ActiveState) |
| `LoadState` | loaded/not-found/masked |
| `NRestarts` | Cumulative auto-restart count since last manual start |
| `Result` | success/exit-code/signal/core-dump/watchdog/start-limit-hit |
| `ExecMainStartTimestamp` | When main process last started (ISO format) |
| `ActiveEnterTimestamp` | When service last became active |
| `ActiveExitTimestamp` | When service last stopped being active |
| `ExecMainExitTimestamp` | When main process last exited |
| `MainPID` | Current main process PID (0 if not running) |
| `MemoryCurrent` | Current memory usage in bytes |
| `MemoryMax` | Configured memory limit |
| `CPUUsageNSec` | Cumulative CPU time |

**Restart loop detection formula:**
```bash
NRESTARTS=$(systemctl --user show <service> -p NRestarts --value)
ENTER_TS=$(systemctl --user show <service> -p ActiveEnterTimestamp --value)
# If NRestarts > 3 and ActiveEnterTimestamp < 1 hour ago: recent restart loop
```

**Start-limit-hit detection:**
```bash
RESULT=$(systemctl --user show <service> -p Result --value)
# If Result == "start-limit-hit": service is in death spiral, won't auto-restart
```

### Timer Properties (via `systemctl --user show <timer> -p ...`)

| Property | Use |
|----------|-----|
| `LastTriggerUSec` | Last time the timer fired (microseconds since epoch) |
| `NextElapseUSecRealtime` | Next scheduled fire time |
| `ActiveState` | active (waiting) / inactive / failed |
| `Result` | success/failure for last trigger |

**Missed run detection:**
```bash
LAST_TRIGGER=$(systemctl --user show <timer>.timer -p LastTriggerUSec --value)
NOW_USEC=$(date +%s%6N)  # current time in microseconds
AGE_HOURS=$(( (NOW_USEC - LAST_TRIGGER) / 3600000000 ))
# Compare against expected interval (e.g., notion-sync should fire every 6h)
# If AGE_HOURS > 1.5 * expected_interval: MISSED RUN
```

**Known issue:** `systemctl list-timers` output is human-formatted. Machine-readable checks require `systemctl show` with `-p` flags.

---

## Section 5: Dependency Health Patterns

**Sources:** [Netdata systemd units monitoring](https://www.netdata.cloud/monitoring-101/systemdunits-monitoring/) | [CubePath service monitoring guide](https://cubepath.com/docs/monitoring-logging/service-monitoring-with-systemd) | [Zabbix systemd template](https://github.com/MogiePete/zabbix-systemd-service-monitoring)

### Service Dependency Failure Cascade

Systemd tracks `Wants=`, `Requires=`, `After=` dependencies. A service can fail because its dependency failed — the unit itself shows "failed" but the root cause is elsewhere. Detection pattern:

```bash
# Check if a failed service has failed dependencies
systemctl --user list-dependencies <service> --failed
# Or: check the service's own log for "dependency failed" messages
journalctl --user -u <service> --since "1 hour ago" -o cat | grep -i "depend"
```

**Known dependency in the target system:**
- `aria-hub.service` depends on MQTT broker (core_mosquitto on HA Pi). If `aria-hub` fails, the agent should check MQTT connectivity: `nc -z <mqtt-broker-ip> 1883`
- `telegram-listener.service` and `telegram-capture.service` both poll the same Telegram bot API. The 409 conflict error ("getUpdates: only one must be allowed") appears in their logs as a distinct pattern. The agent must check for this specific pattern.

### Known Failure Patterns to Detect

| Pattern | Service(s) | Detection |
|---------|-----------|-----------|
| Telegram 409 conflict | telegram-listener, telegram-capture | `journalctl --user -u telegram-*.service --since "1h ago" \| grep "409"` |
| Ollama queue starvation | ollama-queue | Check port 7683 responds; check queue length via API |
| MQTT disconnect | aria-hub | `journalctl --user -u aria-hub --since "1h ago" \| grep -i "mqtt\|disconnect\|reconnect"` |
| Memory limit OOM kill | open-webui, gpt-researcher | `Result == oom-kill` in systemctl show; `journalctl -k --since "24h ago" \| grep "oom"` |
| Start limit hit | any | `Result == start-limit-hit` — service will not auto-restart |
| Silent active failure | any | `ActiveState == active` + 0 log entries in 24h |

---

## Section 6: Timer and Cron Job Monitoring

**Sources:** [check_systemd PyPI](https://pypi.org/project/check_systemd/) | [healthchecks.io](https://healthchecks.io/) | [ArchWiki systemd/Timers](https://wiki.archlinux.org/title/Systemd/Timers)

### check_systemd (Python, PyPI)

A Nagios-compatible plugin that includes timer-specific monitoring:
- `--dead-timers` parameter detects timers that have not fired in longer than expected
- Checks `LastTriggerUSec` against a configurable age threshold
- Supports both system and user scope (`--user` flag)

Installation: `pip install check_systemd`. Relevant invocation:
```bash
check_systemd --user --dead-timers --dead-timers-warning 1.5 --dead-timers-critical 2.0
# Warning if timer hasn't fired in 1.5x its expected interval
```

### Timer Health Check Strategy

The 21 timers have varying intervals. The agent needs a per-timer expected interval table:

| Timer | Expected Interval | Max Acceptable Age |
|-------|------------------|--------------------|
| `aria-watchdog.timer` | 5 minutes | 15 minutes |
| `ha-log-sync.timer` | 15 minutes | 45 minutes |
| `telegram-brief-alerts.timer` | 5 minutes | 15 minutes |
| `notion-sync.timer` | 6 hours | 9 hours |
| `notion-vector-sync.timer` | 6 hours | 9 hours |
| `telegram-capture-sync.timer` | 6 hours | 9 hours |
| `telegram-brief-{morning,midday,evening}.timer` | daily | 30 hours |
| `aria-*.timer` (daily) | daily | 30 hours |
| `aria-*.timer` (weekly) | weekly | 9 days |
| `ha-log-sync-rotate.timer` | daily | 30 hours |
| `lessons-review.timer` | monthly | 35 days |

---

## Synthesis: Best Patterns to Adopt

### Pattern 1: Deterministic Inspection + AI Interpretation (from incident-helper)

Do NOT ask Claude to "look at the services." Instead, run a deterministic bash inspection suite that produces structured data, then pass that structured data to Claude for pattern reasoning. The agent's job is 80% bash data collection, 20% AI interpretation.

### Pattern 2: Three-Tier Severity from systemd_mon

Adopt the `recovered / restarting / still-failed` taxonomy and expand it:
- **CRITICAL:** `ActiveState == failed`, `Result == start-limit-hit`, `Result == oom-kill`
- **WARNING:** `NRestarts > 3` in last hour, timer missed by >1.5x interval, error count > threshold
- **ANOMALY (Cluster A):** `ActiveState == active` + zero log entries in 24h, Telegram 409 in logs, MQTT disconnect loop
- **OK:** All checks pass

### Pattern 3: Machine-Readable Properties Only (from pengutronix)

Never parse `systemctl status` text. Always use:
```bash
systemctl --user show <service> -p ActiveState,SubState,NRestarts,Result,ExecMainStartTimestamp --value
```

### Pattern 4: Per-Service Log Error Rate (from GASP's AI-first philosophy)

For each service, compute: `(error_count_last_24h, warning_count_last_24h, total_entries_last_24h)`. Pass the ratio, not the raw logs. A service with 1000 entries and 5 errors (0.5%) is healthier than one with 10 entries and 3 errors (30%).

### Pattern 5: Memory-Based Baselines (from systemd-doctor + GASP)

Use `memory: user` to persist:
- NRestarts baseline per service (from last clean run)
- Error rate baseline per service
- "Last seen active" timestamp for silent failure detection
Compare current values against stored baselines; flag deviations >2x as anomalies.

### Pattern 6: Pre-Filter Before LLM (from incident-helper's LogResolver)

```bash
# Collect: top 20 error messages per service (deduplicated)
journalctl --user -u <service> --since "24 hours ago" -p err -o cat --no-pager \
  | sort | uniq -c | sort -rn | head -20
```

Pass this 20-line summary to Claude, not hundreds of raw log lines.

---

## Recommended Agent Structure

### File Location

`~/.claude/agents/service-monitor.md` (user-level, available in all projects)

### Frontmatter

```yaml
---
name: service-monitor
description: Audits all 12 user systemd services and 21 timers for failures, restart loops, silent errors, resource anomalies, and known failure patterns (Telegram 409, MQTT disconnect, OOM kills, start-limit-hit). Use when asked about service health, when services may be failing silently, or before commits that touch service code.
tools: Bash, Read, Grep
model: sonnet
memory: user
maxTurns: 50
---
```

### System Prompt Structure (recommended sections)

1. **Identity:** You are a systemd service health monitor for a personal Linux workstation with 12 user services and 21 timers.

2. **Inspection phases (ordered):**
   - Phase 1: Service state sweep (all 12 services via `systemctl --user show`)
   - Phase 2: Timer health check (all 21 timers, compare LastTriggerUSec against interval table)
   - Phase 3: Per-service log analysis (error rates, silent failure detection, known pattern matching)
   - Phase 4: Resource anomaly check (memory usage vs MemoryMax, load average)
   - Phase 5: Known failure pattern scan (Telegram 409, MQTT disconnect, OOM kills)
   - Phase 6: Baseline comparison (read MEMORY.md for previous baselines, flag deviations)

3. **Data collection commands:** Explicit bash commands for each phase (do not improvise)

4. **Output format:** Severity-stratified report (CRITICAL / WARNING / ANOMALY / OK) with recommended actions

5. **Memory update:** After each run, update MEMORY.md with new baselines

### Report Format

```
SERVICE MONITOR REPORT — <timestamp>

CRITICAL (immediate action required):
- [service]: [issue] — [recommended action]

WARNING (investigate soon):
- [service]: [issue] — [recommended action]

ANOMALY — Cluster A Candidates (silent failures):
- [service]: active but [N] log entries in 24h (baseline: [M]) — verify service is doing work

TIMER ISSUES:
- [timer]: last fired [X] hours ago (expected: every [Y] hours)

OK: [N] services healthy, [M] timers on schedule

Baseline updated: [timestamp]
```

### Known Limitations to Document in the Agent

1. `NRestarts` is cumulative since last `systemctl --user start` — it does not reset on auto-restart. This means a service restarted manually 30 days ago and auto-restarted 5 times since shows NRestarts=5, but a service that was started 1 hour ago and crashed 5 times also shows NRestarts=5. Must combine with `ActiveEnterTimestamp` to compute restart frequency.

2. `LastTriggerUSec` returns 0 for timers that have never fired (e.g., newly installed). The agent should detect this and flag it as a setup issue, not a missed run.

3. User systemd scope requires `--user` flag on all `systemctl` and `journalctl` commands. System-scope services (ssh.socket, tailscaled) require separate invocations without `--user`.

4. `journalctl --user` may require lingering to be enabled (`loginctl show-user justin -p Linger`). If lingering is off, user services stop on logout and logs may be incomplete.

---

## Sources

- [Anthropic Claude Code Sub-agents Documentation](https://code.claude.com/docs/en/sub-agents) — definitive agent file format, frontmatter fields, permissionMode, memory scopes
- [joonty/systemd_mon](https://github.com/joonty/systemd_mon) — event-driven DBus monitoring, state aggregation, restart loop taxonomy
- [AcceleratedIndustries/gasp](https://github.com/AcceleratedIndustries/gasp) — AI-first monitoring philosophy, context-rich output for LLM consumption
- [pengutronix/monitoring-check-systemd-service](https://github.com/pengutronix/monitoring-check-systemd-service) — machine-readable property enumeration, DBus-over-text-parsing rationale
- [malikyawar/incident-helper](https://github.com/malikyawar/incident-helper) — ServiceResolver + LogResolver architecture, pre-filtering before LLM
- [gjalves/logwatch](https://github.com/gjalves/logwatch) — pattern-to-action model, syslog + systemd dual source
- [0xkelvin/systemd-doctor](https://github.com/0xkelvin/systemd-doctor) — time-series health tracking for trend-based anomaly detection
- [systemd/python-systemd](https://github.com/systemd/python-systemd) — programmatic journal access API
- [check_systemd PyPI](https://pypi.org/project/check_systemd/) — timer dead-run detection, `--dead-timers` parameter
- [wshobson/agents](https://github.com/wshobson/agents) — Claude Code agent catalog structure, observability-engineer pattern
- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) — subagent design patterns, infrastructure category coverage
- [Piebald-AI/claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts) — Claude Code system prompt internals
- [DigitalOcean journalctl guide](https://www.digitalocean.com/community/tutorials/how-to-use-journalctl-to-view-and-manipulate-systemd-logs) — journalctl flag reference
- [Last9 journalctl cheatsheet](https://last9.io/blog/journalctl-commands-cheatsheet/) — practical monitoring patterns
- [freedesktop.org systemctl man](https://www.freedesktop.org/software/systemd/man/latest/systemctl.html) — authoritative property reference
- [MogiePete/zabbix-systemd-service-monitoring](https://github.com/MogiePete/zabbix-systemd-service-monitoring) — multi-service discovery and monitoring template
- [healthchecks.io](https://healthchecks.io/) — cron/timer missed-run detection model
- [Netdata systemd units monitoring](https://www.netdata.cloud/monitoring-101/systemdunits-monitoring/) — metrics and state monitoring reference
