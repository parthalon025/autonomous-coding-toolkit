---
id: 29
title: "Never write secret values into committed files"
severity: blocker
languages: [all]
category: silent-failures
pattern:
  type: syntactic
  regex: "(api_key|token|password|secret)\\s*=\\s*['\"][^'\"]{8,}"
  description: "Actual secret values hardcoded in source files"
fix: "Reference secrets by env var name only; in tests use mock values; enforce with pre-commit hooks"
example:
  bad: |
    # config.py
    API_KEY = 'sk-1234567890abcdef'
    DATABASE_PASSWORD = 'prodPassword123'

    # Committed to repo, exposed to anyone with access
  good: |
    # config.py
    import os
    API_KEY = os.environ.get('API_KEY', '')
    DATABASE_PASSWORD = os.environ.get('DATABASE_PASSWORD', '')

    # .env (never committed, sourced by deployment)
    API_KEY=sk-1234567890abcdef
    DATABASE_PASSWORD=prodPassword123
---

## Observation

Secrets hardcoded in source files are committed to version control, exposing them to anyone with repo access. Even after deletion, secrets remain in git history forever.

## Insight

Source code is assumed to be shareable (it's version-controlled, reviewed, archived). Secrets are the opposite (must be kept private, rotated, compartmentalized). Mixing them violates the principle of least privilege and creates an irreversible exposure risk.

## Lesson

**Never write secret values (passwords, API keys, tokens) into any file that gets committed:**

1. **Configuration files**: Use environment variables with `os.environ.get()` (Python) or `process.env` (Node.js)
2. **Tests**: Use mocks, fixtures, or test fixtures; never real credentials
3. **.env files**: Create locally, gitignore them, source them at runtime
4. **Pre-commit hooks**: Add linters (gitleaks, detect-secrets) to reject commits containing secrets

If a secret is committed:

1. Rotate it immediately (invalidate the exposed credential)
2. Scrub it from history (git filter-branch, BFG repo cleaner)
3. Document the incident

Recommended workflow:

- `config.py` reads from `os.environ`
- `.env` (gitignored) contains local values
- CI/deployment sets env vars via secrets manager (Vault, AWS Secrets, etc.)
- Tests use fixtures/mocks, no real credentials

Verify by inspecting the last 50 commits: `git log --all -S 'sk-' | head -50` should find zero matches.
