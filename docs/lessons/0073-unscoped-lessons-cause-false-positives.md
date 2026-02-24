---
id: 73
title: "Unscoped lessons cause 67% false positive rate at scale"
severity: should-fix
languages: [all]
scope: [project:autonomous-coding-toolkit]
category: context-retrieval
pattern:
  type: semantic
  description: "Lesson files without scope metadata applied universally to all projects, causing irrelevant violations to fire on projects where the anti-pattern cannot occur."
fix: "Add scope: tags to every lesson. Use detect_project_scope() to filter lessons by project context. Default to [universal] only for genuinely cross-cutting patterns."
example:
  bad: |
    # Lesson about HA automation keys fires on a React project
    # Lesson about JSX factory fires on a Python-only project
    # 67% of violations are irrelevant noise
  good: |
    scope: [domain:ha-aria]  # Only fires on HA projects
    scope: [language:javascript, framework:preact]  # Only fires on JSX projects
    scope: [universal]  # Genuinely applies everywhere
---

## Observation
As the lesson library grew past ~50 lessons, the false positive rate on any given project reached 67%. Lessons about Home Assistant automation keys fired on React projects. Lessons about JSX factory issues fired on Python-only projects. Developers started ignoring lesson-check output entirely.

## Insight
Without scope metadata, every lesson fires everywhere. This is correct for universal patterns (bare except, missing await) but wrong for domain-specific patterns. The noise from irrelevant violations drowns the signal from real issues, causing the entire system to be ignored.

## Lesson
Every lesson needs scope metadata. Use `scope: [universal]` only for patterns that genuinely apply to all projects. For everything else, scope to language, framework, domain, or specific project. The scope system keeps signal-to-noise high as the library scales.
