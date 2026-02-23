#!/usr/bin/env bash
# ollama.sh — Shared Ollama API interaction for Code Factory scripts
#
# Requires: common.sh sourced first (for strip_json_fences)
#
# Functions:
#   ollama_build_payload <model> <prompt>  -> JSON payload string
#   ollama_parse_response                  -> stdin filter: extract .response from Ollama JSON
#   ollama_extract_json                    -> stdin filter: parse response, strip fences, validate JSON
#   ollama_query <model> <prompt>          -> full query: build payload, call API, return response text
#   ollama_query_json <model> <prompt>     -> full query + JSON extraction

OLLAMA_DIRECT_URL="${OLLAMA_DIRECT_URL:-http://localhost:11434}"
OLLAMA_QUEUE_URL="${OLLAMA_QUEUE_URL:-http://localhost:7683}"

ollama_build_payload() {
    local model="$1" prompt="$2"
    jq -n --arg model "$model" --arg prompt "$prompt" \
        '{model: $model, prompt: $prompt, stream: false}'
}

ollama_parse_response() {
    jq -r '.response // empty'
}

ollama_extract_json() {
    local text
    text=$(cat)
    # Strip fences
    text=$(echo "$text" | strip_json_fences)
    # Validate JSON
    if echo "$text" | jq . >/dev/null 2>&1; then
        echo "$text"
    else
        echo "WARNING: ollama_extract_json: invalid JSON in response" >&2
        echo ""
    fi
}

ollama_query() {
    local model="$1" prompt="$2"
    local payload api_url response

    payload=$(ollama_build_payload "$model" "$prompt")

    # Prefer queue if available
    if curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "$OLLAMA_QUEUE_URL/health" 2>/dev/null | grep -q "200"; then
        api_url="$OLLAMA_QUEUE_URL/api/generate"
    else
        api_url="$OLLAMA_DIRECT_URL/api/generate"
    fi

    response=$(curl -s "$api_url" -d "$payload" --max-time 300)
    echo "$response" | ollama_parse_response
}

ollama_query_json() {
    local model="$1" prompt="$2"
    ollama_query "$model" "$prompt" | ollama_extract_json
}
