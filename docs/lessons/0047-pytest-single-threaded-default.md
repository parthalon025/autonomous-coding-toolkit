---
id: 0047
title: "pytest runs single-threaded by default -- add xdist"
severity: should-fix
languages: [python]
category: performance
pattern:
  type: semantic
  description: "pytest test suite runs single-threaded when parallel execution would be significantly faster"
fix: "Add pytest-xdist to dev deps and addopts = '-n auto' to pytest config"
example:
  bad: |
    # pytest.ini or pyproject.toml
    [tool.pytest.ini_options]
    testpaths = ["tests"]
    # Result: runs tests one at a time (slow)

  good: |
    # pyproject.toml
    [tool.pytest.ini_options]
    testpaths = ["tests"]
    addopts = "-n auto --dist load"

    # requirements-dev.txt or pyproject.toml
    pytest-xdist>=3.5.0
    # Result: runs tests in parallel (fast)
---

## Observation
pytest, by default, runs tests sequentially in a single worker process. For test suites with 50+ tests, this is significantly slower than parallel execution. Developers run test suites serially and accept the slow feedback loop, unaware that xdist can parallelize.

## Insight
pytest-xdist provides automatic parallelization across multiple CPU cores. Running tests in parallel often provides 3-6x speedup on modern hardware, but requires explicit configuration. This is a low-effort, high-impact performance improvement.

## Lesson
Add `pytest-xdist>=3.5.0` to dev dependencies. Add `addopts = "-n auto --dist load"` to pytest configuration. This parallelizes tests automatically, using all available CPU cores. Use `-n 0` to disable parallelization temporarily for debugging. Test with your specific test suite to measure speedup. For very large test suites, use `-n 6` instead of `-n auto` to prevent memory exhaustion.
