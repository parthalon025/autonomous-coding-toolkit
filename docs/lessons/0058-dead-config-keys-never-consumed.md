---
id: 58
title: "Config keys registered but never consumed are dead knobs"
severity: should-fix
languages: [python]
scope: [project:autonomous-coding-toolkit]
category: silent-failures
pattern:
  type: semantic
  description: "Config keys registered in a defaults/schema file but never read via get_config or equivalent"
fix: "Wire every registered config key to a get_config call, or remove the dead registration"
example:
  bad: |
    # config_defaults.py
    register_config("automation.min_confidence", default=0.7)
    register_config("automation.max_suggestions", default=5)

    # automation.py — uses hardcoded constants, never reads config
    MIN_CONFIDENCE = 0.7
    MAX_SUGGESTIONS = 5
  good: |
    # config_defaults.py
    register_config("automation.min_confidence", default=0.7)

    # automation.py — reads from config system
    min_confidence = get_config_value("automation.min_confidence")
---

## Observation

Config keys were registered in a defaults file and exposed in a Settings UI,
but the consuming module used hardcoded module-level constants instead of
reading from config. Users could adjust settings that had zero runtime effect.

## Insight

This happens when registration and consumption are built in different work
batches. Batch N registers the config keys with defaults. Batch N+1
implements the module with hardcoded constants matching those defaults.
Neither batch verifies the integration. Dead config is worse than missing
config — it lies to operators by showing controls that do nothing.

## Lesson

Every config key registration must have a corresponding read call in the
consuming module. Add a CI check or quality gate step to detect orphaned
config keys: extract registered keys, extract consumed keys, diff them.
Config registration and consumption should happen in the same PR, or a
contract test must verify that every registered key has at least one consumer.
