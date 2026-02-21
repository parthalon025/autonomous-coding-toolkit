---
id: 32
title: "Module lifecycle: subscribe after init gate, unsubscribe on shutdown"
severity: should-fix
languages: [python, javascript]
category: resource-lifecycle
pattern:
  type: semantic
  description: "Component subscribes to events in constructor but never unsubscribes on shutdown"
fix: "Subscribe in initialize() after startup gate, store callback ref on self, unsubscribe in shutdown()"
example:
  bad: |
    class EventListener:
        def __init__(self):
            self.event_bus = get_event_bus()
            self.event_bus.subscribe('user_login', self.on_login)
            # subscribe in __init__, no unsubscribe
            self.callback_ref = None  # Lost reference

        def on_login(self, event):
            print(f"User {event.user} logged in")

        # No shutdown method, so callback never unsubscribed
  good: |
    class EventListener:
        def __init__(self):
            self.event_bus = None
            self.callback_ref = None

        async def initialize(self):
            self.event_bus = await get_event_bus()
            self.callback_ref = self.on_login
            self.event_bus.subscribe('user_login', self.callback_ref)

        def on_login(self, event):
            print(f"User {event.user} logged in")

        async def shutdown(self):
            if self.callback_ref:
                self.event_bus.unsubscribe('user_login', self.callback_ref)
                self.callback_ref = None
---

## Observation

Components subscribe to events in constructors but rarely unsubscribe. On shutdown, stale callbacks remain registered and continue firing, creating memory leaks and ghost events.

## Insight

Constructors are for initialization; cleanup is for shutdown. Mixing them violates the resource lifecycle principle. A callback registered in `__init__` may outlive the component because nothing explicitly removes it.

## Lesson

Follow this subscription lifecycle:

1. **Separate init/shutdown**: Never subscribe in `__init__`. Use an explicit `initialize()` method.
2. **Store callback reference**: Keep a reference to the callback on `self` so you can unsubscribe later.
3. **Unsubscribe on shutdown**: In `shutdown()`, unsubscribe and set callback to None.

Pattern:

```python
class Component:
    def __init__(self):
        self.event_bus = None
        self.on_event_callback = None

    async def initialize(self):
        self.event_bus = await get_event_bus()
        self.on_event_callback = self.on_event  # Store ref
        self.event_bus.subscribe('event_type', self.on_event_callback)

    def on_event(self, event):
        # Handle event

    async def shutdown(self):
        if self.on_event_callback:
            self.event_bus.unsubscribe('event_type', self.on_event_callback)
            self.on_event_callback = None
```

Test this by:
1. Create component
2. Verify callback is registered (count subscribers)
3. Shutdown component
4. Fire event, verify callback doesn't fire (or count unchanged)

This pattern is critical for long-running services where components are created and destroyed repeatedly.
