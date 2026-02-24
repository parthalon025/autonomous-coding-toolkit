# Lesson Scope Metadata — Design

**Date:** 2026-02-24
**Status:** Approved
**Phase:** 5A (Adoption & Polish)
**Evidence:** Lesson #63 — 67% false positive rate predicted at ~100 lessons without scope metadata (Zimmermann, 622 predictions)

---

## Problem

The lesson system has 146 lessons (70 toolkit + 76 workspace) — past the ~100 threshold where unscoped lessons hit untenable false positive rates. Domain-specific lessons (HA entity resolution, Telegram bot polling) fire on unrelated projects. This erodes trust and slows quality gates.

Two systems need scope:
1. **Toolkit lessons** (`docs/lessons/0001-*.md`) — YAML frontmatter, scanned by `lesson-check.sh`
2. **Workspace lessons** (`~/Documents/docs/lessons/2026-*.md`) — freeform markdown, scanned by `lesson-scanner` agent

## Goals

1. **Project goal**: Reduce false positive rate below 20% as lesson count grows
2. **Workspace goal**: Lessons compound across projects — bugs found in one project propagate to others through evidence, not manual tagging

---

## Design

### 1. Scope Vocabulary

Hierarchical tag system with three tiers:

```
universal              # applies to all projects (default)
language:<lang>        # python, bash, javascript, typescript
framework:<framework>  # pytest, preact, systemd, docker
domain:<domain>        # ha-aria, telegram, notion, ollama
project:<name>         # exact project directory name match
```

**Matching rule**: A lesson is relevant if ANY of its scope tags matches the project's scope set, OR if the lesson's scope includes `universal`.

**Relationship to `languages:`**: The existing `languages:` field handles file-level filtering (which extensions to scan). `scope:` handles project-level filtering (should this lesson be loaded at all?). They are orthogonal:
- `scope: [domain:ha-aria]` + `languages: [python]` = only scan `.py` files, only in ha-aria
- `scope: [language:python]` + `languages: [python]` = scan `.py` files in any Python project
- `scope: [universal]` + `languages: [python]` = scan `.py` files in every project

### 2. Project Manifests (Supply Side)

Each project declares its identity via scope tags in its CLAUDE.md:

```markdown
## Scope Tags
language:python, framework:pytest, domain:ha-aria
```

lesson-check.sh reads this field. Benefits:
- **No heuristic code** — projects declare themselves
- **Extensible** — new domains need no code changes
- **Projects own their identity** — Cluster B (integration boundary) bugs eliminated

**Fallback**: If no `## Scope Tags` section exists, auto-detect from:
1. `detect_project_type()` for language (already exists)
2. Framework markers: `pyproject.toml` containing `pytest` → `framework:pytest`
3. Default to `{universal}` — all lessons apply

**CLI override**: `--scope "language:python,domain:ha-aria"` for ad-hoc runs.

### 3. Lesson Scope Field (Demand Side)

#### Toolkit lessons (YAML frontmatter)

New field in YAML block:

```yaml
---
id: 1
title: "Bare exception swallowing hides failures"
scope: [language:python]    # NEW — project-level filtering
languages: [python]          # existing — file-level filtering
severity: blocker
# ...
---
```

Default when omitted: `[universal]` — backward compatible.

#### Workspace lessons (freeform markdown header)

New field in the metadata block:

```markdown
# Lesson: HA Entity Area Resolution

**Date:** 2026-02-14
**System:** ARIA (ha-aria)
**Tier:** lesson_learned
**Scope:** domain:ha-aria           # NEW
**Category:** data-model
**Keywords:** HA, entity, area
```

Default when omitted: `universal`.

### 4. lesson-check.sh Changes

```
parse_lesson()          — add scope parsing from YAML (new field: lesson_scope)
detect_project_scope()  — NEW: read CLAUDE.md ## Scope Tags, fallback to detect_project_type()
scope_matches()         — NEW: returns 0 if lesson scope intersects project scope
main loop               — add scope_matches() gate before language/grep check
build_help()            — show scope per lesson in --help output
CLI flags:
  --all-scopes          — bypass scope filtering (scan everything)
  --show-scope          — display detected project scope and exit
  --scope <tags>        — override project scope manually
```

### 5. Lesson-Scanner Agent Changes

Update `~/.claude/agents/lesson-scanner.md` prompt to:
1. Read `**Scope:**` from workspace lesson headers
2. Detect project context from working directory (read CLAUDE.md scope tags)
3. Filter lessons by scope match before applying
4. Report scope mismatch in output: `"Skipped 23 lessons (scope mismatch)"`

### 6. Scope Inference at Creation Time

Integrate into the `/capture-lesson` skill:

1. When a new lesson is created, analyze its content for scope signals:
   - File paths mentioned → infer project/domain
   - System names (HA, Telegram, Notion) → infer domain
   - Language-specific patterns → infer language
