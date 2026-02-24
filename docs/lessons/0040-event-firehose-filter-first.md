---
id: 0040
title: "Process all events when 5% are relevant -- filter first"
severity: should-fix
languages: [all]
scope: [domain:ha-aria]
category: performance
pattern:
  type: semantic
  description: "Event handler processes every event when only a small fraction are relevant"
fix: "Filter by domain/type/source at the top of the handler before any expensive operations"
example:
  bad: |
    def on_event(self, event):
        # Processes every event, even irrelevant ones
        parsed = expensive_parse(event)
        if parsed.domain != "target_domain":
            return
        self.handle_target(parsed)
  good: |
    def on_event(self, event):
        if event.domain != "target_domain":
            return
        # Only expensive parse for relevant events
        parsed = expensive_parse(event)
        self.handle_target(parsed)
---

## Observation
Event handlers receive high-volume event streams (e.g., Home Assistant state_changed, MQTT topic subscriptions). Filtering happens after expensive operations (parsing, decoding, database lookups) instead of before, wasting CPU on irrelevant events.

## Insight
Early filtering is a free optimization. Checking a simple field (`event.type`, `event.domain`) takes nanoseconds. Do this first, return immediately for irrelevant events, then proceed with expensive operations only for matching events.

## Lesson
Filter events at the very top of the handler using simple field checks before any expensive operations. Structure the filter to reject irrelevant events as quickly as possible. If filtering becomes complex, move it to a decorator or middleware layer. Test with high event volume (1000s/sec) to verify performance doesn't degrade.
