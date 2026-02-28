# Research: Improving Existing Claude Code Agents

**Date:** 2026-02-23
**Status:** Complete
**Scope:** ~/.claude/agents/ — 8 existing agents

---

## BLUF

The 8 existing agents range from production-quality (lesson-scanner, counter) to underspecified (security-reviewer, doc-updater). Priority improvements fall into four categories: (1) add `model` fields to 5 agents that inherit unnecessarily, (2) add `memory` fields to 3 agents that would benefit from cross-session learning, (3) tighten tool lists on 4 agents that are over-permissioned, (4) add explicit hallucination guards to the 2 audit agents.

---

## Sources

- [wshobson/agents](https://github.com/wshobson/agents) — 112-agent production system, plugin architecture, progressive disclosure skills
- [VoltAgent/awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) — 127+ agent community collection
- [0xfurai/claude-code-subagents](https://github.com/0xfurai/claude-code-subagents) — 100+ production-ready subagents
- [iannuttall/claude-agents](https://github.com/iannuttall/claude-agents) — custom agents collection
- [hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code) — curated skills/hooks/agents list
- [Claude Code Docs — Create custom subagents](https://code.claude.com/docs/en/sub-agents) — official frontmatter reference
- [PubNub — Best Practices for Claude Code Sub-Agents](https://www.pubnub.com/blog/best-practices-for-claude-code-sub-agents/) — tool constraints, hooks, error handling
- [PubNub — From Prompts to Pipelines](https://www.pubnub.com/blog/best-practices-claude-code-subagents-part-two-from-prompts-to-pipelines/) — agent chain patterns, artifact structure
- [Claude Docs — Reduce Hallucinations](https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) — hallucination prevention
- [Adaline Labs — Ship Reliably with Claude Code](https://labs.adaline.ai/p/how-to-ship-reliably-with-claude-code) — governance patterns

---

## Key Findings from External Research

### Frontmatter Capabilities Most Agents Are Not Using

From the official docs, these frontmatter fields exist and none of the current agents use them fully:

| Field | What it does | Agents missing it |
|-------|-------------|-------------------|
| `model` | Route to right model tier | security-reviewer, infra-auditor, doc-updater, notion-researcher, notion-writer |
| `memory` | Persistent cross-session learning | security-reviewer, lesson-scanner, infra-auditor |
| `maxTurns` | Hard stop against runaway execution | all agents |
| `isolation: worktree` | Isolated git context for write agents | doc-updater |
| `hooks` | Pre/post tool validation | infra-auditor, notion-writer |
| `permissionMode` | Default is overly permissive for read-only agents | security-reviewer, infra-auditor, counter, counter-daily |

### Tool Constraint Anti-Pattern: Omission = Full Inheritance

From PubNub research: "If you omit `tools`, you're implicitly granting access to all available tools." All 8 agents explicitly list tools, which is correct. However, several include write-capable tools (Edit, Write, Bash) when they only need read access.

- `counter.md` and `counter-daily.md` have `tools: Read, Grep, Glob` — correct, no write needed
- `security-reviewer.md` includes `Bash` — risky if used for active exploitation testing
- `infra-auditor.md` includes `Bash` — necessary for system checks, but should add `permissionMode: dontAsk` for writes

### Hallucination Prevention Patterns

From Anthropic's official docs on reducing hallucinations:
1. **Ground assertions in tool output** — agents should be required to cite specific grep/read results before any finding
2. **Explicit "do not report what grep + read does not confirm"** instruction — lesson-scanner has this; security-reviewer and infra-auditor do not
3. **Uncertainty declarations** — agents should say "I could not verify X" rather than inferring

### Agent Chain Integration Patterns

From PubNub Part 2:
- Structured handoff artifacts: active-plan.md, implementation-summary.md, qa-summary.md
- Each agent returns a clean summary to the orchestrator, not raw logs
- Hook-based governance: PreToolUse for validation, PostToolUse for verification
- Plan → Execute → Verify pipeline as the canonical sequence

### Model Selection Best Practice

From official docs and PubNub:
- Haiku: mechanical tasks, read-only searches, daily lightweight checks
- Sonnet: balanced analysis, multi-file operations
- Opus: complex reasoning, adversarial review, architecture critique

Current agents: counter correctly uses `model: opus`. counter-daily correctly uses `model: sonnet`. The other 6 all inherit from the parent conversation, which means they will run at whatever model the user happens to be using — wasteful for lightweight agents, underspecced for analysis agents.

### Persistent Memory Pattern

From official docs: `memory: user` gives agents a `~/.claude/agent-memory/<name>/` directory that persists across sessions. The agent's system prompt automatically includes the first 200 lines of MEMORY.md.

Agents that would benefit most from memory:
- **lesson-scanner**: could accumulate false-positive patterns per-project, avoid rescanning clean files
- **security-reviewer**: could remember known-safe patterns and previously flagged issues
- **infra-auditor**: could track baseline service states and flag deviations vs. absolute thresholds

---

## Per-Agent Assessment and Improvements

### 1. security-reviewer.md

**Current state:** Minimal (35 lines). Covers 4 vulnerability categories. Output format exists but is implicit. No hallucination guard. Web-focused (SQL injection, XSS) — misses Python/bash attack surfaces.

**Gap analysis:**
- No explicit "only report what the tools confirm" guardrail — will hallucinate findings on code it hasn't read
- Missing attack categories for Python/shell scripts: deserialization, subprocess injection, pickle loading, hardcoded secrets in environment variable fallbacks
- No `model` field (should be `sonnet`)
- No `memory` field — can't accumulate project-specific baseline
- Bash tool included but no guard against running exploits — should be `permissionMode: plan` or `dontAsk`
- Missing cryptography category: weak algorithms (MD5, SHA1), hardcoded salts, insecure random
- Output format has no "CLEAN" affirmation — leaves ambiguity about unreviewed files

**Recommended improvements:**

```markdown
---
name: security-reviewer
description: Reviews code for security vulnerabilities and sensitive data exposure. Use proactively after any code changes that touch authentication, data handling, file I/O, subprocess calls, or network requests.
tools: Read, Grep, Glob
model: sonnet
memory: project
permissionMode: plan
---
```

Changes:
1. Remove `Bash` — not needed for read-only review; eliminates risk of active exploitation
2. Add `model: sonnet` — analysis task, not opus-level reasoning
3. Add `memory: project` — accumulate known-safe patterns and previously reviewed baselines
4. Add `permissionMode: plan` — read-only mode, no writes
5. Expand vulnerability categories:
   - Add Python-specific: `pickle.loads()`, `eval()`, `exec()`, `subprocess` with `shell=True`
   - Add cryptography: `hashlib.md5`, `hashlib.sha1`, `random.random()` in security context, hardcoded salts
   - Add dependency chain: check `requirements.txt`, `package.json`, `Pipfile.lock` for known CVEs via `safety check` in bash (after re-adding Bash with hook guard)
6. Add explicit hallucination guard: "Only report findings grounded in specific file:line evidence from Read/Grep output. If a grep returns no matches, record the category as CLEAN — do not infer."
7. Add structured `CLEAN` section to output format

### 2. infra-auditor.md

**Current state:** Well-specified (77 lines). Clear check categories, concrete commands, good report format. Strong baseline.

**Gap analysis:**
- No `model` field (should be `haiku` — mechanical checks, not reasoning)
- No `maxTurns` — could loop indefinitely if a service check hangs
- Missing checks: memory slice caps (the systemd-oomd and user-1000 slice are defined in CLAUDE.md), ollama-queue service, open-webui health
- `systemctl --user is-active` for 6 services — correct, but missing the timer units (21 timers)
- Sync freshness check uses `stat -c '%Y'` (epoch) but compares to nothing — needs `$(date +%s)` math
- No hook to validate bash commands before execution (adds risk if agent hallucinates a destructive command)
- Missing: `journalctl --user -u <service> --since "1 hour ago" --no-pager` for recent errors on unhealthy services

**Recommended improvements:**

```yaml
model: haiku
maxTurns: 30
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "~/.claude/hooks/validate-readonly-bash.sh"
```

Specific content additions:
1. Add timer audit: `systemctl --user list-timers --no-pager` — check that all 21 timers are active
2. Fix sync freshness math: `NOW=$(date +%s); SYNC=$(stat -c '%Y' file); echo $((NOW - SYNC))` seconds
3. Add ollama-queue service check: `curl -s http://127.0.0.1:7683/health`
4. Add memory slice check: `systemctl show user-1000.slice --property=MemoryHigh`
5. Add hallucination guard: "Only report the output of commands you actually executed. Do not infer service health without running the check."
6. Add journal check for any unhealthy service before escalating to CRITICAL

### 3. doc-updater.md

**Current state:** Well-structured (40 lines). Context hierarchy table is excellent. CLAUDE.md chain enforcement is the right mental model.

**Gap analysis:**
- No `model` field (should be `sonnet` — needs to reason about content placement)
- No `isolation: worktree` — doc writes could corrupt staging area (Lesson #44 parallel agent concern)
- `git diff HEAD~1` only looks at last commit — misses uncommitted changes; should use `git diff HEAD` and `git status --short` together
- No check for MEMORY.md line count (stated in the rules but no scan instruction)
- Missing: validate that CLAUDE.md files don't contain hardcoded secrets (should grep for IP addresses, tokens)
- No output format — the agent makes changes but returns no structured summary of what was changed and why
- Write tool is included — needs explicit guard against writing to CLAUDE.md files it hasn't read first (lesson #file-editing from CLAUDE.md)

**Recommended improvements:**

```yaml
model: sonnet
isolation: worktree
```

Content additions:
1. Add explicit scan sequence:
   - Step 0: `git status --short && git diff HEAD --name-only` (catch both staged and unstaged)
   - Add MEMORY.md line count check: `wc -l ~/.claude/projects/.../memory/MEMORY.md`
2. Add output format:
   ```
   ## Doc Update Summary
   Files reviewed: [list]
   Files modified: [list with reason]
   Duplication removed: [what and where]
   No-op: [what needed no change and why]
   ```
3. Add security check: before writing, grep new content for IP addresses, tokens, credentials
4. Add explicit "read before write" rule — must Read the target file before Edit/Write

### 4. lesson-scanner.md

**Current state:** Excellent (294 lines). Most mature agent in the set. Structured scan groups, explicit patterns, hallucination guard already present, clean report format. This is the reference implementation.

**Gap analysis:**
- Description says "53 lessons" — now 66 lessons (stale count)
- No `model` field (should be `sonnet` — pattern matching and analysis, not Opus-level)
- No `memory: project` — could cache "clean file" hashes to skip unchanged files on repeat runs
- Scan Group coverage gaps vs. current lesson set:
  - Missing Lessons #60-66 (research-derived, added 2026-02-21): plan quality, spec compliance, positive instructions, lesson scope, context placement
  - Missing Lesson #51: `.venv/bin/pip` vs `.venv/bin/python -m pip` (hookify warns but scanner should flag too)
  - Missing Lesson #50: plan assertion math (if scanner runs on docs/plans/*.md)
  - Missing Lesson #26: unit boundary verification
- Scan Group 4a (duplicate function names) has a false-positive threshold of 3 files — should be configurable

**Recommended improvements:**

```yaml
model: sonnet
memory: project
```

Content additions:
1. Update description count: "66 lessons" (from 53)
2. Add Scan Group 7: Plan Quality (Lessons #60-66):
   - Scan `docs/plans/*.md` for missing hypothesis statements, missing acceptance criteria, missing success metrics
   - Pattern: check for "hypothesis:" or "we believe" keywords — absence is a flag
   - Pattern: check for "acceptance criteria" section — absence is Should-Fix
3. Add Scan 3f: `.venv/bin/pip` usage (Lesson #51):
   ```
   pattern: \.venv/bin/pip\b
   glob: **/*.{sh,md,py}
   ```
   Flag as Should-Fix with fix: use `.venv/bin/python -m pip`
4. Add memory instruction: "After each scan, write a one-line entry to MEMORY.md noting the project path, timestamp, and blocker count. On repeat scans, check memory first — if a file has not changed since last scan and had no blockers, skip it."

### 5. counter.md

**Current state:** Exceptional (466 lines). Most sophisticated agent in the set. Psychological grounding, four lenses, lean gate, wildcard, human contact gate, severity system, critical rules. This is a complete system.

**Gap analysis:**
- No `maxTurns` — a review could spiral into exhaustive analysis; 20 turns is sufficient for any review
- The `Discovered Patterns` section at the bottom is the right pattern but has no reminder to check it — the agent could skip it on automatic runs
- No reference to Lessons #60-66 in the Bias Detection section — "Lesson regression" check (Lens 2) should include the research-derived clusters E and F
- `~/.claude/counter-humans.md` is referenced but if this file doesn't exist the human contact gate silently fails
- Missing: the agent has no instruction to check if it's being invoked recursively (counter reviewing a counter output creates echo chamber)

**Recommended improvements:**

1. Add `maxTurns: 20` to frontmatter
2. Add Cluster E and F to the Lesson Regression check in Lens 2:
   ```
   "Lesson regression — mental grep against all 6 clusters:
   A (silent failures), B (integration boundaries), C (cold-start),
   D (specification drift), E (context & retrieval — info buried or misscoped),
   F (planning & control flow — wrong decomposition contaminates downstream)"
   ```
3. Add check at top of Discovered Patterns section: "Before reviewing, scan Discovered Patterns for any pattern matching the input type."
4. Add guard: "If the input being reviewed is itself a Counter output or review of a review, flag this to the user before proceeding — adversarial review of adversarial review creates false certainty."

### 6. counter-daily.md

**Current state:** Well-calibrated (66 lines). Tight scope, correct model, no padding.

**Gap analysis:**
- No `maxTurns` — should be 5 (three questions, acknowledgment, done)
- Missing question pool entry for "Lesson regression" gap — the daily check could include "Did you repeat a known failure pattern today?" as an optional question
- The defaults fire when no context is provided — but if the user provides partial context, question selection logic is vague ("pick the three most relevant")
- No output structure at all — questions are unformatted, which is correct for this agent, but there's no instruction about follow-up behavior if Justin responds

**Recommended improvements:**

1. Add `maxTurns: 5`
2. Add one question to each pool as options:
   - Collaboration: "Did you make any decision today based on a lesson you've documented but ignored anyway?"
   - Focus: "What would have changed if you'd checked Lessons SUMMARY.md before starting today's main task?"
3. Add behavior rule: "If Justin responds to the questions, acknowledge once and stop. Do not analyze the response. Do not follow up with more questions. That's the full counter's job."

### 7. notion-researcher.md

**Current state:** Well-structured (77 lines). Search strategy hierarchy is excellent. Content domain shortcuts are high-value. Synthesis rules are correct.

**Gap analysis:**
- No `model` field (should be `sonnet` — cross-database synthesis, not mechanical lookup)
- `tools: Read, Grep, Glob, Bash` — Bash is needed for `notion-vector-search` CLI, correct
- No `maxTurns` — large Notion workspaces could cause runaway exploration; limit to 40 turns
- Staleness check instruction is there but weak — "if freshness matters" is vague; should always check if data is >12 hours old
- No citation format standardization — the output rule says "cite sources" but doesn't specify format; the main session can't parse inconsistent citations
- Missing: the agent should check `~/Documents/notion/CLAUDE.md` exists before starting — if Notion sync has never run, the file may not exist
- Missing: if `notion-vector-search` returns 0 results, the agent has no fallback instruction (will hallucinate or stop)

**Recommended improvements:**

```yaml
model: sonnet
maxTurns: 40
```

Content additions:
1. Standardize citation format:
   ```
   Source: [Database/Page Name] | ID: {uuid} | Updated: {date}
   ```
2. Add vector search fallback: "If `notion-vector-search` returns 0 results, fall back to Grep with decomposed keyword terms before concluding the topic is not in Notion."
3. Strengthen staleness check: always run `stat` on sync metadata at start and include age in output — do not wait for "freshness matters"
4. Add guard: "Check that `~/Documents/notion/CLAUDE.md` exists before searching. If it doesn't exist, report: 'Notion local replica not found — run notion-sync first.'"

### 8. notion-writer.md

**Current state:** Functional (115 lines). Complete API reference, good property formats, batch operation example, SQLite sync instruction.

**Gap analysis:**
- No `model` field (should be `haiku` — mechanical API calls, not reasoning)
- No `maxTurns` — should be 20 to prevent runaway batch operations
- Rate limit handling is documented but has no instruction for what to do after hitting rate limit beyond "wait and retry" — should include exponential backoff
- No input validation instruction — if called with a missing database ID, will attempt API call and get a cryptic 404
- The SQLite sync step is noted as "when creating pages from capture bot" — but the agent has no way to know which origin triggered it; it should always offer to sync
- No rollback instruction — if a batch create fails midway, the agent has no guidance on how to identify which pages were created vs. not
- Missing: the agent should verify `NOTION_API_KEY` is set before first API call, not discover it's missing on first 401

**Recommended improvements:**

```yaml
model: haiku
maxTurns: 20
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "~/.claude/hooks/validate-api-key.sh NOTION_API_KEY"
```

Content additions:
1. Add pre-flight check: "Before any API call, verify `NOTION_API_KEY` is set: `bash -c 'source ~/.env && [ -n \"$NOTION_API_KEY\" ] && echo OK || echo MISSING'`"
2. Add input validation: "Before calling any API with a database ID, check that the ID matches UUID format (8-4-4-4-12 hex). If not, stop and report the malformed ID."
3. Add exponential backoff for 429: `sleep $((retry_after + 1))`, double delay on second retry
4. Add batch operation tracking: maintain a local list of successfully created page IDs during batch operations; if an error occurs, report "Created N of M pages: [list of IDs]"
5. Add SQLite sync offer: always end with "Run `notion-sync --page PAGE_ID` to refresh local replica for each created page?"

---

## Cross-Cutting Patterns

### Pattern 1: Hallucination Guard Template

Every audit/review agent (security-reviewer, infra-auditor, lesson-scanner) should include this as its final instruction:

```
## Anti-Hallucination Rules

- Report ONLY what Grep/Read/Bash output directly confirms.
- If a scan group returns no grep matches, record it as CLEAN — do not infer vulnerabilities.
- If you are uncertain about a finding, read more context before flagging — do not flag based on pattern proximity alone.
- If a command fails or returns no output, report "Could not verify: [check name]" rather than assuming pass or fail.
```

lesson-scanner already has a version of this. security-reviewer and infra-auditor need it added.

### Pattern 2: Model Tier Alignment

Current state vs. correct assignment:

| Agent | Current | Should Be | Reason |
|-------|---------|-----------|--------|
| security-reviewer | inherit | sonnet | Multi-file analysis |
| infra-auditor | inherit | haiku | Mechanical checks |
| doc-updater | inherit | sonnet | Content reasoning |
| lesson-scanner | inherit | sonnet | Pattern analysis |
| counter | opus | opus | Correct — adversarial reasoning |
| counter-daily | sonnet | sonnet | Correct — lightweight |
| notion-researcher | inherit | sonnet | Cross-database synthesis |
| notion-writer | inherit | haiku | Mechanical API calls |

### Pattern 3: maxTurns as Safety Net

None of the current agents set `maxTurns`. Per official docs, this is a hard stop on runaway execution. Recommended values:

| Agent | maxTurns | Reason |
|-------|----------|--------|
| security-reviewer | 50 | May scan many files |
| infra-auditor | 30 | ~20 discrete checks |
| doc-updater | 20 | Few files to read+write |
| lesson-scanner | 80 | 6 scan groups × many files |
| counter | 20 | Review, not analysis marathon |
| counter-daily | 5 | 3 questions only |
| notion-researcher | 40 | May explore many pages |
| notion-writer | 20 | Bounded by batch size |

### Pattern 4: Memory for Audit Agents

Three agents would benefit most from `memory: project`:

- **lesson-scanner**: Cache scan results per file hash; skip unchanged clean files on repeat runs. This transforms it from O(project_size) to O(changed_files) on every run.
- **security-reviewer**: Store baseline of known-safe patterns (e.g., "this project uses parameterized queries throughout — SQL injection is mitigated at the ORM layer"). Avoid re-flagging architecturally sound patterns.
- **infra-auditor**: Store service baseline state. Flag deviations from baseline rather than absolute thresholds. Reduces false positives on expected service restarts.

### Pattern 5: Description Quality

The `description` field is how Claude decides when to delegate. Current descriptions vary in specificity:

**Weak** (won't trigger delegation reliably):
- `security-reviewer`: "Reviews code for security vulnerabilities and sensitive data exposure" — no trigger phrase
- `doc-updater`: "Reviews recent changes and updates documentation" — no trigger phrase

**Strong** (explicit invocation triggers):
- `lesson-scanner`: "Scans codebase for anti-patterns... Dispatched via /audit lessons against any Python/JS/TS project root" — explicit dispatch instruction
- `notion-researcher`: "Use this agent when answering questions that require reading multiple Notion files..." — clear use-case examples

All agents should include: "Use proactively when..." or "Dispatch when..." with specific trigger conditions.

### Pattern 6: Tool Minimization

Per PubNub: "Be intentional" about tools. Current over-permissions:

- `security-reviewer` has `Bash` — remove it; read-only review needs only Read/Grep/Glob
- `infra-auditor` has `Bash` — keep it (needed for system checks), but add PreToolUse hook to validate no destructive commands
- `doc-updater` has `Edit, Write, Bash` — all justified, but add read-before-write rule

---

## Priority-Ordered Action List

### P0 — Correctness (prevents wrong output)

1. **Add hallucination guards to security-reviewer and infra-auditor** — these agents report findings that drive action; false findings are costly
2. **Fix infra-auditor sync freshness math** — current `stat -c '%Y'` comparison is broken without `$(date +%s)` delta math
3. **Remove Bash from security-reviewer** — read-only review should not have shell execution; eliminates active-exploitation risk
4. **Update lesson-scanner description count** — "53 lessons" is stale; now 66

### P1 — Quality (prevents waste or confusion)

5. **Add `model` fields to all 6 agents missing them** — prevents sonnet-scale tasks routing to haiku or opus-scale tasks routing to haiku by accident
6. **Add `maxTurns` to all agents** — prevents runaway execution; values above
7. **Add explicit trigger phrases to security-reviewer and doc-updater descriptions** — delegation won't activate reliably without them
8. **Fix doc-updater git diff command** — `HEAD~1` misses uncommitted changes; use `git status --short && git diff HEAD`

### P2 — Capability (adds meaningful new features)

9. **Add `memory: project` to lesson-scanner** — caching clean-file results transforms repeat scan performance
10. **Add Scan Group 7 (Plan Quality, Lessons #60-66) to lesson-scanner** — research-derived lessons are not currently scanned
11. **Add Scan 3f (`.venv/bin/pip`, Lesson #51) to lesson-scanner** — hookify warns but scanner should also flag
12. **Add Clusters E and F to counter Bias Detection (Lens 2)** — lesson regression check is incomplete without them
13. **Add notion-researcher vector search fallback** — zero-result behavior is undefined
14. **Add notion-writer pre-flight API key check** — currently discovers missing key on first 401

### P3 — Polish (reduces friction)

15. **Add structured output format to doc-updater** — currently makes changes but returns no summary
16. **Add counter-daily follow-up behavior rule** — "acknowledge once and stop" prevents it from morphing into a full counter session
17. **Add notion-writer batch operation tracking** — partial failure currently leaves ambiguous state
18. **Add `memory: project` to security-reviewer** — baseline known-safe patterns across sessions
19. **Add `isolation: worktree` to doc-updater** — protects staging area during CLAUDE.md writes
20. **Add counter `maxTurns: 20`** — prevents review sessions from becoming analysis marathons

---

## Agent Chain Integration Opportunities

Three natural agent chains exist that are not currently wired:

### Chain 1: Code Change Pipeline
```
[code change committed]
  → security-reviewer (read-only scan, report findings)
  → lesson-scanner (pattern audit, report violations)
  → doc-updater (update CLAUDE.md + README if needed)
```
Currently these run independently. Wiring via a slash command or hook would create a single `/post-commit-audit` that runs all three.

### Chain 2: Notion Research → Write
```
[user asks a Notion question]
  → notion-researcher (explore, synthesize, return citations)
  → notion-writer (create capture page with findings if requested)
```
Currently the user manually switches between agents. The researcher's output format should be designed to be directly consumable by the writer.

### Chain 3: Counter → doc-updater
```
[counter reviews a plan and finds issues]
  → counter returns critique with specific gaps
  → doc-updater updates the plan doc with flagged items
```
This requires counter's output format to include actionable file:line references compatible with doc-updater's input format — a structural change to counter's output format.

---

## Appendix: Official Frontmatter Reference (as of 2026-02-23)

From [Claude Code Docs](https://code.claude.com/docs/en/sub-agents):

| Field | Required | Default | Notes |
|-------|----------|---------|-------|
| `name` | Yes | — | Lowercase + hyphens |
| `description` | Yes | — | Delegation trigger text |
| `tools` | No | All inherited | Omitting = full inheritance (dangerous) |
| `disallowedTools` | No | — | Blocklist from inherited set |
| `model` | No | inherit | sonnet/opus/haiku/inherit |
| `permissionMode` | No | default | default/acceptEdits/dontAsk/bypassPermissions/plan |
| `maxTurns` | No | unlimited | Hard stop on agentic turns |
| `skills` | No | — | Inject skill content at startup |
| `mcpServers` | No | — | MCP servers available to subagent |
| `hooks` | No | — | Lifecycle hooks scoped to subagent |
| `memory` | No | — | user/project/local |
| `background` | No | false | Always run as background task |
| `isolation` | No | — | worktree = isolated git context |
