# ARCHIVED — Do Not Use These Files Directly

These lesson markdown files have been migrated into the lessons-db SQLite database.

**Always use the `lessons-db` CLI instead:**

```bash
lessons-db search "your query"          # semantic search
lessons-db status                       # DB health + counts
lessons-db scan --target .              # run Semgrep rules derived from lessons
lessons-db export <id>                  # export a lesson back to markdown if needed
```

DB location: `~/.local/share/lessons-db/lessons.db`

Files here are kept for historical reference only. The DB is the authoritative source.
Migrated: 2026-02-28
