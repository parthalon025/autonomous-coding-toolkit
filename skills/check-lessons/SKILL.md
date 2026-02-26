---
name: check-lessons
description: Use when starting planning or coding to surface relevant lessons that prevent repeating past mistakes
---

# Check Lessons

## Overview

Proactive lesson retrieval that searches the lessons-learned system for patterns matching the current work. Surfaces relevant cluster mitigations, open corrective actions, and key takeaways before you start coding — preventing the same bug from happening twice.

Uses `lessons-db search` (LanceDB semantic vector search + SQLite keyword/file matching) — not grep.

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

### Step 2: Semantic Search

Run `lessons-db search` with descriptive queries for the work domain:

```bash
# Search by description of what's being built or the pattern at risk
lessons-db search "async error handling fire and forget"
lessons-db search "sqlite context manager connection close"
lessons-db search "schema change consumer update"

# Search by file being edited (surfaces lessons that reference this file)
lessons-db search "" --file path/to/file.py

# Search by code content (check against detection patterns)
lessons-db search "" --content "except:"
```

Run 2-3 focused queries targeting:
- The specific system being touched (e.g., "HA entity state subscription")
- The error pattern at risk (e.g., "silent exception return None")
- The cluster domain (e.g., "cold start missing baseline seed")

### Step 3: Map Clusters

For each result, note the cluster and look up cluster-wide mitigations:

| Cluster | Name | Watch For |
|---------|------|-----------|
| A | Silent Failures | Any fallback/except/return None without logging |
| B | Integration Boundaries | Cross-service calls, shared state, API contracts |
| C | Cold-Start | First-run, missing baselines, state seeding |
| D | Specification Drift | Agent builds wrong thing correctly — verify spec |
| E | Context & Retrieval | Info available but misscoped or buried |
| F | Planning & Control Flow | Wrong decomposition contaminates downstream |

### Step 4: Present Findings

Format output as:

```
Relevant Lessons for [current work]:

Cluster [X] ([Name]) — N matches:
  #[num]: [one_liner from search result]
  #[num]: [one_liner from search result]
  Mitigations:
    1. [applicable cluster mitigation]
    2. [applicable cluster mitigation]

File overlap:
  #[num] references [matching file] — Key Takeaway: [takeaway text]
```

### Step 5: Flag Open Corrective Actions

Check `lessons-db status` for open scan findings and overdue corrective actions related to the matched lessons.

## Key References

| Source | How to query |
|--------|-------------|
| `lessons-db search "<query>"` | Semantic + keyword search (primary) |
| `lessons-db search "" --file <path>` | File-overlap search |
| `lessons-db search "" --content "<code>"` | Pattern match against detection rules |
| `lessons-db status` | Open findings + overdue actions |

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using grep on markdown files | Use `lessons-db search` — it has semantic search, not just keyword match |
| Single vague query | Run 2-3 focused queries: system, error pattern, cluster domain |
| Ignoring standalone lessons (no cluster) | Search results include all lessons — cluster assignment is informational |
| Skipping open corrective actions | Run `lessons-db status` to surface proposed-but-unvalidated fixes |
