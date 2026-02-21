---
description: "Generate a PRD with machine-verifiable acceptance criteria from a feature description"
argument-hint: "<feature description>"
---

# Create PRD

Generate a Product Requirements Document for the given feature.

## Input

The user provides a feature description: $ARGUMENTS

## Process

1. **Understand the feature** — Ask clarifying questions if the description is ambiguous
2. **Break into tasks** — Generate 8-15 small, granular tasks (not 3-5 large ones)
3. **Machine-verifiable criteria** — Every acceptance criterion must be a command that returns pass/fail:
   - Test commands: `pytest tests/test_feature.py -x`
   - Lint commands: `python3 -m py_compile file.py`
   - Endpoint checks: `curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/endpoint`
   - File existence: `test -f path/to/file`
   - Pattern checks: `grep -q 'expected_pattern' file`
4. **Separate investigation from implementation** — "Research X" and "Implement X" are different tasks
5. **Order by dependency** — Tasks should be ordered so each builds on the previous

## Output Format

Save to `tasks/prd.json` (create `tasks/` directory if needed):

```json
[
  {
    "id": 1,
    "title": "Short imperative title",
    "description": "What needs to be done and why",
    "acceptance_criteria": [
      "pytest tests/test_auth.py::test_login -x",
      "test -f src/auth/handler.py"
    ],
    "passes": false,
    "blocked_by": []
  }
]
```

Also save a human-readable version to `tasks/prd-<feature-slug>.md` with full descriptions.

## Rules

- Each task should take 1-3 iterations of a Ralph loop to complete
- Acceptance criteria MUST be shell commands that exit 0 on success, non-zero on failure
- No vague criteria like "code is clean" or "well-tested" — everything is boolean
- Include setup tasks (create directories, install deps) as separate tasks
- Final task should always be "Run full quality gate" with all checks combined
