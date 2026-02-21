---
id: 0038
title: "Subscribe without stored ref = cannot unsubscribe"
severity: should-fix
languages: [python, javascript]
category: resource-lifecycle
pattern:
  type: syntactic
  regex: "\.subscribe\(lambda|\.subscribe\(\s*\("
  description: "Event subscription with anonymous lambda cannot be unsubscribed later"
fix: "Store callback on self before subscribing; unsubscribe with stored ref in shutdown"
example:
  bad: |
    def __init__(self):
        self.emitter.subscribe(lambda event: self.on_event(event))

    def shutdown(self):
        # No way to unsubscribe -- callback ref lost
  good: |
    def __init__(self):
        self._callback = lambda event: self.on_event(event)
        self.emitter.subscribe(self._callback)

    def shutdown(self):
        self.emitter.unsubscribe(self._callback)
---

## Observation
Event subscriptions created with inline lambdas or anonymous functions cannot be unsubscribed later because the callback reference is not stored. In shutdown or cleanup code, there's no way to reference the callback to remove it.

## Insight
The subscriber pattern returns a reference to the callback if you need to unsubscribe later. When the callback is created inline and not stored, that reference is lost immediately after subscription.

## Lesson
Always store event callbacks on `self` before subscribing. Unsubscribe using the stored reference in `shutdown()` or cleanup methods. Test that subscriptions are properly cleaned up and no callbacks fire after shutdown. This prevents memory leaks and stale event handlers.