2. Propose scope tags to the user for confirmation
3. Write the scope field into the lesson

This prevents decay — new lessons get scope at birth, not retroactively.

### 7. Scope Inference Script (Bulk Tagging)

`scripts/scope-infer.sh` for the initial migration:

```
scope-infer.sh [--dir <lessons-dir>] [--dry-run] [--apply]
```

For each lesson without a scope field:
1. Read content, extract signals (keywords, file paths, system references)
2. Apply heuristics:
   - Title/body contains "HA", "entity", "area", "automation" → `domain:ha-aria`
   - Title/body contains "Telegram", "bot", "polling" → `domain:telegram`
   - Title/body contains "Notion", "database", "sync" → `domain:notion`
   - `languages: [python]` with no domain signals → `language:python`
   - No signals → `universal`
3. Output proposed scope as a diff (or apply with `--apply`)
4. Generate summary: "Inferred scope for N lessons: X universal, Y domain-specific, Z language-specific"

### 8. Propagation Tracking

New optional field in lesson YAML:

```yaml
validated_in: [ha-aria, telegram-brief, autonomous-coding-toolkit]
```

**Workflow**:
1. Lesson created with `scope: [domain:ha-aria]` and `validated_in: [ha-aria]`
2. Same anti-pattern found in telegram-brief → `validated_in: [ha-aria, telegram-brief]`
3. At 3+ validations across different domains → scope auto-widens to `universal`

**Implementation**: The lesson-scanner agent appends to `validated_in` when it finds a violation and the fix is confirmed. `scope-infer.sh --update-propagation` can check for scope-widening candidates.

This is the compounding mechanism: lessons start narrow and earn broader scope through evidence.

---

## File Inventory

| File | Action | Description |
|------|--------|-------------|
| `scripts/lesson-check.sh` | Modify | Add scope parsing, project detection, filtering, CLI flags |
| `scripts/scope-infer.sh` | Create | Bulk scope inference for existing lessons |
| `scripts/tests/test-scope-filtering.sh` | Create | Tests for scope matching, project detection |
| `scripts/tests/test-lesson-check.sh` | Modify | Add scope-aware test cases |
| `docs/lessons/TEMPLATE.md` | Modify | Add scope field to template |
| `docs/lessons/0001-*.md` through `0010-*.md` | Modify | Add scope tags to 10 existing toolkit lessons |
| `~/.claude/agents/lesson-scanner.md` | Modify | Add scope filtering to agent prompt |
| `~/.claude/skills/capture-lesson/SKILL.md` | Modify | Add scope inference to creation workflow |
| `~/Documents/docs/lessons/2026-*.md` | Modify (via scope-infer.sh) | Add **Scope:** field to 76 workspace lessons |

## Scope Tag Assignments (Existing Toolkit Lessons)

| ID | Title | Proposed Scope |
|----|-------|---------------|
| 0001 | Bare exception swallowing | `[language:python]` |
| 0002 | Async def without await | `[language:python]` |
| 0003 | create_task without callback | `[language:python]` |
| 0004 | Hardcoded test counts | `[universal]` |
| 0005 | sqlite without closing | `[language:python]` |
| 0006 | venv pip path | `[language:python, framework:pytest]` |
| 0007 | Runner state self-rejection | `[project:autonomous-coding-toolkit]` |
| 0008 | Quality gate blind spot | `[project:autonomous-coding-toolkit]` |
| 0009 | Parser overcount empty batches | `[project:autonomous-coding-toolkit]` |
| 0010 | local outside function bash | `[language:bash]` |

## Testing Plan

1. **Scope parsing**: lesson with scope field parsed correctly; missing scope defaults to universal
2. **Project detection**: CLAUDE.md scope tags read; fallback to language detection; --scope override
3. **Scope matching**: universal matches everything; domain:ha-aria only matches ha-aria projects; empty intersection skips lesson
4. **--all-scopes**: bypasses filtering, all lessons applied
5. **--show-scope**: displays detected scope and exits
6. **Integration**: full lesson-check run with scope filtering on a non-Python project skips Python-only lessons
7. **scope-infer.sh**: correct inference from lesson content; --dry-run shows diff; --apply writes

## Dependencies

- None on other phases
- `detect_project_type()` in `lib/common.sh` already exists
- TEMPLATE.md update is backward-compatible (scope optional, defaults universal)

## Risks

| Risk | Mitigation |
|------|-----------|
| Over-scoping hides real violations | `--all-scopes` escape hatch; `validated_in` promotes proven lessons |
| Scope tags go stale | Propagation tracking auto-widens; scope-infer.sh can re-run periodically |
| CLAUDE.md scope tags missing | Fallback to language detection; warn in --show-scope output |
| Manual tagging burden for new lessons | `/capture-lesson` skill infers scope at creation time |
