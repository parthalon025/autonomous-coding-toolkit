---
name: check-lessons
description: Use when starting planning or coding to surface relevant lessons that prevent repeating past mistakes
---

# Check Lessons

## Overview

Proactive lesson retrieval that searches the lessons-learned system for patterns matching the current work. Surfaces relevant cluster mitigations, open corrective actions, and key takeaways before you start coding — preventing the same bug from happening twice.

## When to Use

- Before `EnterPlanMode` — check if planned work touches any lesson clusters
- When editing a file that appears in any lesson's `**Files:**` field
- When a test fails in a pattern matching a known cluster
- When starting work on a system with known failure history
- When `/check-lessons` is invoked

## Process

### Step 1: Identify the Work Domain

Determine what is being touched:
- Which files and directories?
- Which systems (HA, Telegram, Notion, systemd, etc.)?
- Which patterns (async, error handling, data flow, schema, startup, etc.)?

### Step 2: Search by Keyword

Grep the SUMMARY.md Quick Reference table for matching terms:

```bash
# Search for keywords matching the work domain
grep -i "keyword1\|keyword2\|keyword3" ~/Documents/docs/lessons/SUMMARY.md
```

Search for:
- System names (e.g., "aria", "telegram", "systemd")
- Pattern names (e.g., "async", "schema", "cache", "startup")
- Error types (e.g., "silent", "missing", "wrong")
- Cluster letters (A through F) relevant to the work type

### Step 3: Search by File Overlap

If specific files are being modified, check if any lesson references them:

```bash
# Search lesson files for matching file paths
grep -rl "filename\|module_name" ~/Documents/docs/lessons/2026-*.md
```

Then read matching lessons to extract their Key Takeaway and Corrective Actions.

### Step 4: Read Cluster Mitigations

For each matching cluster, read the mitigations from SUMMARY.md:

| Work Type | Check Clusters |
|-----------|---------------|
| Error handling, exception flow | A (Silent Failures) |
| Cross-service changes, API contracts | B (Integration Boundary) |
| Service restart, initialization | C (Cold-Start) |
| Plan execution, spec interpretation | D (Specification Drift) |
| Context management, lesson scoping | E (Context & Retrieval) |
| Task decomposition, batch ordering | F (Planning & Control Flow) |

### Step 5: Present Findings

Format output as:

```
Relevant Lessons for [current work]:

Cluster [X] ([Name]) — N matches:
  #[num]: [one-line summary from Quick Reference table] (Tier: [tier])
  #[num]: [one-line summary] (Tier: [tier])
  Mitigations:
    1. [applicable mitigation from SUMMARY.md cluster section]
    2. [applicable mitigation]

File overlap:
  #[num] references [matching file] — Key Takeaway: [takeaway text]

Open corrective actions:
  #[num] Action [N]: [action description] (status: proposed)
```

### Step 6: Flag Open Corrective Actions

Read each matching lesson file and check the Corrective Actions table. If any action has `| proposed |` status, flag it — these are known fixes that haven't been validated yet.

## Proactive Trigger Guidance

This skill should be invoked automatically in these situations:

1. **Before planning:** When about to enter plan mode for work touching files in `~/Documents/projects/ha-aria/`, `~/Documents/projects/telegram-*/`, or any project with lesson history
2. **On test failure:** When a test fails with a pattern matching cluster keywords (silent return, schema mismatch, missing await, empty collection)
3. **On file edit:** When modifying a file that appears in any lesson's Files field — use a quick grep to check

## Key References

| File | Purpose |
|------|---------|
| `~/Documents/docs/lessons/SUMMARY.md` | Quick Reference table + cluster mitigations |
| `~/Documents/docs/lessons/FRAMEWORK.md` | OIL taxonomy and category definitions |
| `~/Documents/docs/lessons/DIAGNOSTICS.md` | Symptom-to-cause lookup table |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Searching only by system name | Also search by pattern (async, schema, cache) and error type (silent, missing) |
| Ignoring standalone lessons (no cluster) | Standalone lessons still have Key Takeaways — include them if keywords match |
| Skipping open corrective actions | Proposed actions are the highest-signal items — they represent known but unvalidated fixes |
| Dumping all 72 lessons | Filter aggressively — only surface lessons with keyword, file, or cluster overlap to the current work |
