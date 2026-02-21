---
id: 35
title: "Duplicate registration IDs cause silent overwrite"
severity: should-fix
languages: [python, javascript, all]
category: silent-failures
pattern:
  type: semantic
  description: "Multiple components register with the same ID, last one silently overwrites earlier ones"
fix: "Check for existing registration before inserting; log warning or raise on duplicate"
example:
  bad: |
    class HandlerRegistry:
        def __init__(self):
            self.handlers = {}

        def register(self, handler_id, handler):
            self.handlers[handler_id] = handler  # Silently overwrites

    registry = HandlerRegistry()
    registry.register('payment', PaymentHandler())
    registry.register('payment', StripeHandler())  # Oops, overwrites first one
    # Now only Stripe handler is registered, PaymentHandler is lost

    registry.handle('payment', data)  # Only StripeHandler runs
  good: |
    class HandlerRegistry:
        def __init__(self):
            self.handlers = {}

        def register(self, handler_id, handler):
            if handler_id in self.handlers:
                raise ValueError(f"Handler '{handler_id}' already registered")
            self.handlers[handler_id] = handler

    registry = HandlerRegistry()
    registry.register('payment', PaymentHandler())
    registry.register('payment', StripeHandler())  # Raises ValueError
    # Bug caught immediately
---

## Observation

Registries that accept duplicate IDs silently overwrite earlier registrations. A second module registering with the same ID erases the first module's handler, and there's no error.

## Insight

Registries are designed to prevent collisions: each ID maps to one handler. Without collision detection, the register operation becomes a silent update, and duplicate IDs are indistinguishable from intentional overwrites.

## Lesson

When building a registration system (event handlers, plugins, middleware):

1. **Check for duplicates**: Before inserting, verify the ID isn't already registered.
2. **Three options on duplicate**:
   - **Reject** (strict): Raise an exception. Fails fast, prevents bugs.
   - **Warn** (permissive): Log a warning, then overwrite. Allows dynamic reconfiguration but can mask bugs.
   - **Append** (list-based): If multiple handlers per ID are valid, use a list instead of a dict.

Pattern:

```python
def register(self, handler_id, handler):
    if handler_id in self.handlers:
        raise ValueError(f"Duplicate registration: '{handler_id}'")
    self.handlers[handler_id] = handler
```

Or with warning:

```python
def register(self, handler_id, handler):
    if handler_id in self.handlers:
        logger.warning(f"Overwriting handler '{handler_id}'")
    self.handlers[handler_id] = handler
```

Test by:
1. Register handler A with ID 'foo'
2. Register handler B with ID 'foo'
3. Verify exception is raised OR warning is logged
4. Verify the correct handler is in the registry afterward

Choose **reject** (strict) by default unless dynamic reconfiguration is explicitly required.
