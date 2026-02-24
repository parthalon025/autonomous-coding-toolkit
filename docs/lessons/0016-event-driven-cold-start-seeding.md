---
id: 16
title: "Event-driven systems must seed current state on startup"
severity: should-fix
languages: [python, javascript, all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Event-driven system produces empty/wrong output on first boot before any events arrive"
fix: "On startup, seed current state by fetching a snapshot via REST/query before subscribing to events"
example:
  bad: |
    # WebSocket event-driven system
    class Dashboard:
        def __init__(self):
            self.users = []  # Empty on startup!

        def on_event(self, event):
            if event.type == "user_join":
                self.users.append(event.user)

    # On first boot, dashboard is empty until first user joins
  good: |
    # Seed current state on startup
    class Dashboard:
        def __init__(self):
            self.users = []
            # Fetch current state before subscribing to events
            self.users = api.get_all_users()  # Seed!

        def on_event(self, event):
            if event.type == "user_join":
                self.users.append(event.user)
---

## Observation
An event-driven system (e.g., WebSocket, MQTT, event stream) maintains state by processing events. On startup, before any events arrive, the system has no state. It produces an empty result, wrong result, or waits until an event triggers. Users see an empty dashboard or broken state until the first event.

## Insight
The root cause is treating events as the only state source. Events represent *changes*, not current state. In steady state, events keep the system up-to-date. But on first boot, there's no baseline — the system must fetch current state separately before subscribing to changes.

## Lesson
Event-driven systems must seed current state on startup. Before subscribing to events, fetch a snapshot (via REST API, database query, or cache) to populate initial state. Then subscribe to events to handle incremental changes. This ensures the system has correct state from the first moment it's needed, not after the first event.
