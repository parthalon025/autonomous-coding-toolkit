---
id: 22
title: "Build tool JSX factory shadowed by arrow params"
severity: blocker
languages: [javascript, typescript]
scope: [framework:preact]
category: silent-failures
pattern:
  type: syntactic
  regex: "\.map\\(h\\s*=>"
  description: "Arrow function parameter shadows build tool JSX factory injection"
fix: "Never use single-letter variable names that match build tool injections (h, React)"
example:
  bad: |
    import { h } from 'preact';
    const items = users.map(h => (
      <div key={h.id}>{h.name}</div>  // h refers to user, not JSX factory
    ));  // JSX transform fails silently
  good: |
    import { h } from 'preact';
    const items = users.map(user => (
      <div key={user.id}>{user.name}</div>
    ));  // Clear intent, no shadowing
---

## Observation

Build tools like esbuild inject `h` (or `React` in some configs) as a JSX factory at the top of each file. When code uses `h` as an arrow function parameter (`.map(h => ...)`), the parameter shadows the injected factory. JSX elements become malformed, rendering silently fails with no error.

## Insight

This is a tooling footgun: the injection is invisible but syntactically valid. A user object parameter named `h` is reasonable in isolation, but creates a silent failure when combined with JSX. The build tool cannot detect this because it happens after transformation.

## Lesson

Never use `h`, `React`, or other build-tool-injected names as local variable or parameter names:

- Avoid: `.map(h => ...)`, `.forEach(React => ...)`
- Use: `.map(user => ...)`, `.forEach(Component => ...)`

Apply this consistently across your codebase. In code review, flag any single-letter parameter names that match build tool injections. The cost of renaming is zero; the cost of debug time is unbounded.

For teams using JSX, add a linter rule (ESLint with `no-shadow` + `no-loop-func`) to catch this pattern automatically.
