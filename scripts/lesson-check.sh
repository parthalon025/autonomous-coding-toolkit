#!/usr/bin/env bash
# lesson-check.sh — Syntactic anti-pattern detector from lessons learned
# Checks for top 5 anti-patterns that caused real data loss or multi-hour debugging.
# Exit 0 if clean, exit 1 with file:line: [lesson-N] format if violations found.
set -euo pipefail

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<'USAGE'
Usage: lesson-check.sh [file ...]
  Check files for known anti-patterns from lessons learned.
  Files can be passed as arguments or piped via stdin (one per line).
  If neither, defaults to git diff --name-only in current directory.

Checks:
  [lesson-7]  bare except without logging (.py only)
  [lesson-25] async def without await (.py only)
  [lesson-43] create_task without add_done_callback (.py only)
  [lesson-12] hub.cache. direct access (.py only)
  [lesson-55] singular HA automation key access without plural check (.py, automation files only)
  [lesson-51] .venv/bin/pip instead of .venv/bin/python -m pip (all files)

Output: file:line: [lesson-N] description
Exit:   0 if clean, 1 if violations found
USAGE
    exit 0
fi

violations=0

# Gather file list
files=()
if [[ $# -gt 0 ]]; then
    files=("$@")
elif [[ ! -t 0 ]]; then
    while IFS= read -r f; do
        [[ -n "$f" ]] && files+=("$f")
    done
else
    while IFS= read -r f; do
        [[ -n "$f" ]] && files+=("$f")
    done < <(git diff --name-only 2>/dev/null || true)
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "lesson-check: no files to check" >&2
    exit 0
fi

# Separate Python files from all files
py_files=()
all_files=()
for f in "${files[@]}"; do
    [[ ! -f "$f" ]] && continue
    all_files+=("$f")
    [[ "$f" == *.py ]] && py_files+=("$f")
done

# --- Check #1: bare except without logging (lesson-7) ---
# --- Check #2: async def without await (lesson-25) ---
# --- Check #3: create_task without add_done_callback (lesson-43) ---
# All three multi-line checks done in a single awk pass per file for speed.
for f in "${py_files[@]}"; do
    while IFS= read -r finding; do
        echo "$finding"
        ((violations++)) || true
    done < <(awk '
    # Check 1: bare except without logging in next 3 lines
    /^[[:space:]]*except[[:space:]]*:/ || /^[[:space:]]*except[[:space:]]+Exception[[:space:]]*:/ || /^[[:space:]]*except[[:space:]]+Exception[[:space:]]+as[[:space:]]/ {
        except_line = NR
        except_lookahead = 3
    }
    except_lookahead > 0 && NR > except_line {
        if ($0 ~ /logger\.|logging\.|log\.|print\(/) {
            except_lookahead = 0
        } else {
            except_lookahead--
            if (except_lookahead == 0) {
                printf "%s:%d: [lesson-7] bare except without logging in next 3 lines\n", FILENAME, except_line
            }
        }
    }

    # Check 2: async def without await — track function boundaries by indent
    /^[[:space:]]*async[[:space:]]+def[[:space:]]/ {
        # If we had a pending async def with no await, report it
        if (async_def_line > 0 && !found_await) {
            printf "%s:%d: [lesson-25] async def without await\n", FILENAME, async_def_line
        }
        async_def_line = NR
        found_await = 0
        # Measure indent: count leading spaces
        match($0, /^[[:space:]]*/)
        async_def_indent = RLENGTH
    }
    # A non-async def at same or lesser indent ends the current async function
    async_def_line > 0 && NR > async_def_line && /^[[:space:]]*(async[[:space:]]+)?def[[:space:]]/ {
        match($0, /^[[:space:]]*/)
        if (RLENGTH <= async_def_indent && NR != async_def_line) {
            if (!found_await) {
                printf "%s:%d: [lesson-25] async def without await\n", FILENAME, async_def_line
            }
            # If this new line is also async def, it was already handled above
            if ($0 ~ /^[[:space:]]*async[[:space:]]+def[[:space:]]/) {
                # already set above
            } else {
                async_def_line = 0
                found_await = 0
            }
        }
    }
    # Check for await/async for/async with inside async function body
    async_def_line > 0 && NR > async_def_line && !found_await {
        if ($0 ~ /await[[:space:]]/ || $0 ~ /await\(/ || $0 ~ /async[[:space:]]+for/ || $0 ~ /async[[:space:]]+with/) {
            found_await = 1
        }
    }

    # Check 3: create_task without add_done_callback in next 5 lines
    /create_task\(/ {
        ct_line = NR
        ct_lookahead = 5
    }
    ct_lookahead > 0 && NR > ct_line {
        if ($0 ~ /add_done_callback/) {
            ct_lookahead = 0
        } else {
            ct_lookahead--
            if (ct_lookahead == 0) {
                printf "%s:%d: [lesson-43] create_task without add_done_callback within 5 lines\n", FILENAME, ct_line
            }
        }
    }

    END {
        # Final async def at EOF
        if (async_def_line > 0 && !found_await) {
            printf "%s:%d: [lesson-25] async def without await\n", FILENAME, async_def_line
        }
    }
    ' "$f" 2>/dev/null || true)
done

# --- Check #4: hub.cache. direct access (lesson-12) ---
if [[ ${#py_files[@]} -gt 0 ]]; then
    while IFS=: read -r f lineno _; do
        echo "$f:$lineno: [lesson-12] direct hub.cache. access — use hub.set_cache()/hub.get_cache()"
        ((violations++)) || true
    done < <(grep -Hn 'hub\.cache\.' "${py_files[@]}" 2>/dev/null || true)
fi

# --- Check #5: HA automation singular-only key access (lesson-55) ---
# Detects .get("trigger") or ["trigger"] without also checking "triggers" nearby.
# Only flags in files that deal with HA automations (shadow, comparison, template).
for f in "${py_files[@]}"; do
    # Only check files likely dealing with HA automation dicts
    case "$f" in
        *shadow*|*comparison*|*automation*|*template*|*candidate*) ;;
        *) continue ;;
    esac
    while IFS= read -r finding; do
        echo "$finding"
        ((violations++)) || true
    done < <(awk '
    /\[["'"'"']trigger["'"'"']\]/ || /\.get\(["'"'"']trigger["'"'"']/ {
        printf "%s:%d: [lesson-55] singular HA key access — check both trigger/triggers\n", FILENAME, NR
    }
    /\[["'"'"']action["'"'"']\]/ || /\.get\(["'"'"']action["'"'"']/ {
        printf "%s:%d: [lesson-55] singular HA key access — check both action/actions\n", FILENAME, NR
    }
    /\[["'"'"']condition["'"'"']\]/ || /\.get\(["'"'"']condition["'"'"']/ {
        printf "%s:%d: [lesson-55] singular HA key access — check both condition/conditions\n", FILENAME, NR
    }
    ' "$f" 2>/dev/null || true)
done

# --- Check #6: .venv/bin/pip instead of .venv/bin/python -m pip (lesson-51) ---
if [[ ${#all_files[@]} -gt 0 ]]; then
    while IFS=: read -r f lineno line; do
        # Skip lines that use the correct form
        [[ "$line" == *".venv/bin/python -m pip"* ]] && continue
        [[ "$line" == *".venv/bin/python3 -m pip"* ]] && continue
        echo "$f:$lineno: [lesson-51] .venv/bin/pip — use .venv/bin/python -m pip instead"
        ((violations++)) || true
    done < <(grep -Hn '\.venv/bin/pip' "${all_files[@]}" 2>/dev/null || true)
fi

# Summary
if [[ $violations -gt 0 ]]; then
    echo ""
    echo "lesson-check: $violations violation(s) found"
    exit 1
else
    echo "lesson-check: clean"
    exit 0
fi
