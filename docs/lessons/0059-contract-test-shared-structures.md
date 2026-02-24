---
id: 59
title: "Independently-built shared structures diverge without contract tests"
severity: should-fix
languages: [all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Two modules independently construct the same ordered structure (feature list, column names, schema) without a shared source or contract test"
fix: "Add a contract test asserting both structures match, or extract a shared source of truth"
example:
  bad: |
    # module_a.py — builds feature list from config iteration
    features = [f.name for section in config for f in section.fields]

    # module_b.py — builds feature list from manual append
    features = []
    features.extend(presence_features)
    features.extend(pattern_features)
    # Missing: event_features added to module_a but not here
  good: |
    # shared.py — single source of truth
    def get_feature_names(config):
        return [f.name for section in config for f in section.fields]

    # OR: contract test
    def test_feature_names_match():
        assert module_a.get_features() == module_b.get_features()
---

## Observation

Two modules independently built the same ordered list (feature names for ML
column alignment). When a new section was added to one, the other was missed.
The lists had the same names but different ordering — causing a model trained
with column 3 = "lights_on" to use column 3 = "people_count" at inference.
Silent data corruption, no error.

## Insight

When two code paths independently construct a shared structure, a developer
adding to one path must manually remember to update the other — a human-memory
contract with no compile-time enforcement. This applies to feature vectors,
schema definitions, API response formats, config key lists, enum values, and
any ordered structure where position matters.

## Lesson

When two modules independently build a structure that must match (same
elements, same order), either: (1) extract a shared source of truth that both
import, or (2) add a contract test asserting equality. Add the contract test
BEFORE adding new elements — not after discovering the divergence.
