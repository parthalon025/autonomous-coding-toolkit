# Lesson: sed Range Deletion is Unbounded When the End Pattern Is Absent (Last Section)

**Date:** 2026-02-28
**System:** autonomous-coding-toolkit
**Tier:** lesson
**Category:** bash
**Keywords:** sed, range deletion, unbounded, last section, awk, EOF, data loss, regex range, CLAUDE.md
**Files:** scripts/lib/run-plan-headless.sh

---

## Observation (What Happened)

`run-plan-headless.sh` used a sed address range to delete the `## Run-Plan:` section from `CLAUDE.md`:

```bash
sed '/^## Run-Plan:/,/^## [^R]/{ /^## [^R]/!d; }' "$claude_md" > "$tmp"
```

When `## Run-Plan:` is the LAST section in the file, the range never finds a closing `^## [^R]` header. sed's range semantics are: if the closing pattern is never found, the range extends to EOF. Everything from `## Run-Plan:` to the end of the file is silently deleted. The content is irrecoverably lost on the next atomic write (#4).

## Analysis (Root Cause — 5 Whys)

**Why #1:** sed address ranges `/start/,/end/` are unbounded — if `end` never matches, the range consumes everything to EOF.
**Why #2:** The developer assumed CLAUDE.md always has another `##` section after `Run-Plan:`, which is not enforced.
**Why #3:** The data loss is silent — `sed` exits 0, the `> "$tmp"` write succeeds, and the atomic `mv` completes without error.
**Why #4:** sed is a poor tool for structured section deletion because it has no concept of "end of section implies EOF is also valid end" — it just runs open ranges to the end of file.

## Corrective Actions

| # | Action | Status | Owner | Evidence |
|---|--------|--------|-------|----------|
| 1 | Replace sed with awk for section deletion — awk allows explicit state tracking with an EOF guard: `awk '/^## Run-Plan:/{skip=1} skip && /^## / && !/^## Run-Plan:/{skip=0} !skip{print}'` | proposed | Justin | issue #4 |
| 2 | If sed must be used, append a sentinel line before processing and remove it after: `echo "## SENTINEL" >> "$claude_md"; sed ...; remove sentinel` | proposed | Justin | — |
| 3 | General rule: never use sed `/pattern1/,/pattern2/d` on a file where the closing pattern might not exist — always verify with awk's explicit state machine | proposed | Justin | — |
| 4 | Add a test case where the target section is the last section in the file | proposed | Justin | — |

## Key Takeaway

sed `/start/,/end/` ranges extend to EOF when the end pattern is absent — never use sed range deletion on structured files unless you can guarantee the closing pattern always exists; use awk with explicit state tracking instead.
