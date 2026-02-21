---
id: 0039
title: "Fallback `or default()` hides initialization bugs"
severity: should-fix
languages: [python]
category: silent-failures
pattern:
  type: semantic
  description: "Expression like `self._resource or Resource()` creates new resource every access when _resource was never initialized"
fix: "Replace with guard return + warning: if not self._resource: logger.warning('not initialized'); return"
example:
  bad: |
    def get_value(self):
        # If _resource never initialized, creates new one silently
        return (self._resource or Resource()).value

    # Bug: each call creates a new Resource if never initialized
  good: |
    def get_value(self):
        if not self._resource:
            logger.warning("Resource not initialized")
            return None
        return self._resource.value
---

## Observation
Using `or` as a fallback to create a default object (`self._resource or Resource()`) masks initialization bugs. The code never fails; it silently creates a new object on every access, leading to duplicate work, lost state, and difficult-to-trace behavior.

## Insight
Fallback patterns hide the bug rather than fail fast. The developer doesn't know initialization was skipped because the code "works." State stored in the first Resource is lost on the next access, causing subtle state inconsistencies.

## Lesson
Replace fallback patterns with explicit guard checks. Log a warning if the resource is not initialized, then return early or raise an exception. This makes initialization bugs fail fast and visible. Test initialization paths explicitly to ensure resources are initialized before first use.
