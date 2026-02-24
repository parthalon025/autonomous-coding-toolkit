---
id: 0042
title: "Spec compliance without quality review misses defensive gaps"
severity: should-fix
languages: [all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Code review checks only spec compliance but misses error handling, cleanup, validation, and timeouts"
fix: "Include a defensive gaps checklist in code review, separate from spec compliance"
example:
  bad: |
    # Spec: "Call API and return result"
    def fetch_data(url):
        response = requests.get(url)  # No timeout, no error handling
        return response.json()  # Crashes if invalid JSON
  good: |
    # Spec + defensive: Call API with timeout, handle errors, validate
    def fetch_data(url):
        try:
            response = requests.get(url, timeout=30)
            return response.json()
        except (requests.Timeout, requests.JSONDecodeError) as e:
            logger.error(f"Fetch failed: {e}")
            return None
---

## Observation
Code review focuses on whether the implementation matches the specification (does it call the API? does it return the result?). It skips defensive programming: timeouts, error handling, input validation, cleanup paths, and null checks. The code is spec-compliant but fragile.

## Insight
Spec compliance is a floor, not a ceiling. Defensive programming is orthogonal to spec compliance. Reviewers who are trained to check spec often skip defensive gaps because they're not part of the spec.

## Lesson
Create a separate defensive gaps checklist for code review: Does the code have timeouts? Error handling? Input validation? Cleanup paths? Null checks? Is there logging for failure cases? Run this checklist independently from spec compliance. Make it part of the merge gate, not optional. Test with fault injection and chaos testing to verify defensive behavior.
