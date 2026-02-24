---
id: 30
title: "Cache/registry updates must merge, never replace"
severity: should-fix
languages: [python, javascript, all]
scope: [universal]
category: integration-boundaries
pattern:
  type: semantic
  description: "Cache update replaces entire cache instead of merging, losing entries from other modules"
fix: "Use cache.update(new_entries) not cache = new_entries"
example:
  bad: |
    # Module A
    cache = {'user:1': 'Alice'}

    # Module B updates cache
    def refresh_posts():
        posts = fetch_posts()
        cache = {'post:1': 'Hello'}  # Replaces entire cache!
        # user:1 lost

    # Now cache only has posts, users are gone
  good: |
    # Shared cache object
    cache = {}

    # Module B updates cache (merge, don't replace)
    def refresh_posts():
        posts = fetch_posts()
        cache.update({f'post:{p.id}': p for p in posts})
        # All previous entries preserved

    # Cache has both users and posts
---

## Observation

When multiple modules access a shared cache, replacing it from one module loses entries written by others. A refresh operation in Module B that replaces the cache erases data from Module A that's still valid.

## Insight

Cache semantics depend on ownership. If the cache is owned by one module, that module can replace it. If it's shared, updates must be additive or selective. Replacement (assignment) assumes sole ownership; without it, you lose data from other modules.

## Lesson

When updating a shared cache or registry:

1. **Merge, don't replace**: Use `cache.update()` (Python dict), `Object.assign()` (JavaScript), or similar. Never reassign the cache variable.
2. **Selective update**: If you need to replace specific keys, use `cache.pop(key)` then `cache[key] = value`, or `cache.update({key: value})`.
3. **TTL/expiry**: For caches with stale data, use timestamps or TTLs instead of wholesale replacement. Stale entries expire; fresh entries remain.
4. **Ownership**: Document which module owns the cache. If multiple modules write to it, document the contract: "All posts keys start with `post:`, all user keys start with `user:`. Modules only touch their namespace."

Example of selective update:

```python
# Only replace posts, keep other entries
posts_dict = {f'post:{p.id}': p for p in new_posts}
cache.update(posts_dict)  # user:1 and user:2 still there
```

Test this by simulating concurrent updates and verifying data from both modules persists.
