---
id: 5
title: "sqlite3 connections leak without closing() context manager"
severity: should-fix
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "sqlite3\\.connect\\("
  description: "sqlite3.connect() — verify closing() context manager is used (with conn: manages transactions, not connections)"
fix: "Use contextlib.closing(): with closing(sqlite3.connect(db_path)) as conn:"
example:
  bad: |
    conn = sqlite3.connect("data.db")
    with conn:
        conn.execute("INSERT ...")
    # Connection never explicitly closed — relies on GC
  good: |
    from contextlib import closing
    with closing(sqlite3.connect("data.db")) as conn:
        with conn:
            conn.execute("INSERT ...")
---

## Observation
`with conn:` in sqlite3 manages transactions (auto-commit/rollback), NOT the connection lifecycle. The connection remains open until garbage collected. Under load or in long-running processes, this leaks file descriptors.

## Insight
Python's sqlite3 `with` statement is misleading — it looks like a resource manager but only manages transactions. The actual connection close requires either `conn.close()` or `contextlib.closing()`.

## Lesson
Always wrap `sqlite3.connect()` in `contextlib.closing()` for reliable cleanup. The pattern is: `with closing(connect(...)) as conn: with conn: ...` — outer for lifecycle, inner for transactions.
