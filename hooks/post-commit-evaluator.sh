#!/usr/bin/env bash
# post-commit-evaluator.sh — Records heeded/recurrence outcomes for recently surfaced lessons.
# Called from hooks/post-commit after the lesson auto-import step.
# Gracefully no-ops if lessons-db is unavailable.
set -euo pipefail

LESSONS_DB=$(command -v lessons-db 2>/dev/null || true)
if [[ -z "${LESSONS_DB}" ]]; then
    exit 0
fi

# Get lessons surfaced in the last 6 hours (covering current session)
SURFACED_IDS=$("${LESSONS_DB}" learn list --since 6h --format ids 2>/dev/null || true)
if [[ -z "${SURFACED_IDS}" ]]; then
    exit 0
fi

# Get the diff of the current commit (content lines only, no metadata)
DIFF=$(git diff HEAD~1 2>/dev/null || true)
if [[ -z "${DIFF}" ]]; then
    exit 0
fi

# Write diff to temp file for lessons-db check
DIFF_TMP=$(mktemp)
trap 'rm -f "${DIFF_TMP}"' EXIT
printf '%s\n' "${DIFF}" > "${DIFF_TMP}"

# Capture commit subject once (reused in the loop)
COMMIT_SUBJECT=$(git log -1 --format='%s' 2>/dev/null || true)
COMMIT_SUBJECT=${COMMIT_SUBJECT:-commit}

while IFS= read -r lesson_id; do
    [[ -z "${lesson_id}" ]] && continue

    # Check if any lesson patterns appear in the diff
    VIOLATIONS=$("${LESSONS_DB}" check --files "${DIFF_TMP}" 2>/dev/null || true)

    if [[ -n "${VIOLATIONS}" ]]; then
        # Pattern found in diff — lesson was NOT applied (recurrence)
        "${LESSONS_DB}" learn record \
            --lesson-id "${lesson_id}" \
            --hook "commit" \
            --context "${COMMIT_SUBJECT}" \
            --outcome "recurrence" \
            2>>/tmp/lessons-db-errors.log || true
    else
        # Pattern absent from diff — lesson was applied (heeded)
        "${LESSONS_DB}" learn record \
            --lesson-id "${lesson_id}" \
            --hook "commit" \
            --context "${COMMIT_SUBJECT}" \
            --outcome "heeded" \
            2>>/tmp/lessons-db-errors.log || true
    fi
done <<< "${SURFACED_IDS}"

exit 0
