---
id: 14
title: "Decorator registries are import-time side effects"
severity: should-fix
languages: [python]
scope: [language:python]
category: silent-failures
pattern:
  type: semantic
  description: "Decorator-based registry remains empty because module with decorated functions is never imported"
fix: "Ensure all modules with registrations are imported in __init__.py or an explicit loader"
example:
  bad: |
    # handlers.py
    @register("command")
    def handle_command(): pass

    # main.py
    # registry.get_all() returns empty — handlers.py was never imported
    from registry import registry
    for handler in registry.get_all():  # Empty!
        handler()
  good: |
    # handlers.py (same as above)
    @register("command")
    def handle_command(): pass

    # main.py
    # Explicitly import to trigger decorators
    from . import handlers  # This runs the decorators
    from registry import registry
    for handler in registry.get_all():  # Has handlers now
        handler()
---

## Observation
A Python project uses decorator-based registration (`@register("name")` adds a function to a registry). The registry is empty at runtime even though decorated functions exist in the codebase. No error is raised — the registry just returns an empty list.

## Insight
Decorator-based registries execute at import time. If the module containing decorated functions is never imported (perhaps `main.py` only imports specific modules), the decorators never run and the registry stays empty. The mistake is assuming the module will be imported implicitly, when it must be imported explicitly.

## Lesson
Decorator-based registries require explicit imports of all modules that have decorated functions. Add imports to `__init__.py` or a loader module that's guaranteed to run. Document this requirement. Alternatively, use a registration function that's called explicitly, instead of relying on import-time side effects. Never assume a module is imported — always be explicit.
