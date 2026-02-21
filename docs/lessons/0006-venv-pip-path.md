---
id: 6
title: ".venv/bin/pip installs to wrong site-packages"
severity: should-fix
languages: [python, shell]
category: integration-boundaries
pattern:
  type: syntactic
  regex: "\\.venv/bin/pip\\b"
  description: ".venv/bin/pip instead of .venv/bin/python -m pip — pip shebang may point to wrong Python"
fix: "Use .venv/bin/python -m pip to ensure packages install into the correct virtual environment"
example:
  bad: |
    .venv/bin/pip install requests
  good: |
    .venv/bin/python -m pip install requests
---

## Observation
When multiple Python versions exist on the system (e.g., system Python + Homebrew Python), `.venv/bin/pip` may resolve to the wrong Python interpreter via its shebang line. Packages install into the wrong site-packages directory, making them invisible to the venv's Python.

## Insight
The pip executable's shebang (`#!/path/to/python`) is set at venv creation time. If PATH changes or another Python is installed later, the shebang becomes stale. Using `python -m pip` always uses the Python that's running it.

## Lesson
Never call `.venv/bin/pip` directly. Always use `.venv/bin/python -m pip` to guarantee the correct interpreter and site-packages directory.
