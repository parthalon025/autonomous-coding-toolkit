---
id: 15
title: "Frontend-backend schema drift invisible until e2e trace"
severity: should-fix
languages: [typescript, javascript, python, all]
category: integration-boundaries
pattern:
  type: semantic
  description: "Frontend and backend define the same data shape independently and drift over time"
fix: "Shared schema definition (types generated from API schema) or contract tests"
example:
  bad: |
    # Backend (Python)
    def get_user():
        return {"id": 1, "name": "Alice", "email": "alice@example.com"}

    # Frontend (TypeScript, independent definition)
    interface User { id: number; name: string; }
    // Missing email field! Silent bug.
  good: |
    # Shared schema (OpenAPI/GraphQL)
    components:
      schemas:
        User:
          type: object
          properties:
            id: { type: integer }
            name: { type: string }
            email: { type: string }

    # Generated TypeScript (from schema)
    // User interface auto-generated, always in sync
---

## Observation
Frontend and backend define the same data shape (User, Product, etc.) independently. Over time they drift — backend adds an `email` field to User, frontend's User interface doesn't include it. The field is silently ignored on the frontend. No error until a feature tries to use the field and finds it missing.

## Insight
The root cause is separate schema definitions. Each layer maintains its own types, and they're never synchronized. Backend and frontend evolve independently. The drift is invisible because both sides are "correct" within their own codebase — TypeScript compiles, Python runs, API calls succeed. Only end-to-end traces reveal the mismatch.

## Lesson
Never define schemas independently in frontend and backend. Use a single source of truth: OpenAPI, GraphQL schema, Protobuf, or equivalent. Generate types from the shared schema. Alternatively, use contract tests that verify the API response matches what the frontend expects. The contract must be version-controlled and tested.
