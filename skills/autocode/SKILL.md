---
name: autocode
description: "Run the full autonomous coding pipeline — brainstorm → PRD → plan → execute → verify → finish — with Telegram notifications and quality gates at every stage."
disable-model-invocation: true
metadata:
  version: 1.0.0
  category: workflow
  tags: [automation, pipeline, coding, code-factory]
  updated: 2026-03-08
---

# Autocode — Full Autonomous Coding Pipeline

## Overview

Orchestrate the complete agent-driven development pipeline from idea to merged code. This skill chains all stages in order, enforces hard gates between them, and optionally sends Telegram notifications at stage transitions.

<HARD-GATE>
Do NOT skip any stage. Do NOT proceed to the next stage until the current stage's exit criteria are met. Every stage must produce its required artifact before the gate opens.
</HARD-GATE>

## Checklist

You MUST create a task for each of these items and complete them in order:

1. **Initialize pipeline** — detect project, set up Telegram, create progress.txt
2. **Stage 0.5: Roadmap** (conditional) — invoke `autonomous-coding-toolkit:roadmap`, decompose multi-feature epic
3. **Stage 1: Brainstorm** — invoke `autonomous-coding-toolkit:brainstorming`, produce approved design
4. **Stage 1.5: Research** — invoke `autonomous-coding-toolkit:research`, investigate unknowns, produce research artifacts
5. **Stage 2: PRD** — generate `tasks/prd.json` with machine-verifiable acceptance criteria
6. **Stage 3: Plan** — invoke `autonomous-coding-toolkit:writing-plans`, produce batch plan
7. **Stage 4: Execute** — run batches with quality gates, update PRD and progress.txt
8. **Stage 5: Verify** — invoke `autonomous-coding-toolkit:verification-before-completion`, all PRD criteria pass
9. **Stage 6: Finish** — invoke `autonomous-coding-toolkit:finishing-a-development-branch`, merge/PR/keep/discard

## Arguments

The user provides a feature description, report path, or issue reference:

- Feature description: "Add user authentication with JWT"
- Report path: `reports/daily.md` — run `scripts/analyze-report.sh` first to extract top priority
- Issue: `#42` — fetch issue details via `gh issue view 42`

## Pipeline

### Stage 0: Initialize

1. Detect the project: read `CLAUDE.md`, identify test command, linter, language
2. Check for Telegram credentials:
   ```bash
   # Check if credentials exist (don't echo them)
   grep -q 'TELEGRAM_BOT_TOKEN' ~/.env 2>/dev/null && echo "telegram: enabled" || echo "telegram: disabled"
   ```
3. If input is a report path, analyze it first:
   ```bash
   scripts/analyze-report.sh <report>
   ```
   Use the `#1 priority` from the analysis output as the feature description.
4. Create or read `progress.txt` — append pipeline start entry
5. Notify (if Telegram enabled):
   ```
   🏭 Autocode started: <feature summary>
   Project: <name>
   ```

**Exit criteria:** Feature description is clear, project context loaded, progress.txt initialized.

---

### Stage 0.5: Roadmap (conditional)

If the input describes multiple features (3+ distinct features, "roadmap" keyword, or an epic), invoke `autonomous-coding-toolkit:roadmap` to decompose it.

This stage produces:

- `tasks/roadmap.md` with dependency-ordered feature list
- Phase groupings with effort estimates
- User approval of feature ordering

**Skip condition:** Single-feature inputs skip directly to Stage 1. When in doubt, check: does the input contain multiple independent deliverables?

After roadmap approval, the pipeline loops through features in order — each feature runs Stages 1-6 independently.

**Exit criteria:** `tasks/roadmap.md` exists and user approves feature ordering.

**Telegram:** `✅ Stage 0.5 complete: Roadmap approved — <N> features, <M> phases`

---

### Stage 1: Brainstorm

Invoke `autonomous-coding-toolkit:brainstorming` with the feature description.

