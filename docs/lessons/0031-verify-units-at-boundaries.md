---
id: 31
title: "Verify units at every boundary (0-1 vs 0-100)"
severity: should-fix
languages: [all]
category: integration-boundaries
pattern:
  type: semantic
  description: "Data crosses boundary with implicit unit change (proportion vs percentage)"
fix: "Verify units at every boundary; add unit to variable names (accuracy_pct, ratio_0_1)"
example:
  bad: |
    # Model outputs probability (0-1)
    def predict(input):
        return model.predict(input)  # Returns 0.85 (85% confidence)

    # UI assumes percentage (0-100)
    confidence = predict(data)
    ui.show_progress_bar(confidence)  # Shows 0.85% instead of 85%!
  good: |
    # Clear units in names and documentation
    def predict(input):
        return model.predict(input)  # Returns probability_ratio_0_1

    # UI explicitly converts
    probability_ratio_0_1 = predict(data)
    confidence_pct = probability_ratio_0_1 * 100
    ui.show_progress_bar(confidence_pct)  # Shows 85%
---

## Observation

Data flows between systems with different unit conventions: probabilities (0-1), percentages (0-100), milliseconds vs seconds, ppm vs ppb. A boundary crossing without explicit conversion silently produces wrong results with no error.

## Insight

Unit mismatches are silent failures because both sides are syntactically valid — a number is a number. The bug isn't a crash, it's a wrong result. A 0.85 probability rendered as 0.85% is off by two orders of magnitude but the code runs without error.

## Lesson

At every data boundary (API, database, service-to-service), document and verify units:

1. **Variable names include units**: `accuracy_pct`, `ratio_0_1`, `duration_ms`, `temp_celsius`
2. **API contracts specify units**: "response returns confidence as float 0-1, not percentage"
3. **Conversion explicit**: `pct = ratio_0_1 * 100` is clear; `pct = ratio_0_1` is not
4. **Tests verify conversion**: Test that a 0.5 probability produces a 50% display value

Example contract in docs or code:

```
GET /model/predict
Response: { "probability_ratio_0_1": 0.85 }
The probability is returned as a ratio (0-1), NOT a percentage.
```

Add unit verification tests:

```python
result = predict(data)
assert 0 <= result <= 1, f"Expected probability 0-1, got {result}"
```

For databases, use migration notes: "analytics.confidence column changed from integer (0-100) to float (0-1) in v2.1."

Verify by running data through all boundaries and spot-checking units at each step.
