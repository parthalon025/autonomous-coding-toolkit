---
id: 0046
title: "Plan-specified test assertions can have math bugs"
severity: should-fix
languages: [all]
category: test-anti-patterns
pattern:
  type: semantic
  description: "Implementation plan specifies test thresholds with math errors that implementer copies verbatim"
fix: "Verify threshold boundary logic independently before writing the test"
example:
  bad: |
    # Plan says: "Assert that 90% of requests succeed"
    # Implementer writes (copying from plan):
    assert success_count / total_count >= 0.9
    # But 0.9 is already 90%, so this is correct.
    # But what if plan meant: "Assert that error rate is below 10%"?
    # assert error_count / total_count <= 0.1  # Different logic

    # Implementer didn't verify the math matched intent
  good: |
    # Plan specifies: "Assert 90% success rate (>= 0.9)"
    # Before implementing, verify:
    # 90% = 0.9 (correct multiplier)
    # 10% = 0.1 (correct error rate)
    # Test with known values: 9/10 = 0.9 ✓
    assert success_count / total_count >= 0.9
---

## Observation
Implementation plans specify test thresholds and assertions. Implementers copy these verbatim without verifying the math. If the plan has a boundary condition error (off-by-one, wrong direction, incorrect multiplier), the implementer creates a test that passes despite incorrect logic.

## Insight
Plan authors may write thresholds informally or with implicit assumptions. Implementers assume the math is correct and don't double-check. Boundary logic errors slip through undetected.

## Lesson
Before implementing any threshold-based assertion, verify the math independently. Test with concrete values to confirm the boundary is correct. For example, if the plan says "90% success rate," verify: success_count=9, total=10, then assert 9/10 >= 0.9 should pass. success_count=8, total=10, then assert 8/10 >= 0.9 should fail. Write and run these boundary tests before implementing the main test.