This stage produces:

- Approved design doc at `docs/plans/YYYY-MM-DD-<topic>-design.md`
- User approval of the design

**Exit criteria:** Design doc exists and user has approved it.

**Telegram:** `✅ Stage 1 complete: Design approved — <title>`

---

### Stage 1.5: Research (conditional)

After design approval, check if the feature involves technical unknowns, unfamiliar libraries, or integration with existing code. If so, invoke `autonomous-coding-toolkit:research`.

This stage produces:

- Research report at `tasks/research-<slug>.md`
- Machine-readable findings at `tasks/research-<slug>.json`
- Resolution of all blocking issues (or user override)

**Skip condition:** If the brainstorming phase resolved all technical questions and no unknowns remain, this stage can be skipped. When in doubt, run it — 30 minutes of research prevents hours of rework.

**Gate:** Run `scripts/research-gate.sh tasks/research-<slug>.json` — blocks if unresolved blocking issues exist. Use `--force` to override.

**Exit criteria:** Research artifacts exist, research gate passes (or user overrides).

**Telegram:** `✅ Stage 1.5 complete: Research done — <N> questions, <M> warnings`

---

### Stage 2: PRD Generation

After design approval (and research if conducted), generate `tasks/prd.json` using the `/create-prd` format:

- 8-15 granular tasks with machine-verifiable acceptance criteria
- Every acceptance criterion is a shell command (exit 0 = pass)
- Separate investigation tasks from implementation tasks
- Order by dependency
- Save both `tasks/prd.json` and `tasks/prd-<feature>.md`

After generating, ask the user: **"How would you improve these acceptance criteria?"** — minimum 1 round of refinement.

**Exit criteria:** `tasks/prd.json` exists, all criteria are shell commands, user approves.

**Telegram:** `✅ Stage 2 complete: PRD generated — <N> tasks`

---

### Stage 3: Write Plan

Invoke `autonomous-coding-toolkit:writing-plans` to create the implementation plan.

Enhance the plan with:

- A `## Quality Gates` section listing project-specific checks (auto-detect: `pytest`, `npm test`, `npm run lint`, `make test`, or `scripts/quality-gate.sh`)
- Cross-references to `tasks/prd.json` task IDs in plan steps
- `progress.txt` initialization as the first plan step
- Plans with 3+ batches MUST include a final "Integration Wiring" batch

**Exit criteria:** Plan file exists at `docs/plans/YYYY-MM-DD-<topic>.md`, user approves.

**Telegram:** `✅ Stage 3 complete: Plan written — <N> batches, <M> tasks`

---

### Stage 4: Execute

Ask the user which execution mode to use:

| Mode           | Best For                           | How                                                     |
| -------------- | ---------------------------------- | ------------------------------------------------------- |
| **In-session** | Small plans (1-3 batches)          | Execute here with TDD                                   |
| **Subagent**   | 5-15 independent tasks             | `autonomous-coding-toolkit:subagent-driven-development` |
| **Headless**   | 4+ batches, unattended             | `scripts/run-plan.sh <plan> --notify`                   |
| **Ralph loop** | Iterate until done                 | `/ralph-loop` with completion promise                   |
| **MAB**        | Learn best strategy per batch type | `scripts/run-plan.sh <plan> --mab --notify`             |

#### For in-session and subagent modes:

Between EVERY batch:

1. Run quality gate:
   ```bash
   scripts/quality-gate.sh --project-root .
   ```
   If not available, run the project's test command directly.
2. Update `tasks/prd.json` — set `"passes": true` for criteria that now pass
3. Append batch summary to `progress.txt`
4. Notify per batch:
   ```
   ✅ Batch <N>/<total>: <title>
   Tests: <count> (↑<delta>) | <duration>
   ```
5. If quality gate fails: fix before proceeding. Notify:
   ```
   ❌ Batch <N>/<total> failed: <title>
   Issue: <error summary>
   ```

#### For headless mode:

