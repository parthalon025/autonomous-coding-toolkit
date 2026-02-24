---
id: 12
title: "API rejects markdown with unescaped special chars"
severity: nice-to-have
languages: [python, javascript, all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Message API rejects text containing unescaped markdown special characters"
fix: "Either escape all special characters or use plain text mode as default with markdown as opt-in"
example:
  bad: |
    # Message with unescaped markdown chars
    message = "Task: _compile_flags = ['-O2', '-Wall']"
    response = api.send_message(message, parse_mode="Markdown")
    # API rejects: parse error due to _ chars
  good: |
    # Either escape special chars
    message = "Task: \\_compile\\_flags = ['-O2', '-Wall']"
    response = api.send_message(message, parse_mode="Markdown")
    # Or use plain text by default
    response = api.send_message(message)  # parse_mode=None
---

## Observation
An API with `parse_mode=Markdown` rejects messages containing unescaped special characters like `_`, `*`, `[`, `]`. The message silently fails or returns a parse error. Code that works with one message format fails with another that contains these characters.

## Insight
The root cause is assuming plain text is safe to send with markdown parsing enabled. Markdown interpreters are strict — any `_` or `*` is interpreted as formatting syntax. If the text literally needs to include these characters (like code snippets or file paths), they must be escaped or the parser must be disabled.

## Lesson
When sending messages to APIs with markdown parsing, either: (1) escape all special characters (`_`, `*`, `[`, `]`, `` ` ``) in the text, or (2) use plain text mode by default and require opt-in for markdown. Never assume plain text is safe with markdown parsing enabled.
