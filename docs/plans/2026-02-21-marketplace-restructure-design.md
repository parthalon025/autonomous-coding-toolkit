# Design: Marketplace-Ready Toolkit with Community Lesson Loop

**Date:** 2026-02-21
**Status:** Approved

## Problem

The autonomous-coding-toolkit repo works as a standalone clone but isn't discoverable as a Claude Code plugin. It's missing marketplace manifests, commands are in the wrong directory, skills contain personal project references, and the lesson system is static — only the maintainer adds new checks.

## Goals

1. Make the repo installable via `/plugin install` from a marketplace
2. Strip personal references so skills work for any project
3. Add a community lesson contribution pipeline where every user's production failures improve every other user's agent
4. Make the lesson-scanner and lesson-check.sh dynamic — new lessons are new checks, no code changes needed

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Ralph-loop handling | Merge into top level | Marketplace expects one plugin per repo |
| Personal references | Strip all | Makes toolkit truly generic and shareable |
| Distribution | Both self-hosted + official marketplace | Maximum reach |
| Lesson flow | GitHub PRs via `/submit-lesson` command | Low-tech, high-trust, maintainer curates |
| Lesson schema | Structured YAML frontmatter | Machine-parseable for automatic check generation |
| Automation | Semi-auto: command generates PR | User runs command, maintainer reviews and merges |
| Scanner design | Dynamic — reads lessons/ at scan time | Adding a lesson file = adding a check, no code changes |
| Attribution | Fork with attribution to superpowers | Clear credit in README and plugin.json |

## Architecture

### Community Lesson Loop

```
User hits bug → captures lesson → /submit-lesson → PR → maintainer merges →
  → lesson file added to docs/lessons/
  → lesson-check.sh gains new grep pattern (if syntactic)
  → lesson-scanner reads it dynamically at scan time (if semantic)
  → every user's next scan catches that pattern
```

### Structured Lesson Schema

Each lesson is a markdown file in `docs/lessons/` with machine-parseable YAML frontmatter:

```yaml
---
id: 7
title: "Bare exception swallowing hides failures"
severity: blocker          # blocker | should-fix | nice-to-have
languages: [python]        # python | javascript | typescript | shell | all
category: silent-failures  # async-traps | resource-lifecycle | silent-failures |
                           # integration-boundaries | test-anti-patterns | performance
pattern:
  type: syntactic          # syntactic (grep-detectable) | semantic (needs context)
  regex: "except:\\s*$"    # grep -P pattern (only for syntactic)
  description: "bare except without logging"
fix: "Always log the exception before returning a fallback"
example:
  bad: |
    try:
        result = api_call()
    except:
        return default_value
  good: |
    try:
        result = api_call()
    except Exception as e:
        logger.error("API call failed", exc_info=True)
        return default_value
---

## Observation
[What happened]

## Insight
[Why it happened]

## Lesson
[The rule to follow]
```

Key properties:
- `pattern.type: syntactic` → auto-wired into `lesson-check.sh` (grep-based, <2s)
- `pattern.type: semantic` → picked up by lesson-scanner agent dynamically
- `severity` maps to BLOCKER/SHOULD-FIX/NICE-TO-HAVE report tiers
- `regex` is the machine-readable contract for enforcement

### Dynamic Lesson Scanner

Rewrite `agents/lesson-scanner.md` to:

1. Glob `docs/lessons/*.md`
2. Parse YAML frontmatter from each
3. Filter by language (match target project)
4. For syntactic patterns: run grep with the `regex` field
5. For semantic patterns: use `description` + `example` for contextual analysis
6. Report using BLOCKER/SHOULD-FIX/NICE-TO-HAVE format

Current 6 hardcoded scan groups become starter lesson files.

### Dynamic lesson-check.sh

Update to read syntactic patterns from lesson files:

```bash
for lesson in docs/lessons/*.md; do
    regex=$(parse_frontmatter_regex "$lesson")
    if [ -n "$regex" ]; then
        grep -Pn "$regex" "$target_files" && report_violation "$lesson"
    fi
done
```

Still <2s — grep overhead is negligible per pattern.

### `/submit-lesson` Command

New command at `commands/submit-lesson.md`:

1. Ask user to describe the bug (what happened, what it should have done)
2. Identify anti-pattern and category
3. Determine syntactic vs semantic
4. If syntactic, generate grep regex and test against user's code
5. Fill structured YAML frontmatter
6. Write lesson file to `docs/lessons/NNNN-<slug>.md`
7. Generate PR against toolkit repo via `gh`

## Directory Structure (Target)

