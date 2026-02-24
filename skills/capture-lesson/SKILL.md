---
name: capture-lesson
description: Use when capturing a lesson learned from a bug, audit finding, or session insight — enforces template, validation, and commit workflow
---

# Capture Lesson

## Overview

Structured process for writing new lessons that enforces the FRAMEWORK.md template, OIL tier rules, category validation, and all three validation scripts before committing. Prevents manual shortcutting that skips recurrence analysis and sustain checks.

## When to Use

- After discovering a bug, audit finding, or session insight worth capturing
- When `/capture-lesson` is invoked
- After a debugging session reveals a repeatable anti-pattern
- When a code review or counter session surfaces a new failure mode

## Process (follow this order exactly)

### Step 1: Gather Context

Ask the user:
1. **What happened?** — factual description with error messages, data contradictions, numbers
2. **Which files were involved?** — specific paths
3. **Which cluster does this resemble?** — A (Silent Failures), B (Integration Boundary), C (Cold-Start), D (Specification Drift), E (Context & Retrieval), F (Planning & Control Flow), or standalone

### Step 2: Draft the Lesson File

Create `~/Documents/docs/lessons/YYYY-MM-DD-short-description.md` using the exact FRAMEWORK.md template:

```markdown
# Lesson: [Short Title]

**Date:** YYYY-MM-DD
**System:** [project name]
**Tier:** observation | insight | lesson
**Category:** [from enum below]
**Keywords:** [comma-separated for grep retrieval]
**Files:** `path/to/file1`, `path/to/file2`

## Observation (What Happened)
[Factual description. Include numbers, error messages, data contradictions.]

## Analysis (Root Cause — 5 Whys)
**Why #1:** [surface cause]
**Why #2:** [why that happened]
**Why #3:** [root cause — deepest controllable cause]

## Corrective Actions
| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | [specific action] | proposed | [who] | — |

## Ripple Effects
[What other systems/pipelines does this touch?]

## Sustain Plan
- [ ] 7-day check: [what to verify]
- [ ] 30-day check: [confirm no recurrence]
- [ ] Contingency: [if corrective action doesn't hold]

## Key Takeaway
[One sentence. The thing you'd tell someone in 10 seconds.]
```

### Step 2.5: Infer Scope Tags

Determine the lesson's scope by analyzing its content:

1. **Check domain signals:** Does the lesson reference specific systems?
   - Home Assistant, HA entities, MQTT, Frigate → `domain:ha-aria`
   - Telegram bot, polling, getUpdates → `domain:telegram`
   - Notion API, sync, replica → `domain:notion`
   - Ollama, model loading, queue → `domain:ollama`

2. **Check framework signals:** Does it reference specific tooling?
   - systemd, journalctl, timers → `framework:systemd`
   - pytest, fixtures, conftest → `framework:pytest`
   - Preact, JSX, `h()` → `framework:preact`

3. **Check language signals:** What language(s) does it apply to?
   - Python-only patterns → `language:python`
   - Bash/shell patterns → `language:bash`
   - JavaScript/TypeScript → `language:javascript`

4. **Default to `universal`** if the lesson describes a general principle (error handling, testing, architecture) not specific to any domain/language.

5. **Propose to user:** Present inferred scope tags and ask for confirmation before writing. Example: "Inferred scope: `[domain:ha-aria, language:python]` — does this look right?"

Add the `scope:` field to the YAML frontmatter after `languages:`:
```yaml
scope: [domain:ha-aria, language:python]
```

Reference: `~/Documents/docs/lessons/TEMPLATE.md` § Scope (Project-Level Filtering) for the full tag vocabulary.

### Step 3: Validate Tier (HARD GATE)

Enforce OIL taxonomy rules:

| Tier | Requires | Status |
|------|----------|--------|
| `observation` | Raw facts only | `observed` |
| `insight` | Root cause identified via 5 Whys | `analyzed` |
| `lesson` | Corrective action proposed with owner + timeline | `proposed` |
| `lesson_learned` | Implementation proof + 30-day sustain evidence | `validated` |

**HARD GATE: Never assign `lesson_learned` to a new lesson.** A new lesson starts at `observation`, `insight`, or `lesson` depending on how far the analysis goes. Promotion to `lesson_learned` requires sustained evidence over time.

### Step 4: Validate Category

Category must be exactly one of:

| Category | Scope |
|----------|-------|
| `data-model` | Schema, inheritance, data flow |
| `registration` | Module loading, decorators, imports |
| `cold-start` | First-run, missing baselines |
| `integration` | Cross-service, shared state, API contracts |
| `deployment` | Service config, systemd, env vars |
| `monitoring` | Alerts, noise suppression, staleness |
| `ui` | Frontend, data display |
| `testing` | Coverage gaps, mock masking |
| `performance` | Resources, memory, scheduling |
| `security` | Auth, secrets, permissions |

If the lesson doesn't fit any category cleanly, pick the closest match and note the tension in Ripple Effects.

### Step 5: Update SUMMARY.md

Edit `~/Documents/docs/lessons/SUMMARY.md`:

1. **Add row** to the Quick Reference table with the next sequential number
2. **Update cluster membership** — add the lesson number to the relevant cluster's parenthetical list in the cluster section header
3. **Update the count** in the header line (e.g., "72 lessons" becomes "73 lessons")
4. **Update tier counts** in the Status & Maturity table

### Step 6: Run Validation Scripts

Run each script and address output before proceeding:

```bash
# Recurrence analysis — if alert triggers, answer the 4 questions before continuing
bash ~/Documents/scripts/lesson-class-check.sh ~/Documents/docs/lessons/YYYY-MM-DD-short-description.md

# Promotion candidates — informational, report to user
bash ~/Documents/scripts/lesson-promote-check.sh

# Overdue sustain items — informational, report to user
bash ~/Documents/scripts/lessons-sustain-check.sh
```

**If `lesson-class-check.sh` triggers a recurrence alert**, answer these 4 questions before proceeding:
1. Why didn't the existing cluster mitigations catch this?
2. Is this a new sub-pattern or a gap in existing mitigations?
3. Should a new mitigation be added to the cluster?
4. Should an existing mitigation be strengthened?

### Step 7: Commit

Stage and commit with the standard format:

```bash
git add ~/Documents/docs/lessons/YYYY-MM-DD-short-description.md ~/Documents/docs/lessons/SUMMARY.md
git commit -m "docs: add lesson #N — short description"
```

## Key References

| File | Purpose |
|------|---------|
| `~/Documents/docs/lessons/FRAMEWORK.md` | Template and OIL taxonomy |
| `~/Documents/docs/lessons/SUMMARY.md` | Lesson index (Quick Reference table + clusters) |
| `~/Documents/scripts/lesson-class-check.sh` | Cluster recurrence analysis |
| `~/Documents/scripts/lesson-promote-check.sh` | Hookify promotion candidates |
| `~/Documents/scripts/lessons-sustain-check.sh` | Overdue sustain items |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Assigning `lesson_learned` to a new lesson | Start at `observation`, `insight`, or `lesson` — promotion requires 30-day evidence |
| Skipping 5 Whys analysis | If tier is `insight` or higher, 5 Whys is required — at least 2-3 levels deep |
| Using a category not in the enum | Pick the closest match from the 10 valid categories |
| Forgetting to update SUMMARY.md counts | Always update: row count in header, tier counts in Status table, cluster membership lists |
| Skipping `lesson-class-check.sh` | This is the most important validation — it detects cluster recurrence patterns |
