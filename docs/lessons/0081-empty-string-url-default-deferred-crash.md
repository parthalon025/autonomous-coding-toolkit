---
id: "0081"
title: "Empty string URL default crashes at call time, not definition time"
severity: blocker
languages: [python]
category: silent-failures
pattern:
  type: syntactic
  regex: "def \\w+\\([^)]*url\\w*\\s*:\\s*str\\s*=\\s*\"\"[^)]*\\)"
  description: >
    A function parameter typed as `str` with a default of `""` is used to
    construct a URL (e.g. `f"{url}/api/generate"`). The empty string produces
    a relative path like `"/api/generate"`, which passes the type check and
    linting but raises `ValueError: unknown url type` at runtime when passed
    to urllib or requests. The bug is invisible until the function is actually
    called without the parameter.
fix: >
    Default URL parameters to the real sentinel value, not an empty string.
    Import the config constant and use it as the default:
    `ollama_url: str = OLLAMA_QUEUE_URL`. If no sensible default exists,
    make the parameter required (no default) so callers are forced to
    provide a value. Never use `""` as a URL default.
example:
  bad: |
    # Passes linting and type checks. Crashes at runtime if called without arg.
    def call_judge(
        prompt: str,
        ollama_url: str = "",       # empty string looks fine
        ollama_model: str = "",
    ) -> str | None:
        req = urllib.request.Request(
            f"{ollama_url}/api/generate",   # produces "/api/generate"
            ...
        )
        # raises: ValueError: unknown url type: '/api/generate'
  good: |
    from mypackage.config import OLLAMA_QUEUE_URL

    def call_judge(
        prompt: str,
        ollama_url: str = OLLAMA_QUEUE_URL,  # real default, never empty
        ollama_model: str = "",
    ) -> str | None:
        req = urllib.request.Request(
            f"{ollama_url}/api/generate",    # http://127.0.0.1:7683/api/generate
            ...
        )
---

## Observation

An eval pipeline function `call_judge()` had `ollama_url: str = ""` as a default
parameter. All callers in production passed the URL explicitly, so the bug was
latent. A test that called the function without the parameter (relying on the
default) got `ValueError: unknown url type: '/api/generate'` from `urllib`.
The error masked a different test's assertion failure, making two tests appear
broken for unrelated reasons until the root cause was traced back to the default.

## Insight

Python evaluates default parameter values at *function definition time*, not call
time. An empty string is a valid `str`, so no type error is raised. The URL
construction `f"{url}/api/generate"` silently produces `"/api/generate"` — a
string with no scheme or host. urllib's `urlopen` only accepts absolute URLs
(`http://...`) and raises `ValueError` on relative ones. The failure happens deep
in the call stack, far from the default that caused it.

The same pattern appears in requests, httpx, and aiohttp — they all require an
absolute URL scheme.

## Lesson

URL parameters must never default to `""`. Either:
1. Import the real config constant and use it as the default (preferred — works in
   all call sites including tests).
2. Make the parameter required with no default, forcing every caller to be explicit.

When reviewing function signatures, treat `url: str = ""` as a linting error. The
string `""` is structurally valid but semantically broken for any URL-consuming
parameter.
