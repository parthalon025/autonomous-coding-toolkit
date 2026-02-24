---
id: 0041
title: "Ambiguous base dir variable causes path double-nesting"
severity: should-fix
languages: [python, shell, all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Variable named log_dir already contains subdirectory, but os.path.join adds it again"
fix: "Name variables to encode their scope (log_base_dir vs intelligence_dir); verify paths before first use"
example:
  bad: |
    log_dir = "/var/logs/app/intelligence"
    # Developer thinks log_dir is base, adds another level
    intelligence_output = os.path.join(log_dir, "intelligence", "output.json")
    # Result: /var/logs/app/intelligence/intelligence/output.json
  good: |
    log_base_dir = "/var/logs/app"
    intelligence_dir = os.path.join(log_base_dir, "intelligence")
    intelligence_output = os.path.join(intelligence_dir, "output.json")
    # Result: /var/logs/app/intelligence/output.json
---

## Observation
Path variables are created with unclear semantics. A variable named `log_dir` might contain `/var/logs/app` or `/var/logs/app/intelligence`. Later code blindly adds subdirectories without checking the base, resulting in nested duplicates like `intelligence/intelligence/output.json`.

## Insight
Variable naming doesn't encode the directory's depth or scope. Different developers interpret the same variable name differently, leading to double-nesting or missing levels.

## Lesson
Name path variables to encode their scope: use `_base_dir` for top-level, `_dir` for specific subdirectories. Verify all paths at initialization time before they're used. Print and assert the structure early: `assert log_base_dir.endswith('/logs/app')` and `assert intelligence_dir.endswith('/intelligence')`. Test with actual filesystem operations to catch these bugs immediately.
