# Research: Dependency Auditor Agent for 8-Repo Workspace

**Date:** 2026-02-23
**Status:** Research complete
**Scope:** Tool survey + pattern synthesis for a Claude Code agent that audits 8 project repos (6 Python, 1 Node/Preact, 1 Docker) for outdated packages, CVEs, and license compliance
**Method:** Web search across 7 tool categories + codebase reconnaissance on all 8 target repos

---

## Executive Summary

BLUF: The dependency auditor agent should use a 3-tool stack per ecosystem — **pip-audit** (CVEs, Python), **npm audit** (CVEs, Node), **Trivy** (Docker + multi-ecosystem cross-check) — unified by **OSV-Scanner** as the JSON-normalized aggregator, with **pip-licenses** and **license-checker** for license compliance. Existing Claude Code command examples confirm this is a well-trodden slash-command pattern. The agent can cover all 8 repos in a single orchestrated run, producing a per-repo severity table and a workspace rollup.

Confidence: high on tool selection, medium on Docker-specific scanning (gpt-researcher is the only Docker repo and uses a Python base image, so pip-audit still applies inside).

---

## 1. Target Repo Inventory

Surveyed from `~/Documents/projects/`:

| Repo | Package Manager | Manifest Files | Ecosystem |
|------|----------------|----------------|-----------|
| `ha-aria` | pip (pyproject.toml) | `pyproject.toml` | Python |
| `notion-tools` | pip | `requirements.txt` | Python |
| `ollama-queue` | pip (pyproject.toml) | `pyproject.toml` | Python |
| `telegram-agent` | pip | `requirements.txt` | Python |
| `telegram-brief` | pip | `requirements.txt` | Python |
| `telegram-capture` | pip | `requirements.txt` | Python |
| `superhot-ui` | npm | `package.json` | Node/Preact |
| `gpt-researcher` | pip + Poetry + Docker | `pyproject.toml`, `requirements.txt`, `poetry.toml`, `Dockerfile` | Python + Docker |

Key observations:
- 6 pure Python repos, split between `requirements.txt` and `pyproject.toml` — pip-audit handles both natively
- 1 Node repo (`superhot-ui`) with minimal deps (only `esbuild` and `preact` as devDeps) — npm audit is sufficient
- 1 hybrid Docker repo (`gpt-researcher`) — Python base image means pip-audit applies inside, Trivy adds layer analysis
- No Go, Rust, or Java — tool selection can be narrow

---

## 2. Source Research: CVE Scanners

### 2.1 pip-audit (Python)

