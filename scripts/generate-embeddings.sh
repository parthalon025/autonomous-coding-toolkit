#!/usr/bin/env bash
GENERATE="$(command -v generate-embeddings 2>/dev/null || echo "$HOME/.local/bin/generate-embeddings")"
[ -x "$GENERATE" ] && exec "$GENERATE" "$@" || { echo "generate-embeddings not found"; exit 1; }