Launch via bash:

```bash
scripts/run-plan.sh <plan-file> --notify --on-failure retry --max-retries 3 --verify
```

Report the command to the user and let them decide to run it.

**Exit criteria:** All batches complete, all quality gates pass, test count monotonically increased.

**Telegram:** `✅ Stage 4 complete: All <N> batches executed — <total tests> tests passing`

---

### Stage 5: Verify

Invoke `autonomous-coding-toolkit:verification-before-completion`.

Additionally:

1. Run ALL acceptance criteria from `tasks/prd.json`:
   ```bash
   # For each criterion in prd.json
   eval "<criterion_command>" && echo "PASS" || echo "FAIL"
   ```
2. Every task must have `"passes": true`
3. Run lesson scanner against changed files
4. For plans with 3+ batches: run A/B verification (see `ab-verification.md`)

<HARD-GATE>
Never claim completion if ANY PRD criterion fails. Fix failures and re-verify.
</HARD-GATE>

**Exit criteria:** All PRD criteria pass, verification evidence collected, no lesson violations.

**Telegram:** `✅ Stage 5 complete: All <N> acceptance criteria passing`

---

### Stage 6: Finish

Invoke `autonomous-coding-toolkit:finishing-a-development-branch`.

After the user's choice (merge/PR/keep/discard):

**Telegram:**

- Merge: `🎉 Autocode complete: <feature> merged to <branch>`
- PR: `🎉 Autocode complete: <feature> — PR #<N> created`
- Keep: `📌 Autocode paused: <feature> on branch <name>`
- Discard: `🗑️ Autocode cancelled: <feature> discarded`

---

## Telegram Notifications

Notifications are sent via the Telegram Bot API using credentials from `~/.env`. They are **optional** — the pipeline works without them.

To send a notification from within Claude Code:

```bash
TELEGRAM_BOT_TOKEN=$(grep 'TELEGRAM_BOT_TOKEN' ~/.env | cut -d= -f2-)
TELEGRAM_CHAT_ID=$(grep 'TELEGRAM_CHAT_ID' ~/.env | cut -d= -f2-)
curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="$TELEGRAM_CHAT_ID" \
  -d text="<message>" \
  -d parse_mode="Markdown" \
  --max-time 10 > /dev/null 2>&1
```

If credentials are missing, skip notifications silently — never block the pipeline on notification failure.

## Rules

- **Never skip a stage.** The design must be approved before PRD generation.
- **Every acceptance criterion is a shell command.** No vague criteria.
- **Quality gates run between EVERY batch**, not just at the end.
- **Progress.txt is append-only** during execution — never truncate it.
- **Test counts only go up.** If tests decrease, something broke — fix it.
- **Notification failures are non-fatal.** Log and continue.
- **Fresh context matters.** If past batch 5 in-session, suggest headless mode for remaining batches.

## Common Mistakes

**Skipping brainstorming for "simple" features**

- Problem: Unexamined assumptions cause rework
- Fix: Every feature goes through Stage 1, even one-line changes

**Generating vague PRD criteria**

- Problem: "Works correctly" is not verifiable
- Fix: Every criterion is a shell command. `curl -s localhost:8080/api/health | jq -e '.status == "ok"'`

**Proceeding past failed quality gates**

- Problem: Cascading failures compound in later batches
- Fix: Fix the gate failure BEFORE moving to the next batch

**Not updating progress.txt**

- Problem: Next batch (fresh context) loses discoveries
- Fix: Append batch summary after every batch, before moving on

## Integration

**Called by:** User via `/autocode <feature>` or Skill tool
**Calls:** brainstorming, writing-plans, executing-plans/subagent-driven-development, verification-before-completion, finishing-a-development-branch
**State files:** `progress.txt`, `tasks/prd.json`, `.run-plan-state.json`
**Scripts:** `scripts/run-plan.sh`, `scripts/quality-gate.sh`, `scripts/analyze-report.sh`