**Source:** [pip-audit on PyPI](https://pypi.org/project/pip-audit/) | [pypa/pip-audit on GitHub](https://github.com/pypa/pip-audit)

The official PyPA vulnerability scanner, Google-backed, no paid subscription required. Queries the OSV database via the PyPI JSON API and the GitHub Python Advisory Database.

**Key capabilities:**
- Scans requirements.txt, pyproject.toml, and installed environments
- `--format json` produces structured output with: `name`, `version`, `vulns[].id` (PYSEC IDs), `vulns[].aliases` (CVE + GHSA IDs), `vulns[].fix_versions`, `vulns[].description`
- `--fix` flag auto-installs minimal fix version; `--fix --dry-run` previews without installing
- `--output-format cyclonedx-json` for SBOM output
- Operates on a requirements file without needing an installed environment: `pip-audit -r requirements.txt`

**Limitation:** Does not include vulnerability severity ratings (CVSS scores). OSV-Scanner or Trivy required for severity.

**CLI patterns for the agent:**
```bash
pip-audit -r requirements.txt -f json -o audit-results.json
pip-audit --pyproject pyproject.toml -f json -o audit-results.json
```

### 2.2 Safety (Python, secondary)

**Source:** [safety on PyPI](https://pypi.org/project/safety/)

Safety checks against the PyUp Safety DB, which includes some CVEs not yet in OSV. Useful as a cross-reference but requires account for full database access since Safety 3.x. Not recommended as primary — pip-audit's OSV backend has better coverage and no auth requirement.

### 2.3 OSV-Scanner (cross-language, aggregator)

**Source:** [google/osv-scanner on GitHub](https://github.com/google/osv-scanner) | [OSV-Scanner V2 announcement](https://security.googleblog.com/2025/03/announcing-osv-scanner-v2-vulnerability.html)

Google's unified scanner querying osv.dev — the largest aggregated open source vulnerability database (NVD, GitHub Advisories, ecosystem-specific advisories).

**Key capabilities:**
- Supports 11+ language ecosystems and 19+ lockfile types in one tool
- Scans Python lockfiles (`requirements.txt`, `Pipfile.lock`, `poetry.lock`), npm lockfiles (`package-lock.json`, `yarn.lock`), and Docker images
- JSON output format: `osv-scanner --format json`
- V2 (March 2025): adds guided remediation for npm and Maven, container image scanning with layer analysis, interactive HTML reports
- Handles the `superhot-ui` package.json and all Python repos in a single scan command

**CLI patterns:**
```bash
# Scan all repos in one pass
osv-scanner scan --recursive /home/justin/Documents/projects/ --format json

# Scan single repo
osv-scanner scan --lockfile requirements.txt --format json
```

**Why this is the aggregation layer:** Produces a single normalized JSON report across all 8 repos with consistent severity scoring. pip-audit is more Python-authoritative, but OSV-Scanner provides the cross-repo rollup.

### 2.4 npm audit (Node.js)

**Source:** [npm audit documentation](https://www.nodejs-security.com/blog/how-to-use-npm-audit)

Built-in to npm — no installation needed. Scans `package-lock.json` against the npm Advisory Database.

**Key capabilities:**
- `npm audit --json` produces structured output with severity, CVE IDs, CVSS scores, and fix recommendations
- `npm audit fix` auto-installs fixes; `npm audit fix --dry-run` previews
- For `superhot-ui`, which only has `esbuild` and `preact` as devDeps, audit run time is sub-second
- Limitation: requires `package-lock.json` to exist; `superhot-ui` uses no lockfile currently (check before running)

**CLI pattern:**
```bash
cd /home/justin/Documents/projects/superhot-ui
npm audit --json
```

### 2.5 Trivy (Docker + multi-ecosystem)

**Source:** [aquasecurity/trivy on GitHub](https://github.com/aquasecurity/trivy) | [Trivy docs](https://trivy.dev/)

Aqua Security's open source scanner. Covers containers, filesystems, Kubernetes, and code repositories. Best tool for the `gpt-researcher` Docker image.

**Key capabilities:**
- Scans Docker images with layer analysis: shows which layer introduced each vulnerability
- Supports Python (pip), Node.js (npm), Go, Java, and 15+ other ecosystems
- Detects OS-level CVEs (apt/dpkg) inside Docker images — critical for the `python:3.12-slim-bookworm` base in `gpt-researcher`
- `--format json` for machine-parseable output; `--format sarif` for GitHub Security tab integration
- `--severity HIGH,CRITICAL` to filter noise; `--exit-code 1` for CI blocking

**CLI patterns:**
```bash
# Scan Dockerfile context (builds and scans)
trivy image --format json gpt-researcher:local

# Scan filesystem without container build
trivy fs --format json /home/justin/Documents/projects/gpt-researcher/

# Scan Docker image for OS + Python CVEs
trivy image --scanners vuln --severity HIGH,CRITICAL --format json python:3.12-slim-bookworm
```

### 2.6 OWASP dep-scan (secondary, multi-ecosystem)

**Source:** [owasp-dep-scan/dep-scan on GitHub](https://github.com/owasp-dep-scan/dep-scan) | [OWASP dep-scan PyPI](https://pypi.org/project/owasp-depscan/)

Next-generation OWASP tool combining vulnerability scanning, license checking, and reachability analysis in one tool. Installable via pip (`pip install owasp-depscan`) or Docker.

**Key capabilities:**
- Supports Python, JavaScript, Java, Go, and more
- Includes license compliance checking alongside CVE detection
- Reachability analysis for Python, JavaScript, TypeScript — distinguishes actually-called vulnerable code from unused deps
- Reports in JSON, HTML, SARIF, CycloneDX
- Docker mode: `docker run --rm -v $PWD:/app ghcr.io/owasp-dep-scan/dep-scan depscan --src /app`

**Assessment:** More complex setup than pip-audit + OSV-Scanner combo. The reachability analysis is genuinely valuable for ha-aria (large codebase), but adds operational overhead. Classify as optional enhancement, not baseline.

---

## 3. Source Research: License Compliance

### 3.1 pip-licenses (Python)

**Source:** [pip-licenses on PyPI](https://pypi.org/project/pip-licenses/)

The standard Python license inventory tool.

**Key capabilities:**
- Outputs per-package license info in JSON, Markdown, CSV, HTML formats
- Detection strategy: mixed-mode by default (Trove classifiers first, then package metadata)
- `--from=mixed` is default and most accurate
- `--format json --with-urls --with-description` for full metadata
- `--fail-on "GPL"` to exit non-zero if GPL-licensed deps found (CI-blocking)
- `--allow-only "MIT;Apache Software License;BSD License;ISC License"` to enforce allowlist

**Limitation:** Must run inside a virtualenv where deps are installed; cannot operate on requirements.txt without installation.

**CLI pattern:**
```bash
# Inside each repo's .venv
.venv/bin/pip-licenses --format json --with-urls --fail-on "GPL-3.0"
```

**For the agent:** Run per-repo after activating the virtualenv. Agent should detect venv path from `.venv/`, `venv/`, or `env/`.

### 3.2 pip-license-checker (Python + JS)

**Source:** [pilosus/pip-license-checker on GitHub](https://github.com/pilosus/pip-license-checker) | [pilosus/action-pip-license-checker](https://github.com/pilosus/action-pip-license-checker)

Detects license types (permissive, copyleft, proprietary) for PyPI and npm packages. Supports Python, JavaScript, iOS, and Android — unique in spanning ecosystems.

**Key capabilities:**
- Works on requirements.txt directly (no venv installation needed) — advantage over pip-licenses
- Classifies licenses into permissive / weak-copyleft / strong-copyleft / proprietary
- Supports `--fail-on-copyleft` and `--fail-on-proprietary` flags
- GitHub Action available for CI integration

**Assessment:** Better than pip-licenses for the license-type classification use case (permissive vs. copyleft), but pip-licenses is better for generating the full license inventory report. Use both: pip-license-checker for compliance gating, pip-licenses for the report.

### 3.3 license-checker (Node.js)

**Source:** [license-checker npm package](https://www.npmjs.com/package/license-checker)

Standard Node.js license inventory tool.

**Key capabilities:**
- `license-checker --json` for machine-parseable output
- `--excludePrivatePackages` to skip private packages
- `--onlyAllow "MIT;ISC;BSD"` for compliance enforcement (exits non-zero on violation)
- `--failOn "GPL"` to block on specific licenses

**CLI pattern:**
```bash
cd /home/justin/Documents/projects/superhot-ui
npx license-checker --json --onlyAllow "MIT;ISC;BSD;CC0"
```

---

## 4. Source Research: Dependency Update Tools

### 4.1 Renovate (primary recommendation)

**Source:** [renovatebot/renovate on GitHub](https://github.com/renovatebot/renovate) | [Renovate vs Dependabot comparison](https://www.turbostarter.dev/blog/renovate-vs-dependabot-whats-the-best-tool-to-automate-your-dependency-updates)

The strongest Dependabot alternative. AGPL-3.0, self-hostable, supports GitHub, GitLab, Bitbucket, Azure DevOps.

**Advantages over Dependabot:**
- Dependency Dashboard — single issue showing all pending updates per repo
- Organization-level shared presets — define update rules once for all 8 repos
- Per-package, per-manager, per-repo update rules
- Grouping rules — batch related updates into one PR (e.g., "all pytest-related updates")
- Supports pyproject.toml, requirements.txt, package.json, Dockerfile (base image updates)

**Limitation for this use case:** Renovate generates PRs, it doesn't produce audit reports. The auditor agent is the scanner; Renovate would be the automated fixer. These are complementary, not competing.

**Assessment for this project:** All 8 repos are private. Renovate can run self-hosted via `npx renovate` or as a cron job. Worth noting in the agent design as the "automated fix" companion to the audit agent's "detect" role. Not in scope for the auditor agent itself.

### 4.2 pip-compile / pip-tools (Python update workflow)

**Source:** Standard Python tooling

`pip-compile` from pip-tools upgrades requirements.txt files to latest compatible versions and generates pinned lockfiles. The agent can surface outdated packages via `pip list --outdated --format json` without pip-tools, but pip-tools provides the safe upgrade path.

**CLI pattern for the agent (detect only):**
```bash
pip list --outdated --format json
```

### 4.3 npm-check-updates (Node.js)

**Source:** Standard npm ecosystem

`ncu` (npm-check-updates) lists packages with available updates beyond what `package.json` allows.

**CLI pattern:**
```bash
npx npm-check-updates --jsonUpgraded
```

---

## 5. Source Research: SBOM Generators

### 5.1 Syft (multi-ecosystem)

**Source:** [anchore/syft on GitHub](https://github.com/anchore/syft)

Anchore's SBOM generator. Supports Python, Go, Java, JavaScript, Ruby, Rust, PHP, .NET, and container images.

**Key capabilities:**
- Output formats: CycloneDX JSON, SPDX JSON, Syft JSON
- Works on project directories and container images
- Integrates with Grype (Anchore's vulnerability scanner) for CVE correlation against the SBOM

**CLI patterns:**
```bash
syft /home/justin/Documents/projects/ha-aria -o cyclonedx-json=ha-aria-sbom.json
syft ./gpt-researcher -o spdx-json=gpt-researcher-sbom.json
```

### 5.2 CycloneDX (ecosystem-specific)

**Source:** [CycloneDX/cyclonedx-python on GitHub](https://github.com/CycloneDX/cyclonedx-python) | [CycloneDX/cyclonedx-node-npm](https://github.com/CycloneDX/cyclonedx-node-npm)

The OWASP CycloneDX standard has official generators for Python and npm. More accurate than Syft for single-ecosystem repos.

**CLI patterns:**
```bash
# Python — from requirements.txt
cyclonedx-py requirements -r requirements.txt -o bom.json

# Node — from package-lock.json
cyclonedx-npm --package-lock-only --output-file bom.json
```

**Assessment for this project:** SBOM generation is not a core requirement for the auditor agent — it's useful for downstream tooling (Grype, Dependency-Track). Mark as optional output format. The auditor agent's primary output is a human-readable severity report and a JSON summary for programmatic use.

---

## 6. Source Research: Claude Code Agent Patterns

### 6.1 Existing Claude Code Command Suites

**Source:** [qdhenry/Claude-Command-Suite on GitHub](https://github.com/qdhenry/Claude-Command-Suite) | [wshobson/commands on GitHub](https://github.com/wshobson/commands)

The community has established these dependency audit patterns in Claude Code slash commands:

**From Claude-Command-Suite:**
- `/security:dependency-audit` — dedicated command for checking outdated dependencies
- Integrates with Bandit, Safety, Trivy, Semgrep, Snyk, and GitGuardian

**From wshobson/commands:**
- `/tools:deps-audit` — examines security vulnerabilities, license compliance, and version conflicts
- `/tools:deps-upgrade` — manages version updates with breaking change detection and rollback support
- Tool integrations listed: Bandit, Safety, Trivy, Semgrep, Snyk, GitGuardian

**Pattern confirmed:** Community separates "audit" (read-only detection) from "upgrade" (state-changing fix) into distinct commands. Adopt this separation.

### 6.2 Existing Lesson Scanner Agent (Internal Reference)

The `lesson-scanner.md` agent in this toolkit (at `agents/lesson-scanner.md`) provides the structural template:

1. **Input:** project root directory
2. **Step 1:** Load configuration (lessons from files; for auditor: tool availability check)
3. **Step 2:** Detect project type (Python/Node/Docker from manifest files)
4. **Step 3:** Run appropriate tools per ecosystem
5. **Step 4:** Normalize results
6. **Step 5:** Report with severity tiers (CRITICAL/HIGH/MEDIUM/LOW)

Key design principles from lesson-scanner to adopt:
- Dynamic dispatch based on detected project type, not hardcoded paths
- "Do not hallucinate findings" — report only what tools emit
- Structured tabular output with actionable fix guidance
- Run ALL checks even if earlier ones find issues

---

## 7. Cross-Cutting Synthesis

### 7.1 Tool Coverage Matrix

| Repo | CVE Scanner | License Checker | Outdated Packages | SBOM (optional) |
|------|-------------|-----------------|-------------------|-----------------|
| ha-aria | pip-audit + OSV-Scanner | pip-licenses | pip list --outdated | Syft/CycloneDX |
| notion-tools | pip-audit + OSV-Scanner | pip-licenses | pip list --outdated | Syft/CycloneDX |
| ollama-queue | pip-audit + OSV-Scanner | pip-licenses | pip list --outdated | Syft/CycloneDX |
| telegram-agent | pip-audit + OSV-Scanner | pip-licenses | pip list --outdated | Syft/CycloneDX |
| telegram-brief | pip-audit + OSV-Scanner | pip-licenses | pip list --outdated | Syft/CycloneDX |
| telegram-capture | pip-audit + OSV-Scanner | pip-licenses | pip list --outdated | Syft/CycloneDX |
| superhot-ui | npm audit + OSV-Scanner | license-checker | ncu | CycloneDX npm |
| gpt-researcher | pip-audit + Trivy + OSV-Scanner | pip-licenses | pip list --outdated | Syft |

### 7.2 Key Patterns to Adopt

**Pattern 1: Two-pass CVE scanning (per-ecosystem + cross-language)**
Run pip-audit/npm audit first for ecosystem-authoritative results, then OSV-Scanner for normalized aggregation. OSV-Scanner catches some CVEs the per-ecosystem tools miss (especially newer disclosures).

**Pattern 2: JSON output everywhere**
Every tool should emit `--format json` or `--json`. Agent parses JSON, not human-readable output. This makes the reporting layer independent of tool output format changes.

**Pattern 3: Severity gating**
- CRITICAL/HIGH: block and report immediately (map to lesson-scanner BLOCKER tier)
- MEDIUM: report as SHOULD-FIX
- LOW/INFORMATIONAL: report as NICE-TO-HAVE
- Use `--severity HIGH,CRITICAL` to suppress LOW noise in CI mode

**Pattern 4: Detect-then-fix separation**
The auditor agent is read-only. It does not `pip install`, `npm audit fix`, or modify any files. Output is a report + optional JSON summary. Fixes are a separate workflow (either manual or Renovate-driven).

**Pattern 5: venv-aware Python scanning**
pip-audit and pip-licenses must run inside the correct virtualenv per repo. The agent needs to detect the venv path (`ls .venv/bin/pip-audit 2>/dev/null || ls venv/bin/pip-audit 2>/dev/null`) and invoke tools through that path. If no venv exists, fall back to scanning the manifest file directly (`pip-audit -r requirements.txt`).

**Pattern 6: Outdated != vulnerable**
Separate outdated packages (version drift) from vulnerable packages (known CVE). These are different signals with different urgency. Outdated = maintenance debt; CVE = security risk.

**Pattern 7: License allowlist enforcement**
Define a workspace-level allowlist (MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, Python Software Foundation, CC0). Any dep outside the allowlist is flagged. GPL-3.0 and AGPL are blockers for commercial code.

---

## 8. Recommended Agent Structure

### 8.1 Agent Identity

```yaml
name: dependency-auditor
description: Scans all 8 project repos for CVEs, outdated packages, and license compliance.
             Produces a per-repo severity table and workspace rollup. Read-only — no packages
             are installed or updated.
tools: Bash, Read, Glob, Grep
```

### 8.2 Execution Steps

**Step 0: Tool availability check**
```bash
which pip-audit osv-scanner trivy npm npx 2>/dev/null
```
Report which tools are available. If pip-audit is missing, install it: `pip install pip-audit`. OSV-Scanner and Trivy require separate installation (flag if absent).

**Step 1: Repo detection**
For each repo under `~/Documents/projects/`, detect:
- Python: presence of `requirements.txt`, `pyproject.toml`, `Pipfile`, `poetry.lock`
- Node: presence of `package.json`
- Docker: presence of `Dockerfile`
- venv path: `.venv/`, `venv/`, `env/`

Exclude: `_archived/`, `autonomous-coding-toolkit/` (toolkit itself, no runtime deps).

**Step 2: CVE scanning (per repo)**

For Python repos:
```bash
# With venv
.venv/bin/pip-audit -f json 2>/dev/null || pip-audit -r requirements.txt -f json

# With pyproject.toml
pip-audit --pyproject pyproject.toml -f json
```

For Node repos:
```bash
npm audit --json
```

For Docker repos (additional pass):
```bash
trivy fs --format json --severity HIGH,CRITICAL .
```

**Step 3: CVE aggregation (OSV-Scanner)**
```bash
osv-scanner scan --recursive ~/Documents/projects/ --format json 2>/dev/null
```
Cross-reference with per-ecosystem results. OSV output is the source of truth for severity scores.

**Step 4: Outdated package detection (per repo)**

For Python:
```bash
.venv/bin/pip list --outdated --format json 2>/dev/null
```

For Node:
```bash
npx npm-check-updates --jsonUpgraded 2>/dev/null
```

**Step 5: License compliance (per repo)**

For Python:
```bash
.venv/bin/pip-licenses --format json --with-urls 2>/dev/null
```

For Node:
```bash
npx license-checker --json 2>/dev/null
```

Flag any dep outside: `["MIT", "Apache-2.0", "Apache Software License", "BSD-2-Clause", "BSD-3-Clause", "BSD License", "ISC", "Python Software Foundation License", "CC0-1.0", "Public Domain", "Unlicense"]`

**Step 6: Report**

```
## Dependency Audit Report
Workspace: ~/Documents/projects/
Scanned: <timestamp>
Repos scanned: 8

### CRITICAL / HIGH CVEs — Fix immediately
| Repo | Package | Version | CVE | Severity | Fix Version |
|------|---------|---------|-----|----------|-------------|

### MEDIUM CVEs — Fix this sprint
| Repo | Package | Version | CVE | Fix Version |
|------|---------|---------|-----|-------------|

### Outdated Packages (no known CVE)
| Repo | Package | Current | Latest | Drift |
|------|---------|---------|--------|-------|

### License Compliance Issues
| Repo | Package | License | Issue |
|------|---------|---------|-------|

### Workspace Rollup
- Total CVEs: N (X critical, Y high, Z medium)
- Total outdated packages: N
- License violations: N
- Cleanest repos: [list]
- Highest risk repos: [list]

### Recommended Fix Order
1. [Highest-severity finding with repo, package, fix version, pip install command]
```

### 8.3 Slash Command Definition

File: `~/.claude/commands/dep-audit.md` (global) or `commands/dep-audit.md` (toolkit)

```markdown
---
description: Audit all 8 project repos for CVEs, outdated packages, and license compliance
---

Invoke the dependency-auditor agent against ~/Documents/projects/.
Scan mode: $ARGUMENTS (options: all | <repo-name> | cve-only | license-only)
```

### 8.4 Systemd Timer (optional)

Weekly scan via systemd user timer, writing JSON output to `~/Documents/projects/autonomous-coding-toolkit/logs/dep-audit-latest.json`. Alert via Telegram if CRITICAL CVEs found (using existing telegram-capture pipeline).

---

## 9. Tool Installation Requirements

Tools not yet confirmed installed on this system:

| Tool | Install Command | Purpose |
|------|----------------|---------|
| pip-audit | `pip install pip-audit` | Python CVE scanning |
| OSV-Scanner | `curl -L https://github.com/google/osv-scanner/releases/latest/download/osv-scanner_linux_amd64 -o ~/.local/bin/osv-scanner && chmod +x ~/.local/bin/osv-scanner` | Cross-ecosystem aggregation |
| Trivy | `curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \| sh -s -- -b ~/.local/bin` | Docker + OS CVE scanning |
| pip-licenses | `pip install pip-licenses` | Python license inventory |
| license-checker | `npx license-checker` (no install needed) | Node license inventory |
| npm-check-updates | `npx npm-check-updates` (no install needed) | Node outdated packages |

Note: Verify with `which pip-audit osv-scanner trivy` before agent execution.

---

## 10. Open Questions / Pivot Triggers

1. **venv coverage gap:** If a Python repo has no `.venv/` (e.g., managed by Poetry or system-level install), pip-licenses cannot run. The agent must fall back to manifest-only scanning for that repo and flag the limitation.

2. **superhot-ui lockfile:** `superhot-ui` has `package.json` but may not have `package-lock.json` (repo uses minimal deps, lockfile may not be committed). npm audit requires a lockfile. Agent must check and prompt if missing: `cd superhot-ui && npm install --package-lock-only`.

3. **gpt-researcher Docker image:** Trivy image scanning requires a built Docker image. The agent should scan the Dockerfile filesystem path (`trivy fs .`) as a fallback when no image is built, accepting reduced accuracy for OS-level CVEs.

4. **OSV-Scanner V2 availability:** OSV-Scanner V2 was released March 2025. The agent should check version (`osv-scanner --version`) and note if V1 is installed (V2 has better guided remediation).

5. **Scope of license enforcement:** GPL-3.0 and AGPL-3.0 are blockers for commercial code but may be acceptable for personal tooling. Confirm allowlist policy before blocking.

---

## Sources

- [pip-audit on PyPI](https://pypi.org/project/pip-audit/)
- [pypa/pip-audit on GitHub](https://github.com/pypa/pip-audit)
- [OSV-Scanner V2 announcement](https://security.googleblog.com/2025/03/announcing-osv-scanner-v2-vulnerability.html)
- [google/osv-scanner on GitHub](https://github.com/google/osv-scanner)
- [OSV open source vulnerability DB](https://osv.dev/)
- [safety on PyPI](https://pypi.org/project/safety/)
- [OWASP dep-scan](https://github.com/owasp-dep-scan/dep-scan)
- [aquasecurity/trivy on GitHub](https://github.com/aquasecurity/trivy)
- [Renovate vs Dependabot comparison](https://www.turbostarter.dev/blog/renovate-vs-dependabot-whats-the-best-tool-to-automate-your-dependency-updates)
- [renovatebot/renovate on GitHub](https://github.com/renovatebot/renovate)
- [anchore/syft on GitHub](https://github.com/anchore/syft)
- [CycloneDX/cyclonedx-python on GitHub](https://github.com/CycloneDX/cyclonedx-python)
- [CycloneDX/cyclonedx-node-npm on GitHub](https://github.com/CycloneDX/cyclonedx-node-npm)
- [pip-licenses on PyPI](https://pypi.org/project/pip-licenses/)
- [pilosus/pip-license-checker on GitHub](https://github.com/pilosus/pip-license-checker)
- [qdhenry/Claude-Command-Suite on GitHub](https://github.com/qdhenry/Claude-Command-Suite)
- [wshobson/commands on GitHub](https://github.com/wshobson/commands)
- [npm audit documentation](https://www.nodejs-security.com/blog/how-to-use-npm-audit)
- [Top Open Source Dependency Scanners 2025 (Aikido)](https://www.aikido.dev/blog/top-open-source-dependency-scanners)
- [Best SBOM Tools 2025 (Kusari)](https://www.kusari.dev/blog/best-sbom-tools-2025)
