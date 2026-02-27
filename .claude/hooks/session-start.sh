#!/bin/bash
set -euo pipefail

# Only run on Claude Code web sessions
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Install dependencies (cached after first run)
npm install
