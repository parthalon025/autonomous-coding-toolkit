---
id: 1
title: "Bare exception swallowing hides failures"
severity: blocker
languages: [python]
scope: [language:python]
category: silent-failures
pattern:
  type: syntactic
  regex: "^\\s*except\\s*:"
  description: "bare except clause without logging"
fix: "Always log the exception before returning a fallback: except Exception as e: logger.error(..., exc_info=True)"
example:
  bad: |
    try:
        result = api_call()
    except:
        return default_value
  good: |
    try:
        result = api_call()
    except Exception as e:
        logger.error("API call failed", exc_info=True)
        return default_value
---

## Observation
Bare `except:` clauses silently swallow all exceptions including KeyboardInterrupt, SystemExit, and MemoryError. When the fallback value is returned, there's no log trail to indicate a failure occurred, making debugging impossible.

## Insight
The root cause is a habit of writing "safe" exception handling that catches everything. The Python exception hierarchy means `except:` catches far more than intended. Combined with no logging, failures become invisible.

## Lesson
Never use bare `except:` — always catch a specific exception class and log before returning a fallback. The 3-line rule: within 3 lines of an except clause, there must be a logging call.
