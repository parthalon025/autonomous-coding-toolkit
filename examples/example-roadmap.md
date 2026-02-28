# Roadmap: User Management System

Generated: 2026-02-24

## Features (dependency order)

### Phase 1: Foundation
| # | Feature | Complexity | Risk | Dependencies |
|---|---------|-----------|------|-------------|
| 1 | Database schema and migrations | moderate | low | none |
| 2 | Authentication API (JWT) | moderate | medium | none |

### Phase 2: Core
| # | Feature | Complexity | Risk | Dependencies |
|---|---------|-----------|------|-------------|
| 3 | User CRUD endpoints | moderate | low | #1 |
| 4 | Role-based access control | complex | medium | #2, #3 |

### Phase 3: Polish
| # | Feature | Complexity | Risk | Dependencies |
|---|---------|-----------|------|-------------|
| 5 | Admin dashboard UI | moderate | low | #3, #4 |

## Dependency Graph
```
1 ──→ 3 ──→ 4 ──→ 5
2 ──────→ 4
```

## Milestone Criteria

### Phase 1 Complete
- `pytest tests/test_schema.py -q` exits 0 (migrations run clean)
- `curl -s localhost:8080/api/auth/token -d '{"user":"test","pass":"test"}' | jq -e '.token'` exits 0
- No hardcoded credentials: `git grep -i "password\s*=" -- '*.py' | grep -v test` is empty

### Phase 2 Complete
- All Phase 1 criteria still pass
- `pytest tests/test_users.py tests/test_auth.py -q` exits 0
- RBAC enforces role boundaries: `pytest tests/test_rbac.py -q` exits 0

### Phase 3 Complete
- All Phase 1 and 2 criteria still pass
- `npm run build` exits 0 (dashboard builds without error)
- `playwright test tests/e2e/admin.spec.ts` exits 0 (end-to-end admin flow passes)

## Total Estimate
- Features: 5
- Phases: 3
- Estimated sessions: 5-8
