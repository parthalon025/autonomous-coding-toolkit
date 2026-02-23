# Research: Shell Expert Claude Code Agent

**Date:** 2026-02-23
**Status:** Complete
**Confidence:** High on tool landscape and check taxonomy; Medium on agent structure (few direct precedents for this exact scope)
**Cynefin domain:** Complicated — knowable with expert analysis
**Scope:** System operations agent — systemd services, PATH/environment issues, package management, permissions, config integrity. NOT script writing (that belongs to bash-expert, not this agent).

---

## BLUF

No public Claude Code agent targets the narrow ops domain this agent needs: systemd lifecycle, PATH/environment debugging, package health, and permissions auditing on a personal Linux workstation. The closest precedents are the existing `infra-auditor` agent (already in `~/.claude/agents/`) and the `devops-engineer` agents from VoltAgent/wshobson, which are cloud-IaC-oriented and too broad. The shell-expert agent should be built as a **diagnostic and remediation agent** scoped to five ops domains, using `systemd-analyze` as its primary systemd oracle, Lynis-style check categories as its audit vocabulary, and the existing `infra-auditor` as its status-monitoring complement (not replacement). Build as `~/.claude/agents/shell-expert.md`.

---

## Section 1: Claude Code Custom Agent Survey — DevOps/Infrastructure

### Sources

- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) — 100+ production subagents, infrastructure category
- [wshobson/agents](https://github.com/wshobson/agents) — 76 agents, multi-agent orchestration
- [iannuttall/claude-agents](https://github.com/iannuttall/claude-agents) — lightweight agent collection
- [Anthropic sub-agents docs](https://code.claude.com/docs/en/sub-agents)
- Existing `~/.claude/agents/infra-auditor.md` — Justin's current ops agent

### Findings

**Structural pattern (all sources agree on this format):**
```yaml
---
name: shell-expert
description: "Use this agent when diagnosing systemd service failures, PATH/environment issues, package management problems, file permissions, or environment configuration on Linux. NOT for writing shell scripts."
tools: Read, Grep, Glob, Bash
model: sonnet
---
```

The description field is the routing key — Claude dispatches to the agent when user intent matches. The description must be specific enough to avoid false invocations on scripting tasks (those go to bash-expert).

**VoltAgent devops-engineer agent — key elements:**
- Focus: CI/CD pipelines, containers, Kubernetes, cloud IaC — cloud-first, not host-first
- Model: sonnet (correct for ops work)
- No systemd-specific checks, no PATH debugging, no host package management
- Success metrics: 100% automation, >99.9% availability — enterprise framing, not personal workstation

**wshobson devops-troubleshooter agent:**
- Purpose: "Debug production issues, analyze logs, and fix deployment failures"
- Model: sonnet
- Coordinate with: devops-troubleshooter, incident-responder, network-engineer
- Gap: Still cloud/container-centric; does not cover host-level systemd lifecycle or local environment config

**wshobson network-engineer agent:**
- Purpose: "Debug network connectivity, configure load balancers, and analyze traffic"
- Relevant for: Tailscale diagnostics, DNS resolution failures — partial overlap with shell-expert scope

**Existing infra-auditor (Justin's):**
- Strength: Targeted service health checks, named services, connectivity probes, resource thresholds, config integrity assertions
- Gap: Status monitoring, not diagnosis — tells you something is broken but doesn't root-cause it or remediate
- Gap: No systemd unit hardening analysis, no PATH/environment debugging, no package management audit
- Gap: Hardcoded to specific services — not general-purpose for new service setup or failure investigation

**Key pattern from all agents surveyed:** The most useful ops agents have a **checklist-driven diagnostic flow** rather than open-ended instructions. Every domain (services, environment, packages) should have explicit ordered steps that the agent follows, not just "investigate the issue."

**Adoption decision:** The shell-expert agent should be the *diagnostic and remediation companion* to infra-auditor's *monitoring* role. When infra-auditor flags a failure, shell-expert is invoked to root-cause and fix it. They are complementary, not overlapping.

---

## Section 2: Systemd Service Management — Tools and Validators

### Sources

- [priv-kweihmann/systemdlint](https://github.com/priv-kweihmann/systemdlint) — Python-based linter for unit files
- [mackwic/systemd-linter](https://github.com/mackwic/systemd-linter) — Cross-platform unit file linter
- [systemd/systemd — issue #3677: unit syntax validation](https://github.com/systemd/systemd/issues/3677)
- [systemd-analyze man page](https://www.freedesktop.org/software/systemd/man/latest/systemd-analyze.html)
- [linux-audit.com — systemd-analyze](https://linux-audit.com/system-administration/commands/systemd-analyze/)
- [linux-audit.com — how to verify systemd unit errors](https://linux-audit.com/systemd/faq/how-to-verify-a-systemd-unit-for-errors/)
- [containersolutions.github.io — debug systemd service units runbook](https://containersolutions.github.io/runbooks/posts/linux/debug-systemd-service-units/)

### Findings

**systemd-analyze — the primary oracle:**

`systemd-analyze` has four subcommands relevant to this agent:

| Subcommand | What it does | Use case |
|---|---|---|
| `systemd-analyze verify UNIT` | Lints unit file — unknown sections, invalid settings, dependency cycles | Pre-flight before enabling a new unit |
| `systemd-analyze security UNIT` | Scores hardening posture 0–10 (lower = more secure); lists missing directives | Hardening audit |
| `systemd-analyze blame` | Lists units by activation time, sorted descending | Boot performance investigation |
| `systemd-analyze critical-chain` | Timing tree of dependency chain | Slow boot root cause |
| `systemd-analyze syscall-filter` | Lists syscall filter sets for sandboxing | Understanding `SystemCallFilter` options |

The `security` subcommand produces JSON output (`--json=pretty`) with per-setting exposure scores — usable programmatically without parsing human-readable output.

**systemdlint (priv-kweihmann):**
- Originally for cross-compiled embedded images (no live systemd available)
- Hardening advice output format: `{file}:{line}:{severity} [{id}] - {message}`
- Example ID: `NoFailureCheck` — return code checking disabled
- Value: Identifies hardening gaps without running the service
- Limitation: Does not use systemd's own interpretation; may differ from live systemd behavior

**systemd-linter (mackwic):**
- Cross-platform (Linux, macOS, Windows)
- Validates unit file structure, applies industry best-practices
- Useful for writing/reviewing unit files before deployment

**Debugging runbook (containersolutions):**

Ordered diagnostic procedure for failed services:
1. `systemctl status <service> --no-pager` — immediate state + recent log lines
2. `journalctl -u <service> -n 50 --no-pager` — full log context
3. `journalctl -u <service> -f` — live tail during manual restart attempt
4. `systemctl status --full --lines=50 <service>` — extended status
5. Disable `Restart=` temporarily to see underlying errors without auto-restart loop masking them
6. Run `ExecStart` command manually as the service user (`sudo -u <user> <command>`) to reproduce the environment
7. Check environment: `systemctl show <service> -p Environment`

**Environment-related failure class (most common for user services):**
- systemd does NOT inherit shell PATH or env vars
- When PATH is missing: binary lookup uses `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin` (compiled-in fixed value)
- When `~` is used in ExecStart: not expanded (systemd is not a shell)
- When `$HOME` is in `EnvironmentFile`: not shell-expanded — values are literal

**Check to adopt:** Before diagnosing any service failure, the agent should first check `systemctl show <service> -p Environment,EnvironmentFile,ExecStart,WorkingDirectory` to get the full runtime config, not just the unit file.

---

## Section 3: Systemd Hardening — Check Taxonomy

### Sources

- [linux-audit.com — how to harden systemd service unit](https://linux-audit.com/systemd/how-to-harden-a-systemd-service-unit/)
- [linuxjournal.com — systemd service strengthening](https://www.linuxjournal.com/content/systemd-service-strengthening)
- [ctrl.blog — systemd service sandboxing 101](https://www.ctrl.blog/entry/systemd-service-hardening.html)
- [synacktiv.com — SHH: systemd hardening made easy](https://www.synacktiv.com/en/publications/systemd-hardening-made-easy-with-shh)
- [rockylinux.org — systemd units hardening](https://docs.rockylinux.org/9/guides/security/systemd_hardening/)

### Findings

**Hardening directives by category:**

**Privilege escalation prevention:**
- `NoNewPrivileges=true` — prevents process and children from escalating privileges (SUID, capabilities)
- `CapabilityBoundingSet=` — restrict Linux capabilities to the minimum required (e.g., `CAP_NET_BIND_SERVICE`)
- `RestrictSUIDSGID=true` — prevents setuid/setgid file creation

**Filesystem restrictions:**
- `PrivateTmp=yes` — isolated `/tmp` namespace; eliminates tmp-prediction attacks
- `ProtectSystem=strict` — mounts `/usr`, `/boot`, `/efi` read-only; `=full` also protects `/etc`
- `ProtectHome=yes` — blocks home directory access; `=read-only` allows reads
- `ReadOnlyPaths=`, `ReadWritePaths=`, `InaccessiblePaths=` — fine-grained path control
- `RootDirectory=` — chroot-like confinement
- `NoExecPaths=/`, `ExecPaths=/usr/bin/myapp` — whitelist-only execution

**Namespace isolation:**
- `PrivateDevices=yes` — isolates hardware device access
- `PrivateNetwork=yes` — isolated network namespace (for services with no network needs)
- `RestrictNamespaces=uts ipc pid user cgroup` — blocks specific namespace isolation syscalls
- `ProtectKernelModules=yes` — prevents explicit kernel module loading

**Kernel/system protection:**
- `ProtectKernelTunables=yes` — read-only kernel tunables (sysctl values)
- `ProtectControlGroups=yes` — prevents cgroup modification
- `ProtectClock=yes` — blocks clock changes
- `ProtectHostname=yes` — blocks hostname/NIS domain changes

**Syscall filtering:**
- `SystemCallFilter=@system-service` — predefined safe set for typical services
- `SystemCallFilter=~@mount` — blacklist specific syscall groups

**Memory security:**
- `MemoryDenyWriteExecute=yes` — prevents W^X violations (JIT engines need this disabled)
- `RestrictRealtime=yes` — prevents real-time scheduling (reduces DoS risk)
- `LockPersonality=yes` — locks execution domain (prevents personality changes)

**Network controls:**
- `IPAddressAllow=192.168.1.0/24` — whitelist allowed source IPs
- `RestrictAddressFamilies=AF_UNIX AF_INET` — restrict socket families
- `SocketBindDeny=any` — prevent socket binding except explicitly allowed

**SHH (Synacktiv) — automated hardening approach:**
- Profiles service via strace during operation
- Maps syscall behavior to compatible hardening directives
- Excludes directives incompatible with observed behavior
- Selects most restrictive set that still permits normal operation
- Good model for the agent's hardening recommendation workflow: observe → profile → recommend

**Exposure score interpretation:**
- `systemd-analyze security <unit>` returns 0.0–10.0 (lower is better)
- Rating scale: 0–3 = OK, 3–5 = Medium, 5–7 = Exposed, 7–10 = UNSAFE
- The linuxjournal example went from 9.6 (UNSAFE) to 4.9 (OK) through incremental hardening
- Recommendation: agent should run this on every user service and flag anything >5

**Check to adopt:** The agent should run `systemd-analyze security <service> --json=pretty` on every unit it is asked about, parse exposure score, and present top 5 missing directives by exposure weight.

---

## Section 4: Linux System Hardening Auditors

### Sources

- [CISOfy/lynis](https://github.com/CISOfy/lynis) — agentless security auditing for Linux/Unix/macOS
- [nikhilkumar0102/Linux-cis-audit](https://github.com/nikhilkumar0102/Linux-cis-audit) — CIS benchmark auditor for Debian 12
- [sokdr/LinuxAudit](https://github.com/sokdr/LinuxAudit) — bash audit script
- [gopikrishna152/security-audit-hardening](https://github.com/gopikrishna152/security-audit-hardening) — combined audit + hardening
- [trimstray/linux-hardening-checklist](https://github.com/trimstray/linux-hardening-checklist) — production checklist

### Findings

**Lynis — most comprehensive, most adoptable patterns:**

Lynis uses unique identifiers per check (e.g., `KRNL-6000`, `AUTH-9328`) organized by category. Each check maps to a specific audit question. The categories most relevant to this agent:

| Category | What it covers |
|---|---|
| Boot | GRUB/GRUB2 password, boot loader config |
| Services | systemctl enabled/disabled, startup services, service manager detection |
| Users & Groups | Shadow passwords, password aging, inactive accounts, sudo config |
| File Permissions | `/etc/passwd`, `/etc/shadow`, `/etc/cron.*` ownership and perms |
| Package Management | Outdated/vulnerable packages, GPG key verification, update policy |
| Kernel | Kernel version, loaded modules, sysctl hardening parameters |
| Authentication | PAM config, SSH config, failed login attempts |
| Networking | Firewall status, open ports, ARP config |
| Storage | Filesystem options (nodev, nosuid, noexec on mounts) |

**Lynis-derived check vocabulary for the agent:**

For **package management** domain:
- Is `apt-get check` clean? (no broken dependencies)
- Are packages on hold? (`apt-mark showhold`)
- Are security updates available? (`apt list --upgradable 2>/dev/null | grep -i security`)
- Are orphaned packages present? (`deborphan` if installed)
- Is GPG verification enabled in apt config?

For **permissions** domain:
- World-writable files in key directories (`find /etc -perm -o+w`)
- SUID/SGID binaries not in known-good list (`find / -perm -4000 -o -perm -2000`)
- `~/.env` mode is 600 (not 644, not 664)
- Sensitive config files owned by root or service user

For **users/groups** domain:
- No UID 0 accounts beyond root
- Password aging set for interactive accounts
- sudo configured with least privilege (NOPASSWD scope is minimal)

**CIS benchmark auditor patterns (nikhilkumar0102):**
- Color-coded PASS/FAIL per check — easy to adopt for agent report format
- Actionable recommendation per failure — agent should follow this pattern
- CIS benchmark categories map well to Lynis categories above

**Check to adopt:** Lynis's output format (check ID → severity → recommendation) is the right model for the agent's report section. Every finding should include: what was checked, what was found, what to do.

---

## Section 5: Environment and PATH Debugging

### Sources

- [linuxvox.com — systemd Environment directive PATH expansion](https://linuxvox.com/blog/systemd-environment-directive-to-set-path/)
- [itsfoss.gitlab.io — systemd service environment variables](https://itsfoss.gitlab.io/blog/systemd-service-environment-variables)
- [baeldung.com — systemd environment variables](https://www.baeldung.com/linux/systemd-services-environment-variables)
- [containersolutions runbook — debug systemd service units](https://containersolutions.github.io/runbooks/posts/linux/debug-systemd-service-units/)
- [systemd.io — known environment variables](https://systemd.io/ENVIRONMENT/)

### Findings

**The three most common PATH/environment failure classes:**

1. **PATH missing version manager shims** — nvm, pyenv, rbenv inject shims at shell init time (`~/.bashrc`, `~/.bash_profile`). systemd user services do not source these. Binary found in interactive shell; not found in service.
   - Diagnosis: `systemctl show <service> -p Environment` — verify PATH contains `/home/user/.nvm/versions/node/vX.X.X/bin` or equivalent
   - Fix: Add explicit `Environment=PATH=/home/user/.nvm/versions/node/vX.X.X/bin:/usr/local/bin:/usr/bin:/bin` to unit file, or use `ExecStart=/absolute/path/to/binary`

2. **EnvironmentFile quoting issues** — systemd's `EnvironmentFile=` does not do shell processing. Quoted values in the file are NOT unquoted: `KEY="value"` produces `KEY='"value"'` (with quotes). Shell scripts and `.env` files often use quotes; systemd does not strip them.
   - Diagnosis: Reproduce by running `sudo -u <user> env` after loading the file vs. `printenv KEY` inside the service
   - Fix: Strip quotes from EnvironmentFile values, or use `Environment="KEY=value"` (one level of quoting, shell-processed by systemd before execution)

3. **Tilde and variable expansion** — `ExecStart=~/bin/myapp` or `ExecStart=$HOME/bin/myapp` fail silently (binary not found) because systemd does not expand `~` or shell variables in `ExecStart`. Use absolute paths always.
   - Diagnosis: `systemctl status` shows `code=exited, status=203/EXEC` — executable not found
   - Fix: Replace `~/` with `/home/username/`, replace `$HOME` with literal path in ExecStart

**The fixed systemd PATH (when no PATH is set in unit):**
```
/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
```
Version manager shims, Homebrew (`/home/linuxbrew/.linuxbrew/bin`), and `~/.local/bin` are NOT in this fixed path.

**Justin's specific PATH gotcha (from CLAUDE.md):**
Homebrew Python 3.14 is first on PATH (`python3`). System python3.12 at `/usr/bin/python3`. Services that need ML packages must use `python3` (Homebrew path) not the system Python. The PATH in user services must be set explicitly to get this right.

**Diagnostic command sequence for PATH issues:**
```bash
# Step 1: See what PATH the service actually has
systemctl show <service> -p Environment

# Step 2: See what the unit file says
systemctl cat <service>

# Step 3: Manually test with the service user's environment
sudo -u justin env -i HOME=/home/justin PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin bash -c 'which python3'

# Step 4: Check if EnvironmentFile values have quotes
grep -E '^[A-Z_]+=".+"' /path/to/env-file  # quotes that systemd will NOT strip
```

**Check to adopt:** When the agent is asked about any service failure with `status=203/EXEC` (not found), it should run the four-step PATH diagnostic above before suggesting any other fix.

---

## Section 6: Package Management Auditing

### Sources

- [linux-audit.com — auditing Linux software packages](https://linux-audit.com/auditing-linux-software-packages-managers/)
- [baeldung.com — apt packages kept back](https://www.baeldung.com/linux/apt-packages-kept-back)
- [oneuptime.com — fix broken packages Ubuntu](https://oneuptime.com/blog/post/2026-01-15-fix-broken-packages-ubuntu/view)
- [labex.io — verify Linux package status](https://labex.io/tutorials/linux-how-to-verify-linux-package-status-435583)
- Lynis package management category (from Section 4)

### Findings

**Package health check taxonomy:**

| Check | Command | What to flag |
|---|---|---|
| Broken dependencies | `sudo apt-get check` | Any output = broken state |
| Held-back packages | `apt-mark showhold` | Unexpected holds |
| Security updates | `apt list --upgradable 2>/dev/null \| grep -i security` | Any = action required |
| Orphaned packages | `apt-get autoremove --dry-run` | Review before running |
| Broken package list | `dpkg -l \| grep -E '^(iF\|iU\|rF)'` | Install-required/failed states |
| GPG key validity | `apt-key list 2>/dev/null` (deprecated) / `/etc/apt/trusted.gpg.d/` | Expired or untrusted keys |
| Apt cache stale | `stat /var/cache/apt/pkgcache.bin` — warn if >48h old | Cache not refreshed |

**Common failure patterns and fixes:**

`apt-get: The following packages have been kept back` — usually caused by:
1. A dependency changed (transitional package split)
2. A new package is required but would be a new install (apt won't auto-install new packages)
3. Fix: `sudo apt-get install --install-recommends <packages>` or `sudo apt full-upgrade`

Broken packages from partial upgrade:
1. `sudo dpkg --configure -a` — complete any interrupted configuration
2. `sudo apt-get install -f` — fix broken dependencies
3. `sudo apt-get check` — verify state after each step

**Check to adopt:** The package audit should always run `apt-get check` first (instant, non-destructive). If it fails, escalate to the dpkg/install-f sequence before attempting manual resolution.

---

## Section 7: Infrastructure-as-Code Review Patterns

### Sources

- [analysis-tools-dev/static-analysis](https://github.com/analysis-tools-dev/static-analysis) — curated SAST tool list
- [checkov](https://www.checkov.io/) — IaC security scanning (Terraform, CloudFormation, K8s)
- [tflint](https://github.com/terraform-linters/tflint) — Terraform-specific linter
- [bytebase.com — top open source IaC security tools](https://www.bytebase.com/blog/top-open-source-iac-security-tools/)
- [OWASP — IaC security cheat sheet](https://cheatsheetseries.owasp.org/cheatsheets/Infrastructure_as_Code_Security_Cheat_Sheet.html)

### Findings

**Relevance to this agent:** Justin's "infrastructure-as-code" is primarily systemd unit files, `~/.env` structure, Tailscale Serve config, and shell profile modifications. Not Terraform/CloudFormation. The IaC review tools are not directly adoptable, but the *review methodology* is:

**IaC review patterns worth adopting for unit file/config review:**

1. **Static analysis before live testing** — verify/lint the file before enabling the service (maps to `systemd-analyze verify` + `systemdlint`)
2. **Security policy as code** — hardening requirements are explicit, checkable, not just guidelines (maps to `systemd-analyze security` with threshold assertion)
3. **Drift detection** — compare running config against source-of-truth unit file (`systemctl cat <service>` vs. `~/.config/systemd/user/<service>.service`)
4. **Dependency graph validation** — `systemd-analyze critical-chain` for startup ordering; `After=`, `Requires=`, `Wants=` correctness

**Checkov patterns (adapted for systemd):**
- Every service should declare `After=network.target` if it makes network connections
- Services using `User=` should not also use `PrivilegedInstall=` or run as root
- `EnvironmentFile=` paths should be absolute, not relative
- `WorkingDirectory=` should not be `/` (common default that leaks filesystem access)

---

## Section 8: Synthesis — Best Patterns to Adopt

### Gap analysis: what does no existing tool do?

| Capability | Existing tool | Gap |
|---|---|---|
| Service status monitoring | `infra-auditor` | None — already covered |
| Unit file syntax validation | `systemd-analyze verify` | Not yet in any agent |
| Security exposure scoring | `systemd-analyze security` | Not yet in any agent |
| PATH/environment root cause | None (manual process) | **Gap — primary agent value** |
| Package health audit | `apt-get check` (manual) | Not yet in any agent |
| Permissions audit | `find` (manual) | Not yet in any agent |
| Hardening recommendations | `systemd-analyze security` output | Not yet surfaced to agent |
| Unit file vs. live config drift | `systemctl cat` vs. file | Not yet in any agent |

### Decision matrix: agent vs. script vs. manual

| Task | Right tool | Reason |
|---|---|---|
| Routine service health check | `infra-auditor` (existing) | Already built, named-service checks |
| New service failing at start | `shell-expert` | Root cause requires diagnostic tree |
| PATH/env debugging | `shell-expert` | Requires judgment about which PATH source applies |
| Package audit | `shell-expert` | Fits same diagnostic/remediation pattern |
| Permissions review | `shell-expert` | Requires context about what should own what |
| Boot performance investigation | `shell-expert` | `systemd-analyze blame` + critical-chain interpretation |
| Unit file hardening | `shell-expert` | `systemd-analyze security` + recommendation |

### Core diagnostic flows to encode in the agent

**Flow 1: Service failure triage**
```
status=203 (exec failed) → PATH diagnostic → absolute path check
status=1 (runtime error) → journalctl → manual repro as service user
status=failed (dependency) → systemd-analyze verify → dependency check
active=failed (startup timeout) → systemd-analyze critical-chain → slow dep
```

**Flow 2: PATH/environment root cause**
```
1. systemctl show <service> -p Environment,EnvironmentFile,ExecStart
2. Check if ExecStart uses ~/ or $HOME → flag, suggest absolute path
3. Check if EnvironmentFile has quoted values → flag, show fix
4. Check if required binary is outside systemd's fixed PATH → add Environment= directive
5. Check for Homebrew/nvm/pyenv shims needed → explicit PATH with version manager bins
```

**Flow 3: Hardening audit**
```
1. systemd-analyze security <service> --json=pretty
2. Report exposure score with rating (OK/Medium/Exposed/UNSAFE)
3. List top 5 missing directives by exposure weight
4. For each: show current state → recommended value → impact
5. Flag services >5.0 as requiring attention
```

**Flow 4: Package health**
```
1. apt-get check → if fails, stop and fix before anything else
2. apt-mark showhold → report any held packages
3. apt list --upgradable | grep -i security → report security updates
4. apt-get autoremove --dry-run → report orphaned package count
```

### Report format (adopt from Lynis + infra-auditor patterns)

```
SHELL-EXPERT DIAGNOSIS — <service/domain> — <date>

CRITICAL (fix before proceeding):
- [ID] <finding> → <command to fix>

WARNING (action recommended):
- [ID] <finding> → <recommended action>

INFO (informational):
- [ID] <finding> → <explanation>

DIAGNOSIS SUMMARY:
- Root cause: <one-sentence root cause>
- Fix: <one or two commands>
- Verification: <command that confirms fix>
```

---

## Section 9: Recommended Agent Structure

### Option A: Single shell-expert agent (recommended)

Create `~/.claude/agents/shell-expert.md` covering all five ops domains. Each domain has its own ordered diagnostic checklist. The agent decides which domain's flow to execute based on user intent.

**Frontmatter:**
```yaml
---
name: shell-expert
description: "Use this agent when diagnosing systemd service failures, PATH/environment issues, package management problems, file permissions auditing, or environment configuration on Linux. This agent performs diagnosis and remediation, NOT script writing."
tools: Read, Grep, Glob, Bash
model: sonnet
---
```

**Five diagnostic domains (ordered sections in agent body):**

1. **Service Lifecycle** — triage failure exit codes, journalctl, manual repro, dependency verification, `systemd-analyze verify`
2. **Environment & PATH** — four-step PATH diagnostic, EnvironmentFile quoting, tilde expansion, version manager shim detection
3. **Hardening Audit** — `systemd-analyze security` → exposure score → top-5 directives → fix recommendations
4. **Package Management** — `apt-get check` → held packages → security updates → orphaned packages → broken deps
5. **Permissions** — `~/.env` mode, SUID/SGID audit, world-writable scan, service user ownership

**Relationship to infra-auditor:**
- `infra-auditor` = monitoring (is everything up right now?)
- `shell-expert` = investigation (why did it fail and how to fix it?)
- Trigger: when infra-auditor reports CRITICAL, shell-expert is the next step

### Option B: Split into shell-health + shell-hardening

Split service lifecycle/environment/packages into `shell-health` (reactive/diagnosis) and hardening into `shell-hardening` (proactive/audit). Only warranted if the combined agent exceeds ~300 lines of instructions and routing ambiguity becomes a problem.

**Recommendation: Option A.** The five domains are naturally sequenced and a single agent with domain sections is cleaner. If it grows unwieldy, split at that point.

### What NOT to include

- Script writing or bash one-liners on demand → bash-expert (not yet built)
- Service monitoring on a schedule → infra-auditor (already built)
- Cloud/IaC/Terraform → different agent, different scope
- Tailscale network debugging → infra-auditor has connectivity checks; shell-expert handles host-side only (socket, bind address, lingering)

---

## References

- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents)
- [wshobson/agents](https://github.com/wshobson/agents)
- [iannuttall/claude-agents](https://github.com/iannuttall/claude-agents)
- [priv-kweihmann/systemdlint](https://github.com/priv-kweihmann/systemdlint)
- [mackwic/systemd-linter](https://github.com/mackwic/systemd-linter)
- [systemd-analyze man page](https://www.freedesktop.org/software/systemd/man/latest/systemd-analyze.html)
- [linux-audit.com — systemd-analyze](https://linux-audit.com/system-administration/commands/systemd-analyze/)
- [linux-audit.com — how to verify systemd unit errors](https://linux-audit.com/systemd/faq/how-to-verify-a-systemd-unit-for-errors/)
- [linux-audit.com — how to harden systemd service unit](https://linux-audit.com/systemd/how-to-harden-a-systemd-service-unit/)
- [linux-audit.com — auditing Linux software packages](https://linux-audit.com/auditing-linux-software-packages-managers/)
- [linuxjournal.com — systemd service strengthening](https://www.linuxjournal.com/content/systemd-service-strengthening)
- [ctrl.blog — systemd service sandboxing 101](https://www.ctrl.blog/entry/systemd-service-hardening.html)
- [synacktiv.com — SHH systemd hardening helper](https://www.synacktiv.com/en/publications/systemd-hardening-made-easy-with-shh)
- [rockylinux.org — systemd units hardening](https://docs.rockylinux.org/9/guides/security/systemd_hardening/)
- [CISOfy/lynis](https://github.com/CISOfy/lynis)
- [nikhilkumar0102/Linux-cis-audit](https://github.com/nikhilkumar0102/Linux-cis-audit)
- [trimstray/linux-hardening-checklist](https://github.com/trimstray/linux-hardening-checklist)
- [containersolutions — debug systemd service units runbook](https://containersolutions.github.io/runbooks/posts/linux/debug-systemd-service-units/)
- [linuxvox.com — systemd Environment PATH](https://linuxvox.com/blog/systemd-environment-directive-to-set-path/)
- [baeldung.com — systemd environment variables](https://www.baeldung.com/linux/systemd-services-environment-variables)
- [baeldung.com — apt packages kept back](https://www.baeldung.com/linux/apt-packages-kept-back)
- [OWASP — IaC security cheat sheet](https://cheatsheetseries.owasp.org/cheatsheets/Infrastructure_as_Code_Security_Cheat_Sheet.html)
- [analysis-tools-dev/static-analysis](https://github.com/analysis-tools-dev/static-analysis)
