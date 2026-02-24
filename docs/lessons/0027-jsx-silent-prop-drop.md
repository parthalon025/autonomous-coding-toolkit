---
id: 27
title: "JSX silently drops wrong prop names"
severity: should-fix
languages: [javascript, typescript]
scope: [framework:preact]
category: silent-failures
pattern:
  type: semantic
  description: "JSX component receives prop with wrong name and silently ignores it"
fix: "Use TypeScript with strict component prop types; without TS, verify prop names against component signature"
example:
  bad: |
    // Component definition
    function UserCard({ name, email }) {
      return <div>{name} - {email}</div>;
    }

    // Caller: typo in prop name
    <UserCard name="Alice" emial="alice@example.com" />
    // Renders as "Alice - undefined" with no error
  good: |
    // TypeScript: catches typo at build time
    interface Props {
      name: string;
      email: string;
    }
    function UserCard({ name, email }: Props) {
      return <div>{name} - {email}</div>;
    }

    // TypeScript error: "emial" is not assignable to type 'Props'
---

## Observation

JSX silently ignores props that don't match the component's destructuring. A typo in a prop name (e.g., `emial` instead of `email`) renders as an empty or undefined value with no warning. The component silently degrades instead of surfacing the error.

## Insight

JSX is syntactic sugar over function calls. Passing an unknown prop is like passing an unused argument — JavaScript doesn't care. The component receives `{ name, email }` destructured from the props object; any other keys are ignored. Without a type system, there's no way to know a prop was missed.

## Lesson

Guard against silent prop drops:

1. **Use TypeScript**: Define component props as interfaces and use strict mode. TypeScript will catch unknown props at build time.
2. **Code review**: Without TypeScript, manually verify prop names. List them in a comment or doc.
3. **PropTypes** (React): Use PropTypes in development to catch missing/wrong props at runtime.

Example with PropTypes:

```javascript
function UserCard({ name, email }) {
  return <div>{name} - {email}</div>;
}

UserCard.propTypes = {
  name: PropTypes.string.isRequired,
  email: PropTypes.string.isRequired,
};
```

TypeScript is better (caught at build time), but PropTypes is better than nothing. Test with a known-bad sample (e.g., `<UserCard name="Alice" />` missing email) and verify the error is caught.