```
autonomous-coding-toolkit/
├── .claude-plugin/
│   ├── plugin.json              # Plugin metadata
│   └── marketplace.json         # Self-hosted marketplace config
├── skills/                      # 15 skills (generic, no personal refs)
│   ├── brainstorming/SKILL.md
│   ├── writing-plans/SKILL.md
│   ├── executing-plans/SKILL.md
│   ├── using-git-worktrees/SKILL.md
│   ├── subagent-driven-development/
│   │   ├── SKILL.md
│   │   ├── implementer-prompt.md
│   │   ├── spec-reviewer-prompt.md
│   │   └── code-quality-reviewer-prompt.md
│   ├── verification-before-completion/SKILL.md
│   ├── finishing-a-development-branch/SKILL.md
│   ├── test-driven-development/SKILL.md
│   ├── systematic-debugging/
│   │   ├── SKILL.md
│   │   ├── root-cause-tracing.md
│   │   ├── defense-in-depth.md
│   │   └── condition-based-waiting.md
│   ├── dispatching-parallel-agents/SKILL.md
│   ├── requesting-code-review/
│   │   ├── SKILL.md
│   │   └── code-reviewer.md
│   ├── receiving-code-review/SKILL.md
│   ├── writing-skills/SKILL.md
│   ├── using-superpowers/SKILL.md
│   └── verify/SKILL.md
├── commands/                    # Merged: .claude/commands/ + ralph-loop
│   ├── code-factory.md
│   ├── create-prd.md
│   ├── run-plan.md
│   ├── ralph-loop.md
│   ├── cancel-ralph.md
│   └── submit-lesson.md         # NEW
├── agents/
│   └── lesson-scanner.md        # REWRITTEN: dynamic
├── hooks/
│   ├── hooks.json
│   └── stop-hook.sh
├── scripts/
│   ├── run-plan.sh
│   ├── lib/
│   ├── setup-ralph-loop.sh      # Moved from plugins/
│   ├── quality-gate.sh
│   ├── lesson-check.sh          # REWRITTEN: dynamic
│   ├── auto-compound.sh
│   ├── entropy-audit.sh
│   ├── analyze-report.sh
│   ├── batch-audit.sh
│   ├── batch-test.sh
│   └── tests/
├── docs/
│   ├── ARCHITECTURE.md          # Updated
│   ├── CONTRIBUTING.md          # NEW: how to submit lessons
│   └── lessons/
│       ├── FRAMEWORK.md
│       ├── TEMPLATE.md          # Updated to match schema
│       ├── 0001-bare-exception-swallowing.md
│       ├── 0002-async-def-without-await.md
│       ├── 0003-create-task-without-callback.md
│       ├── 0004-hardcoded-test-counts.md
│       ├── 0005-sqlite-without-closing.md
│       └── ...                  # Community-contributed
├── examples/
│   ├── example-plan.md
│   └── example-prd.json
├── CLAUDE.md                    # Updated for new structure
├── README.md                    # Updated with community section + attribution
└── LICENSE
```

## Changes Summary

### Create
- `.claude-plugin/plugin.json` — plugin manifest
- `.claude-plugin/marketplace.json` — self-hosted marketplace config
- `commands/submit-lesson.md` — community lesson submission command
- `docs/CONTRIBUTING.md` — contribution guide
- `docs/lessons/0001-*.md` through `0005-*.md` — starter lessons (from current hardcoded checks)

### Move
- `.claude/commands/*.md` → `commands/`
- `plugins/ralph-loop/commands/*.md` → `commands/`
- `plugins/ralph-loop/hooks/` → `hooks/`
- `plugins/ralph-loop/scripts/setup-ralph-loop.sh` → `scripts/`

### Delete
- `plugins/` directory (fully merged)
- `.claude/commands/` directory (moved)

### Rewrite
- `agents/lesson-scanner.md` — dynamic, reads lessons/ at scan time
- `scripts/lesson-check.sh` — dynamic, reads syntactic patterns from lesson files
- `docs/lessons/TEMPLATE.md` — updated to structured YAML schema

### Update
- All 15 skills — strip personal references, add version to frontmatter
- `CLAUDE.md` — updated paths for new structure
- `README.md` — attribution, marketplace install, community section
- `docs/ARCHITECTURE.md` — updated for community lesson loop

## Attribution

README acknowledgment:
- Core skill chain forked from [superpowers](https://github.com/obra/superpowers) by Jesse Vincent / Anthropic
- Custom additions: quality gate pipeline, headless execution, ralph-loop, lesson framework, dynamic lesson scanner, community contribution pipeline
