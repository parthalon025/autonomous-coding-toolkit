# Testing Policies

Positive patterns for test suites. Derived from lessons #32, #44, #50, #73, #78.

## No Hardcoded Counts

**Assert test behavior, not test quantities.**
Hardcoded counts break when tests are added or removed. Count assertions create false failures unrelated to code quality.

```bash
# Pattern: assert threshold, not exact count
test_count=$(pytest --co -q 2>/dev/null | tail -1 | grep -o '[0-9]*')
[[ "$test_count" -ge 10 ]]  # not: [[ "$test_count" -eq 42 ]]
```

## Verify Threshold Math

**Test boundary conditions explicitly.**
Off-by-one errors in thresholds are the most common assertion bug. Test at, below, and above the boundary.

```python
# Pattern: test exact boundary
assert is_valid(threshold)      # at boundary
assert not is_valid(threshold - 1)  # below
assert is_valid(threshold + 1)  # above (if applicable)
```

## Test the Test

**Verify a test fails when the condition it checks is broken.**
A test that always passes catches nothing. Temporarily break the code and confirm the test detects it.

```bash
# Pattern: red-green verification
# 1. Write test → see it FAIL (red)
# 2. Write code → see it PASS (green)
# 3. Break code → see it FAIL again (confirms test works)
```

## Live Over Static

**One live integration test catches more bugs than six static reviewers.**
Static analysis finds structural issues but misses behavioral bugs. Always include at least one end-to-end test that exercises the real system.

```bash
# Pattern: combine static + live
shellcheck scripts/*.sh          # static: catches syntax
bash scripts/run-plan.sh --dry-run  # live: catches behavior
```

## Monotonic Test Count

**Test counts only go up between batches.**
A decreasing test count means something was deleted or broken. Track the high-water mark and enforce it.

```bash
# Pattern: compare against high-water mark
prev_count=$(jq -r '.test_count' .run-plan-state.json)
curr_count=$(pytest --co -q 2>/dev/null | tail -1 | grep -o '[0-9]*')
[[ "$curr_count" -ge "$prev_count" ]]
```
