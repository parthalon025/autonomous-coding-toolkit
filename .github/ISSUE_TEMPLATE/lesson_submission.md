---
name: Lesson Submission
about: Submit a new lesson learned from a production bug or agent failure
title: "[lesson] "
labels: lesson
assignees: ''
---

**What happened?**
<!-- The bug, symptom, or failure. Be specific — what broke and what was the impact? -->

**Root cause**
<!-- Why did it happen? What mechanism makes this dangerous? -->

**Pattern type**
- [ ] Syntactic (grep-detectable, can provide regex)
- [ ] Semantic (needs AI context to detect)

**Category**
<!-- Pick one: async-traps, resource-lifecycle, silent-failures, integration-boundaries, test-anti-patterns, performance, specification-drift, context-retrieval, planning-control-flow -->

**Severity**
<!-- Pick one: blocker (data loss/crash), should-fix (subtle bug), nice-to-have (code smell) -->

**Example**
```
# Bad (anti-pattern)


# Good (correct approach)

```

**Scope**
<!-- What projects/languages does this apply to? e.g., [universal], [language:python], [project:my-project] -->
