# Research: Comprehensive Testing Strategies for Large Full-Stack Projects

> **Date:** 2026-02-22
> **Status:** Research complete
> **Method:** Web research + academic literature + tool analysis
> **Confidence:** High on tool comparisons and testing shapes; medium on AI test generation (rapidly evolving field); high on quality gate enhancement proposals (grounded in toolkit architecture)

## Executive Summary

The autonomous-coding-toolkit treats testing as a monolithic step: auto-detect `pytest`/`npm test`/`make test`, run it, enforce monotonic test counts. This works for single-layer projects but breaks down for full-stack applications with backends, frontends, UI/UX, and cross-cutting concerns. This paper synthesizes current evidence on testing strategy, tool selection, and AI-generated test quality to produce actionable recommendations for enhancing the toolkit.

**Key findings:**

1. **No single "right" test shape exists.** The pyramid works for backend-heavy logic; the trophy works for frontend integration; the honeycomb works for microservices. The toolkit should recommend shapes per project type, not enforce one.
2. **AI-generated tests have systematic failure modes** — happy-path clustering, mock-heavy designs, tautological assertions, and 40% mutation kill rates. The toolkit needs specific quality checks for AI-written tests.
3. **Playwright has won the e2e tool war** — surpassing Cypress in downloads (June 2024), with superior cross-browser support, parallelization, and CI/CD integration.
4. **Mutation testing is the strongest predictor of test suite quality** — Google's study of 15M mutants shows coupling with real faults. Coverage percentage alone is a vanity metric after ~60-80%.
5. **Contract testing (Pact) fills the gap between unit and e2e** — critical for multi-service architectures that AI agents build across.
6. **The quality gate should become a layered system** — fast checks (lint, lesson-check), medium checks (unit + integration tests), slow checks (e2e, visual regression, security scans), with different layers running at different frequencies.

---

## 1. Testing Pyramid vs. Trophy vs. Honeycomb

### Findings

Three dominant test distribution models compete in 2025-2026:

| Model | Origin | Distribution | Best For |
|-------|--------|-------------|----------|
| **Pyramid** | Mike Cohn, 2009 | 70% unit / 20% integration / 10% e2e | Backend-heavy, logic-dense codebases |
| **Trophy** | Kent C. Dodds, 2018 | Static > Unit (small) > Integration (largest) > E2E (small) | Frontend applications, React/Vue/Preact |
| **Honeycomb** | Spotify, ~2018 | Few unit / Many integration / Few e2e | Microservices architectures |

**The Pyramid** encodes a fundamental economic truth: a bug caught by a unit test costs $1; by integration test $10; by e2e $100; in production $1,000+. The 70-20-10 ratio optimizes for fast feedback and low maintenance.

**The Trophy** — Kent C. Dodds' principle: "Write tests. Not too many. Mostly integration." The rationale: modern tools (React Testing Library, Vitest) make integration tests nearly as fast as unit tests. Integration tests provide higher confidence per test because they verify the seams between units. Static analysis (TypeScript, ESLint) handles what used to require unit tests for type checking.

**The Honeycomb** — For microservices, individual units are trivially small. The complexity is in service-to-service communication. Integration tests at the boundary (contract tests, API tests) provide the most value.

### Evidence

Martin Fowler's 2021 analysis ("On the Diverse and Fantastical Shapes of Testing") concludes: "People love debating what percentage of which type of tests to write, but it's a distraction — nearly zero teams write expressive tests that establish clear boundaries, run quickly & reliably, and only fail for useful reasons." The shape matters less than the quality of individual tests.

The web.dev testing strategies guide from Google recommends a hybrid approach: pyramid structure for backend services (where logic dominates) and trophy approach for frontend applications (where integration dominates).

### Implications for the Toolkit

**Confidence: High.** The toolkit should not prescribe a single shape. Instead:

1. Detect project type (backend-only, frontend-only, full-stack, microservices)
2. Recommend the appropriate shape with target ratios
3. Track test distribution across layers (unit/integration/e2e counts separately)
4. Flag imbalances: "You have 200 unit tests but 0 integration tests — consider the testing trophy model"

**When AI writes the tests:** AI agents default to writing unit tests because they're self-contained. The toolkit should explicitly prompt for integration and e2e tests in later batches. Test-count monotonicity should track per-layer, not just total.

### Sources

- [Martin Fowler — On the Diverse and Fantastical Shapes of Testing](https://martinfowler.com/articles/2021-test-shapes.html)
- [Kent C. Dodds — Write tests. Not too many. Mostly integration.](https://kentcdodds.com/blog/write-tests)
- [Kent C. Dodds — The Testing Trophy](https://kentcdodds.com/blog/the-testing-trophy-and-testing-classifications)
- [web.dev — Pyramid or Crab? Find a testing strategy that fits](https://web.dev/articles/ta-strategies)
- [An Analysis of the Different "Test Shapes"](https://premiersoft.net/en/blog/an-analysis-of-the-different-test-shapes)

---

## 2. Backend Testing Strategies

### Findings

Backend testing spans multiple layers, each requiring distinct approaches:

**API Testing:**
- Supertest (Node.js), httpx/pytest (Python), REST Assured (Java) for HTTP endpoint testing
- Test the contract (status codes, response shapes, error formats) not the implementation
- Each endpoint needs: happy path, validation errors, auth failures, edge cases

**Database Testing:**
- **Transaction rollback** — wrap each test in a transaction, rollback after. Fast, but can't test commit-dependent behavior (triggers, constraints checked at commit time)
- **Test containers** — spin up a real database per test suite via Docker (Testcontainers library). Slower startup but tests real database behavior. Recommended for integration tests.
- **In-memory databases** (SQLite for PostgreSQL tests) are a common trap — behavior differs enough to miss real bugs. Avoid unless explicitly testing ORM logic only.

**Queue/Event Testing:**
- Test message producers and consumers independently
- Use in-memory message brokers for unit tests (fake implementations)
- Test at least one end-to-end message flow with a real broker in integration tests
- Assert on message shape (schema validation) and side effects (state changes)

**Service-to-Service Testing:**
- Contract testing (Pact) verifies that consumers and providers agree on API shape without running both services simultaneously (see Section 6)
- Wire mocks (WireMock, nock, responses) for simulating external service behavior
- Record-replay patterns for capturing real responses and replaying in tests

### Evidence

Microsoft's Engineering Fundamentals Playbook recommends consumer-driven contract testing as the primary strategy for service-to-service testing, with e2e tests reserved for critical user journeys only.

### Implications for the Toolkit

**Confidence: High.** The toolkit should:

1. Detect database presence (look for migration files, ORM config, docker-compose with db services) and recommend Testcontainers or transaction-rollback patterns
2. Detect message queues (Redis, RabbitMQ, Kafka config) and recommend schema validation tests
3. Include backend test templates in plan generation: "Batch N should include API contract tests for all new endpoints"

### Sources

- [Microsoft Engineering Fundamentals — CDC Testing](https://microsoft.github.io/code-with-engineering-playbook/automated-testing/cdc-testing/)
- [Neon — Database testing with fixtures and seeding](https://neon.com/blog/database-testing-with-fixtures-and-seeding)
- [Pact Docs — Introduction](https://docs.pact.io/)

---

## 3. Frontend Testing Strategies

### Findings

**React Testing Library (RTL)** remains the dominant approach in 2025-2026. Core principle: "The more your tests resemble the way your software is used, the more confidence they can give you."

**jsdom vs. Browser-Based Testing:**

| Aspect | jsdom (Jest/Vitest) | Real Browser (Playwright/Cypress) |
|--------|--------------------|---------------------------------|
| Speed | Fast (~1-5ms/test) | Slower (~50-200ms/test) |
| Fidelity | Approximate DOM | Real browser behavior |
| Layout/CSS | Not supported | Full support |
| API coverage | Subset of browser APIs | Complete |
| Best for | Component logic, state | Visual behavior, user flows |

**jsdom limitations are real:** JSDOM doesn't implement layout APIs, `IntersectionObserver`, `ResizeObserver`, or CSS computations. Tests pass in jsdom but fail in real browsers when code depends on these APIs. One practitioner documented multiple cases of "code relying on browser APIs that JSDOM has not implemented."

**Component Testing Approaches:**
- **Unit components** (pure, stateless): jsdom is sufficient — test inputs/outputs
- **Interactive components** (forms, dropdowns, modals): jsdom works if no layout dependency
- **Layout-dependent components** (infinite scroll, responsive): browser-based testing required
- **Full pages/routes**: integration tests in browser environment

**Snapshot Testing Verdict:** Consensus in 2025 is that snapshot tests provide low signal. They detect changes but don't verify correctness. Teams report "update snapshot" becoming a reflexive action rather than a review step. Inline snapshots for small, stable outputs are acceptable; full-component snapshots are not recommended.

**Storybook as Test Harness:**
Storybook 8.2+ supports component tests via the Vitest addon. The workflow: write stories (component states) -> add play functions (user interactions) -> assert outcomes. Stories serve triple duty: documentation, visual testing, interaction testing. Storybook's accessibility addon runs axe-core checks automatically on every story.

### Evidence

Playwright adoption reached 45.1% among QA professionals in 2025 with 94% retention rate. RTL download numbers remain dominant for React component testing. Atlassian research shows 80% code coverage as the optimal balance between thoroughness and overhead.

### Implications for the Toolkit

**Confidence: High.** The toolkit should:

1. For React/Preact/Vue projects, recommend the Trophy shape: static analysis (largest) > integration (large) > unit (medium) > e2e (small)
2. Detect Storybook and recommend interaction tests for component coverage
3. Warn against snapshot-heavy test suites: "Snapshot tests detected as >30% of test suite — consider replacing with assertion-based tests"
4. Include a jsdom-vs-browser decision in plan generation based on component type

### Sources

- [React Testing Library Docs](https://testing-library.com/docs/react-testing-library/intro/)
- [Storybook — How to test UIs](https://storybook.js.org/docs/writing-tests)
- [Storybook — Component Testing](https://storybook.js.org/blog/component-testing/)
- [BlackSheepCode — Why I've gone off React Testing Library](https://blacksheepcode.com/posts/why_ive_gone_off_react_testing_library)

---

## 4. UI/UX Testing

### Findings

**Visual Regression Testing Tools:**

| Tool | Type | Browser | Strength | Weakness |
|------|------|---------|----------|----------|
| **Percy** (BrowserStack) | SaaS | Multi-browser | AI Review Agent (40% fewer false positives, 3x faster review), full-page cross-browser | Cost ($) |
| **Chromatic** (Storybook) | SaaS | Chromium | Deep Storybook integration, component-level, fast CI | Storybook-only |
| **BackstopJS** | Open source | Chrome only | Free, full control, self-hosted | Single browser, maintenance burden |
| **Playwright visual comparisons** | Built-in | All browsers | No extra tooling, same test runner | No dashboard, raw pixel diff |

**2025 recommendation:** Use Chromatic for component-level visual testing (pairs with Storybook) and Percy for full-page cross-browser visual testing. BackstopJS for budget-constrained projects that only need Chrome coverage.

**Accessibility Testing:**

| Tool | Detection Rate | False Positives | Integration |
|------|---------------|-----------------|-------------|
| **axe-core** | Up to 57% of WCAG issues | ~0% (zero false positive policy) | Jest, Playwright, Storybook addon |
| **Pa11y** | Different subset than axe | Low | CLI, CI-native (pa11y-ci) |
| **Lighthouse** | General audits (uses axe-core internally) | Low | CLI, CI |

**Critical insight:** Automated accessibility testing catches only 30-40% of WCAG issues. Manual testing remains essential for keyboard navigation flows, screen reader behavior, and cognitive accessibility. axe-core and Pa11y find different issues — use both for maximum automated coverage.

**Responsive Testing:** Playwright's viewport API handles responsive testing natively. Test at breakpoints: 320px (mobile), 768px (tablet), 1024px (desktop), 1440px (large). Visual regression at each breakpoint catches responsive layout bugs.

### Evidence

Percy's AI Review Agent (launched late 2025) reduces review time by 3x and automatically filters 40% of false positives. Chromatic's tight Storybook integration means every story is automatically a visual test.

axe-core and Pa11y compared head-to-head: "Each tool definitely finds things which the other does not. Therefore, from these tests, it is recommended using both."

### Implications for the Toolkit

**Confidence: Medium-High.** The toolkit should:

1. For projects with UI: add accessibility testing to the quality gate (axe-core + pa11y-ci on key pages)
2. Recommend visual regression tooling based on project setup (Storybook -> Chromatic, no Storybook -> Percy or BackstopJS)
3. Include responsive breakpoint testing in e2e test templates
4. Quality gate should run accessibility checks as a non-blocking warning initially, then as a blocking gate once baseline is established

### Sources

- [Percy — AI-Powered Visual Review Agent](https://bug0.com/knowledge-base/percy-visual-regression-testing)
- [axe-core vs PA11Y comparison](https://www.craigabbott.co.uk/blog/axe-core-vs-pa11y/)
- [Accessibility Automation: axe-core and Pa11y](https://www.leadwithskills.com/blogs/accessibility-automation-axe-core-pa11y-a11y-testing)
- [CivicActions — Automated accessibility with GitHub Actions](https://accessibility.civicactions.com/posts/automated-accessibility-testing-leveraging-github-actions-and-pa11y-ci-with-axe)

---

## 5. End-to-End Testing

### Findings

**Playwright vs. Cypress vs. Selenium (2025-2026):**

| Feature | Playwright | Cypress | Selenium |
|---------|-----------|---------|----------|
| Browser support | Chromium, Firefox, WebKit | Chrome-family, Firefox (limited) | All (via drivers) |
| Language support | JS, TS, Python, C#, Java | JS, TS only | All major languages |
| Parallelization | Built-in, free | Paid (Cypress Cloud) | External (Selenium Grid) |
| Architecture | Multi-process, out-of-process | In-process, same-origin limited | Client-server |
| Speed (headless) | 42% faster than Cypress | Baseline | Slowest |
| Downloads (2025) | Surpassed Cypress June 2024 | Declining relative share | Stable, enterprise |
| Test isolation | Browser context per test (fast) | Page reload per test | New driver session |
| Network interception | Native, multi-origin | Limited to same-origin | Via proxy |
| Mobile testing | WebKit + device emulation | Limited device emulation | Appium extension |

**Verdict:** Playwright is the recommended default for new projects in 2025-2026. Cypress remains viable for teams already invested in it, especially for component testing. Selenium is legacy — use only for cross-browser compatibility testing that Playwright can't cover.

**Flaky Test Reduction Strategies:**

Flaky tests are a $512M problem industry-wide, with 59% of developers encountering them regularly and enterprise teams spending 8% of development time on test failures.

Root causes: (1) race conditions in async operations, (2) shared mutable state between tests, (3) network latency variations, (4) time-dependent logic, (5) non-deterministic data.

Evidence-based mitigation:
- **Explicit waits over timeouts:** `await page.waitForSelector()` beats `sleep(2000)`. Playwright's auto-waiting is superior to manual waits.
- **Test isolation:** Each test creates its own data, signs in fresh, cleans up after. No shared state between tests.
- **Deterministic inputs:** Freeze clocks (`page.clock`), mock network responses for external APIs, use seeded random generators.
- **Retry with quarantine:** Identify flaky tests, quarantine them (run separately, don't block CI), fix root cause. Don't just add retries.
- **Stub external dependencies:** Remove reliance on flaky external systems for deterministic results.

### Evidence

BrowserStack and Katalon comparisons both conclude Playwright leads in cross-browser support, parallel execution, and CI/CD integration. Market data shows Playwright surpassing Cypress in weekly npm downloads for the first time in June 2024, with the gap widening.

### Implications for the Toolkit

**Confidence: High.** The toolkit should:

1. Default to Playwright for e2e test generation in new projects
2. Include flaky test detection: if a test passes on retry but failed initially, flag it for quarantine
3. E2e test templates should use: auto-wait patterns, test isolation (fresh browser context), deterministic data seeding
4. Quality gate should track flaky test rate as a metric (flaky failures / total runs)

### Sources

- [Playwright vs Cypress — BrowserStack 2025](https://www.browserstack.com/guide/playwright-vs-cypress)
- [Playwright vs Cypress — Katalon 2025](https://katalon.com/resources-center/blog/playwright-vs-cypress)
- [Cypress vs Playwright in 2026 — BugBug](https://bugbug.io/blog/test-automation-tools/cypress-vs-playwright/)
- [Best Practices for E2E Testing 2025 — BunnyShell](https://www.bunnyshell.com/blog/best-practices-for-end-to-end-testing-in-2025/)
- [Flaky Tests — Reproto Guide](https://reproto.com/how-to-fix-flaky-tests-in-2025-a-complete-guide-to-detection-prevention-and-management/)

---

## 6. API Contract Testing

### Findings

**Pact (Consumer-Driven Contracts):**
- Consumer writes a test defining the requests it makes and the responses it expects
- Pact generates a contract file (JSON) from the consumer test
- Provider verifies the contract by replaying recorded interactions against its real implementation
- Pact Broker coordinates contract lifecycle across teams

**Pact vs. OpenAPI Schema Validation:**

| Aspect | Pact | OpenAPI Validation |
|--------|------|--------------------|
| Approach | Consumer-driven, test-generated | Provider-defined specification |
| What it tests | What the consumer actually uses | All possible states |
| Flexibility | Loose matching (only assert on fields you use) | Strict schema compliance |
| False positives | Low (tests real consumer needs) | Higher (may test unused fields) |
| Setup cost | Higher (tests in both consumer + provider) | Lower (validate against spec) |
| Drift detection | Automatic (consumer updates tests) | Manual (spec may diverge from code) |

**Best practice (2025):** Use both. OpenAPI validates the contract for external consumers. Pact validates actual consumer requirements for internal services. Bi-directional contract testing (PactFlow) bridges both — consumer publishes Pact, provider publishes OAS, PactFlow cross-validates.

**PactFlow AI Code Review (2025 feature):** Automatically inspects Pact tests for best practices, actionable suggestions to improve quality and coverage.

**Key principle:** Keep contracts as loose as possible. Don't assert on fields the consumer doesn't use. This prevents provider changes from breaking contracts unnecessarily.

### Implications for the Toolkit

**Confidence: High.** The toolkit should:

1. Detect multi-service architectures (docker-compose with multiple services, separate API + frontend repos, monorepo with `packages/api` + `packages/web`)
2. Recommend Pact for inter-service testing, with a specific batch in plans for contract test setup
3. Recommend OpenAPI validation for any project with an OpenAPI/Swagger spec
4. AI agents should generate Pact consumer tests when building API consumers — assert only on fields actually used

### Sources

- [Pact Docs — Introduction](https://docs.pact.io/)
- [Pact — Convince Me](https://docs.pact.io/faq/convinceme)
- [Sachith — Contract testing with Pact Best Practices 2025](https://www.sachith.co.uk/contract-testing-with-pact-best-practices-in-2025-practical-guide-feb-10-2026/)
- [PactFlow — AI Code Review](https://pactflow.io/blog/create-best-practice-tests-with-code-review/)
- [Microsoft — Consumer-Driven Contract Testing](https://microsoft.github.io/code-with-engineering-playbook/automated-testing/cdc-testing/)

---

## 7. Test Data Management

### Findings

**Factories vs. Fixtures vs. Seeds:**

| Pattern | Description | Best For | Risk |
|---------|-------------|----------|------|
| **Factories** | Functions that generate data on demand, unique per call | Dynamic, parallel-safe tests | Complex setup if many relations |
| **Fixtures** | Predefined data in files, loaded before tests | Stable reference data, snapshots | Drift from production schema, fragile |
| **Seeds** | Database scripts that populate baseline data | Initial state, demo data | Coupling between tests if shared |

**Evidence-based recommendation:** Factories over fixtures for test data. Factories generate unique, self-contained data per test, preventing cross-test pollution. Fixtures are acceptable for read-only reference data that doesn't change between tests.

**Database Isolation Strategies:**

1. **Transaction rollback** — Wrap each test in a begin/rollback. Fast, prevents pollution. Breaks if code under test manages its own transactions.
2. **Per-test database** — Testcontainers or multiple test databases. Complete isolation, slow startup. Best for integration tests.
3. **Truncate-and-reseed** — Truncate tables before each test, reseed baseline. Medium speed, good isolation. Works for most cases.
4. **Database branching** — Neon/PlanetScale instant branching for test environments. Newest approach, good for CI.

**Key principle:** Every test creates its own data. Tests must not depend on data created by other tests. `beforeEach` resets state and creates fresh data.

### Implications for the Toolkit

**Confidence: High.** The toolkit should:

1. Include factory pattern recommendations in plan generation for projects with databases
2. Detect ORM (SQLAlchemy, Prisma, TypeORM) and recommend appropriate factory libraries (factory_boy, @faker-js/faker, fishery)
3. AI agents should generate test factories as part of the first batch (alongside model/schema code)
4. Quality gate could check for test isolation: detect shared state between tests (global variables, module-level database state)

### Sources

- [Grizzly Peak Software — Test Fixtures and Factories](https://www.grizzlypeaksoftware.com/library/test-fixtures-and-factories-gids8uq8)
- [Neon — Database testing with fixtures and seeding](https://neon.com/blog/database-testing-with-fixtures-and-seeding)
- [OneUpTime — How to Fix Test Data Management Issues](https://oneuptime.com/blog/post/2026-01-24-fix-test-data-management-issues/view)
- [DataStealth — 6 Test Data Management Best Practices](https://datastealth.io/blogs/test-data-management-best-practices)

---

## 8. Performance and Load Testing

### Findings

**Tool Comparison:**

| Tool | Language | Architecture | Strength | Best For |
|------|----------|-------------|----------|----------|
| **k6** | JavaScript (Go runtime) | Single-process, multi-core | CI-friendly thresholds, low resource usage, Grafana integration | DevOps teams, CI/CD pipelines |
| **Locust** | Python | Distributed master-worker | Python ecosystem, easy scripting, 70% less resources than JMeter | Python teams, distributed testing |
| **Artillery** | YAML/JavaScript | Node.js-based | Quick YAML configuration, low barrier to entry | Quick load tests, YAML-oriented teams |
| **JMeter** | Java (GUI/CLI) | Thread-based | Widest protocol support, mature ecosystem | Enterprise, complex protocols |

**Should AI agents write performance tests?**

Yes, with constraints. AI agents can effectively generate:
- **Baseline load tests** — script common user journeys with expected throughput
- **Spike tests** — ramp patterns that test system resilience
- **Threshold definitions** — p95 latency < 200ms, error rate < 1%

AI agents should NOT generate:
- **Capacity planning tests** — require domain knowledge about expected user counts
- **Stress test targets** — require knowledge of infrastructure limits
- **Performance regression baselines** — require historical data

**k6 recommendation for the toolkit:** k6's JavaScript scripting, CLI-first design, and built-in threshold enforcement (exit non-zero if thresholds fail) make it the natural fit for CI/CD integration and AI agent generation.

### Implications for the Toolkit

**Confidence: Medium.** The toolkit should:

1. Include k6 as the recommended performance testing tool
2. AI agents can generate baseline performance tests as a late batch (after functional tests pass)
3. Performance thresholds should be enforced in CI but not in the inter-batch quality gate (too slow)
4. Template: k6 script with common patterns (ramp-up, steady state, ramp-down) and configurable thresholds

### Sources

- [Doran Gao — Load Testing PoC: k6 vs Artillery vs Locust vs Gatling](https://medium.com/@dorangao/load-testing-poc-k6-vs-artillery-vs-locust-vs-gatling-node-js-express-target-f056094ffbef)
- [k6 vs Other Performance Testing Tools — QACraft](https://qacraft.com/k6-vs-other-performance-testing-tools/)
- [Load Testing Your API: k6 vs Artillery vs Locust](https://medium.com/@sohail_saifi/load-testing-your-api-k6-vs-artillery-vs-locust-66a8d7f575bd)

---

## 9. Security Testing in CI

### Findings

**SAST (Static Application Security Testing):**

| Tool | Language Focus | Detection Rate | False Positive Rate | Speed | Cost |
|------|---------------|---------------|--------------------|---------| -----|
| **Semgrep** | Multi-language | 95% (with tuning) | Moderate (needs config) | Fast | Free (OSS) + Pro |
| **Bandit** | Python only | 88% injection, 95% hardcoded secrets | 12% | 15s avg | Free (OSS) |
| **SonarQube CE** | Multi-language | Good for common patterns | Higher | Medium | Free (OSS) |
| **Gitleaks** | Any (secrets only) | High for secrets | Low | Very fast | Free (OSS) |

**DAST (Dynamic Application Security Testing):**

| Tool | Focus | Integration | Cost |
|------|-------|-------------|------|
| **OWASP ZAP** | Web app vulnerabilities | CI-friendly, Docker | Free (OSS) |
| **StackHawk** | API security | GitHub Actions native | Free tier + Pro |

**Recommended CI Security Pipeline:**

```
Pre-commit:
  - Gitleaks (secret scanning, <1s)

PR / Inter-batch:
  - Semgrep (SAST, multi-language, ~30s)
  - Bandit (SAST, Python-specific, ~15s)
  - npm audit / pip-audit (dependency scanning)

Nightly / Pre-deploy:
  - OWASP ZAP (DAST against staging)
  - Snyk / Trivy (container + dependency deep scan)
```

**Key insight:** Run SAST in CI for fast feedback (every PR). Run DAST against staging for runtime issues (nightly or pre-deploy). The combined approach — StackHawk + Semgrep correlation shows "exactly what's exploitable in production" by linking code-level findings with runtime validation.

### Implications for the Toolkit

**Confidence: High.** The toolkit should:

1. Add Semgrep to the quality gate for multi-language SAST (alongside lesson-check.sh)
2. Gitleaks is already enforced via pre-commit — document this as security layer 1
3. Add `npm audit --audit-level=high` / `pip-audit` to quality gate for dependency scanning
4. DAST (ZAP) should be recommended for projects with web endpoints but not run inter-batch (too slow)
5. Security scan results should be non-blocking warnings initially, blocking after team establishes baseline

### Sources

- [OX Security — Top 10 SAST Tools in 2025](https://www.ox.security/blog/static-application-security-sast-tools/)
- [Johal — SAST Implementation: Bandit in CI/CD](https://johal.in/sast-implementation-bandit-tool-for-python-code-security-scanning-in-ci-cd-pipelines-2025/)
- [StackHawk + Semgrep — SAST/DAST Correlation](https://www.stackhawk.com/blog/stackhawk-semgrep-sast-dast-integration/)
- [IBM — SAST and DAST automated security testing](https://github.com/IBM/mcp-context-forge/issues/259)

---

## 10. Test Quality Metrics

### Findings

**Metrics that predict quality (evidence-backed):**

| Metric | Predictive Value | Evidence |
|--------|-----------------|----------|
| **Mutation score** | High | Google study: 15M mutants coupled with real faults. 82% of reported mutants labeled "productive" by developers |
| **Branch coverage** (not line) | Moderate | Modest but significant correlation with software quality in 3 large Java projects |
| **Test-to-code ratio** | Low-moderate | Indicates test investment but not quality |
| **Flaky test rate** | High (inverse) | High flaky rate = eroded trust, ignored failures |
| **Test execution time** | Indirect | Slow tests get skipped; fast tests get run |

**Metrics that are vanity metrics (weak predictors):**

| Metric | Why It's Weak |
|--------|--------------|
| **Line coverage %** | Can be gamed (execute code without asserting behavior). 90%+ coverage with critical bugs is common |
| **Test count (raw)** | More tests != better tests. Tautological tests inflate count without value |
| **Pass rate %** | Near-100% pass rate with weak assertions provides false confidence |

**The coverage threshold evidence:** Research consensus: chase the right 60-80%, not any 80%. Focus on code that changes often, carries financial/safety risk, or stitches systems together. After 60-80%, additional coverage has diminishing returns — test design quality dominates.

**Mutation testing as the gold standard:**

Google's study (Petrovic et al., ICSE 2021) analyzed 15 million mutants and found:
- Developers using mutation testing write more tests and actively improve test suites
- Mutants are coupled with real faults — mutation testing would have caught production bugs
- Incremental mutation testing during code review (not whole codebase) is practical
- Context-based mutant filtering removes irrelevant mutants, improving actionability

Meta's 2025 trial: Privacy engineers accepted 73% of generated tests, with 36% judged as privacy-relevant. The system "generates mutants closely coupled to the issue of concern and produces tests that catch faults missed by existing tests."

### Implications for the Toolkit

**Confidence: High.** The toolkit should:

1. Track mutation score (via mutmut for Python, Stryker for JS) as the primary test quality metric — not line coverage
2. Replace raw test-count monotonicity with a richer model: test count + mutation score + coverage delta
3. Add flaky test tracking: tests that pass on retry get logged, reported, and eventually quarantined
4. Include mutation testing as an optional quality gate check (slow — nightly or per-PR, not inter-batch)
5. Report coverage by risk zone: "High-change files have X% coverage" > "Overall coverage is Y%"

### Sources

- [Petrovic et al. — Does mutation testing improve testing practices? (ICSE 2021)](https://arxiv.org/abs/2103.07189)
- [Google — Practical Mutation Testing at Scale](https://research.google/pubs/practical-mutation-testing-at-scale-a-view-from-google/)
- [Meta — LLMs Are the Key to Mutation Testing](https://engineering.fb.com/2025/09/30/security/llms-are-the-key-to-mutation-testing-and-better-compliance/)
- [Google Testing Blog — Mutation Testing](https://testing.googleblog.com/2021/04/mutation-testing.html)
- [marcgg — Code Coverage Is A Vanity Metric](https://marcgg.com/blog/2015/11/03/code-coverage-vanity-metric/)
- [ResearchGate — Is Code Quality Related to Test Coverage?](https://www.researchgate.net/publication/299594922_Is_Code_Quality_Related_to_Test_Coverage)

---

## 11. AI-Generated Tests

### Findings

**Current State of LLM Test Generation:**

A central challenge across all LLM-based test generation approaches is the high number of non-compiling and failing test cases. Red Hat's 2025 study comparing GPT-4o, Gemini-1.5-pro, and DeepSeek-Coder found:
- All models perform best in Python
- GPT excelled in Kotlin, Gemini in Java, DeepSeek in Go
- No clear relationship between test quality and code complexity/length

**Systematic Failure Modes of AI-Generated Tests:**

| Failure Mode | Description | Frequency | Mitigation |
|-------------|-------------|-----------|------------|
| **Happy-path clustering** | Tests only validate the golden path, missing edge cases | Very common | Prompt for error cases, boundary conditions, invalid inputs explicitly |
| **Tautological assertions** | Tests assert what the code does, not what it should do | Common | Mutation testing catches these — if mutant survives, assertion is tautological |
| **Mock-heavy tests** | Over-mocking removes the behavior being tested | Common (25% mock failures in open-source LLMs) | Require integration tests alongside mocked unit tests; flag >3 mocks per test |
| **Implementation coupling** | Tests break on refactoring because they test internal structure | Common | Review for: does this test break if we refactor without changing behavior? |
| **Weak assertions** | `assert result is not None` instead of `assert result == expected` | Common | Mutation testing score <50% = weak assertions |
| **Non-compiling tests** | Incorrect imports, wrong function signatures, hallucinated APIs | Frequent | Compile/syntax check before counting as a test |
| **Cryptic naming** | `test_1`, `result_obj` instead of descriptive names | Common | Readability review in code quality gate |

**Quantitative evidence:** LLMs achieve only ~40% mutation kill rate, compared to human-written tests at 60-80%. This means AI-generated tests miss 60% of seeded bugs that human tests would catch.

**IBM internal finding:** Developers tossed 70% of LLM-generated test outputs because they felt "robotic — no flow, no intent."

### Implications for the Toolkit

**Confidence: High.** This is the most directly actionable section. The toolkit should:

1. **Add AI test quality checks to the quality gate:**
   - Detect tautological assertions (assert on input, not output)
   - Flag tests with >3 mocks (likely over-mocked)
   - Flag `assert is not None` / `assert True` patterns (weak assertions)
   - Run mutation testing sample on AI-generated tests

2. **Enhance prompt engineering for test generation:**
   - Include "Test error cases, boundary conditions, and invalid inputs" in every test-writing prompt
   - Include "Do not mock the system under test" as a constraint
   - Include "Each assertion must verify a specific output value, not just existence"
   - Include "Test behavior, not implementation — tests should survive refactoring"

3. **Two-pass test generation:**
   - Pass 1: AI writes tests (current behavior)
   - Pass 2: Run mutation testing on the tests, feed surviving mutants back to AI: "These mutants survived your tests. Write tests that kill them."

4. **Track AI test quality over time:** Log mutation scores per batch. If mutation score drops, flag the batch for human review.

### Sources

- [Red Hat Research — Choosing LLMs for unit test generation](https://research.redhat.com/blog/2025/04/21/choosing-llms-to-generate-high-quality-unit-tests-for-code/)
- [Shekhar — Why AI-Generated Unit Tests Fall Short](https://shekhar14.medium.com/unmasking-the-flaws-why-ai-generated-unit-tests-fall-short-in-real-codebases-71e394581a8e)
- [FrugalTesting — LLM-Powered Test Case Generation](https://www.frugaltesting.com/blog/llm-powered-test-case-generation-enhancing-coverage-and-efficiency)
- [Are "Solved Issues" in SWE-bench Really Solved?](https://arxiv.org/html/2503.15223v1)
- [Red Hat — Benchmarking LLM-generated unit tests](https://research.redhat.com/blog/2025/09/03/student-research-yields-a-new-tool-for-benchmarking-llm-generated-unit-tests/)

---

## 12. Testing Strategy for the Toolkit

### Findings

Based on all previous sections, the toolkit needs three enhancements:

**A. Test Strategy Advisor (project-level)**

On project initialization or first `/autocode` run, analyze:
- Project type (backend-only, frontend-only, full-stack, monorepo, microservices)
- Tech stack (Python/Node/Go, React/Vue/Preact, PostgreSQL/MongoDB)
- Existing test infrastructure (test framework, coverage tools, CI config)

Output: a `testing-strategy.json` that captures:
```json
{
  "shape": "trophy",
  "layers": {
    "static": {"tools": ["typescript", "eslint"], "target": "100%"},
    "unit": {"tools": ["vitest"], "target_ratio": 0.20},
    "integration": {"tools": ["vitest", "testing-library"], "target_ratio": 0.50},
    "e2e": {"tools": ["playwright"], "target_ratio": 0.15},
    "visual": {"tools": ["chromatic"], "target_ratio": 0.10},
    "accessibility": {"tools": ["axe-core", "pa11y-ci"], "target_ratio": 0.05}
  },
  "quality_metrics": {
    "mutation_score_target": 0.60,
    "coverage_target": 0.80,
    "flaky_rate_max": 0.02
  }
}
```

**B. Layered Quality Gate**

Replace the monolithic test run with a tiered system:

| Tier | Checks | When | Duration |
|------|--------|------|----------|
| **T0: Instant** | lesson-check, lint, compile | Every batch | <10s |
| **T1: Fast** | Unit tests, static analysis | Every batch | <60s |
| **T2: Medium** | Integration tests, contract tests | Every batch | <5min |
| **T3: Slow** | E2E tests, visual regression | Every 3rd batch or pre-merge | <15min |
| **T4: Nightly** | Mutation testing, DAST, performance tests | Nightly/weekly | <60min |

**C. Test Templates per Project Type**

Pre-built test scaffolding that AI agents can reference:

| Project Type | Templates Included |
|-------------|-------------------|
| Python API | pytest fixtures, factory_boy factories, API contract tests, conftest.py patterns |
| Node.js API | vitest setup, supertest patterns, Pact consumer test, test database setup |
| React/Preact | RTL component tests, Storybook stories, Playwright e2e setup, MSW handlers |
| Full-stack | All of the above + contract test setup, shared test utilities |
| Monorepo | Nx/Turborepo affected-test config, shared test utilities package |

### Implications for the Toolkit

**Confidence: High.** This is the primary deliverable recommendation.

### Sources

All previous sections.

---

## 13. Property-Based and Fuzzing

### Findings

**Property-based testing (PBT)** complements example-based testing by generating random inputs that satisfy declared properties. Instead of `test(add(2,3) == 5)`, PBT declares `for all a, b: add(a, b) == add(b, a)` (commutativity) and generates thousands of test cases.

**Tools:**

| Tool | Language | Key Feature |
|------|----------|-------------|
| **Hypothesis** | Python | Stateful testing, database of examples, shrinking |
| **fast-check** | JavaScript/TypeScript | Shrinking, model-based testing, Vitest/Jest integration |
| **go-fuzz / gopter** | Go | Native fuzzing since Go 1.18 |

**When to use PBT vs. example-based:**

| Use PBT | Use Example-Based |
|---------|-------------------|
| Parsers, serializers (roundtrip property) | UI interactions |
| Mathematical operations (algebraic properties) | Workflow/business logic with specific scenarios |
| Data transformations (idempotency, commutativity) | Integration tests with external services |
| Input validation (no valid input crashes) | Tests requiring specific fixtures/state |
| Encoding/decoding (encode(decode(x)) == x) | Performance-sensitive tests (PBT generates many inputs) |

**Evidence:** Hypothesis has found real bugs in Python core libraries, cryptographic implementations, and scientific computing packages. The Argon2 binding bug — hash length > 512 hits a fixed-size C buffer, causing verification failure — would be nearly impossible to find with example-based testing.

**PBT + AI agents:** AI agents are well-suited to generate property-based tests because:
1. They can identify algebraic properties from function signatures
2. They can generate custom Hypothesis strategies for domain types
3. PBT reduces the "happy-path clustering" problem — properties force exploration of the input space

### Implications for the Toolkit

**Confidence: Medium-High.** The toolkit should:

1. Include PBT in test templates for parsers, serializers, validators, and data transformations
2. Prompt AI agents to use Hypothesis/fast-check for functions with well-defined algebraic properties
3. PBT tests should be run as part of T1 (fast) quality gate — they're typically fast per-property

### Sources

- [Hypothesis — What is property-based testing?](https://hypothesis.works/articles/what-is-property-based-testing/)
- [fast-check — Comprehensive Guide to Property-Based Testing](https://medium.com/@joaovitorcoelho10/fast-check-a-comprehensive-guide-to-property-based-testing-2c166a979818)
- [Increment — In praise of property-based testing](https://increment.com/testing/in-praise-of-property-based-testing/)
- [Antithesis — Property-based testing finding bugs you don't know you have](https://antithesis.com/resources/property_based_testing/)

---

## 14. Monorepo Testing

### Findings

**Affected-Only Testing:**

In a monorepo, running all tests on every change is wasteful. Affected-only testing runs tests for packages that changed or depend on changed packages.

| Tool | Affected Detection | Parallel Execution | Cache | Test Splitting |
|------|-------------------|-------------------|-------|----------------|
| **Nx** | `nx affected --target=test` (git diff based) | `--parallel=N` | Remote cache (Nx Cloud) | Yes, via task graph |
| **Turborepo** | `turbo run test --filter=...[HEAD^]` | Built-in | Remote cache (Vercel) | Limited |
| **Bazel** | Precise dependency graph | Massive parallelism | Hermetic, remote | Yes |

**Nx vs. Turborepo (2025):**

Nx is significantly faster than Turborepo — open-source benchmarks show >7x better performance in large monorepos. Nx offers richer features: module boundary enforcement, code generators, dependency visualization, and affected analysis based on the full project graph (not just file changes).

Turborepo is simpler to set up and sufficient for smaller monorepos (<20 packages). For large monorepos (20+ packages), Nx is the clear choice.

**Cross-package testing strategies:**
1. **Unit tests** — package-local, never cross package boundaries
2. **Integration tests** — test package interactions, run when either package changes
3. **E2E tests** — test full application, run on key path changes or pre-merge
4. **Contract tests** — between packages that communicate via API, run when interface changes

### Implications for the Toolkit

**Confidence: Medium-High.** The toolkit should:

1. Detect monorepo structure (presence of `nx.json`, `turbo.json`, `lerna.json`, or `packages/` directory)
2. For monorepos, use affected-only test running in quality gate: `nx affected --target=test` instead of `npm test`
3. Plan generation should respect package boundaries — batches should target specific packages
4. Test count monotonicity should be per-package, not global (adding a package shouldn't mask test regression in another)

### Sources

- [Nx vs Turborepo — Wisp CMS Comprehensive Guide](https://www.wisp.blog/blog/nx-vs-turborepo-a-comprehensive-guide-to-monorepo-tools)
- [Turborepo vs Nx: 2025 Comparison](https://generalistprogrammer.com/comparisons/turborepo-vs-nx)
- [Aviator — Top 5 Monorepo Tools for 2025](https://www.aviator.co/blog/monorepo-tools/)

---

## 15. Test Infrastructure for CI/CD

### Findings

**GitHub Actions Optimization Patterns:**

1. **Fan-out/fan-in:** Single setup job -> parallel test jobs -> aggregation job
   ```yaml
   jobs:
     setup:
       # Install deps, build, upload artifacts
     test-unit:
       needs: setup
       # Download artifacts, run unit tests
     test-integration:
       needs: setup
       # Download artifacts, run integration tests
     test-e2e:
       needs: setup
       # Download artifacts, run e2e tests
     report:
       needs: [test-unit, test-integration, test-e2e]
       if: always()
       # Aggregate results
   ```

2. **Matrix strategy for test splitting:**
   ```yaml
   strategy:
     matrix:
       shard: [1, 2, 3, 4]
   steps:
     - run: npx playwright test --shard=${{ matrix.shard }}/4
   ```

3. **Caching strategies:**
   - Cache `node_modules` by `package-lock.json` hash
   - Cache `.venv` by `requirements.txt` hash
   - Cache Playwright browsers by version
   - Cache test results for unchanged files (Nx/Turborepo remote cache)

4. **Dynamic test splitting:** Use previous run times to evenly balance test loads across runners. CircleCI and some GitHub Actions implementations support this natively.

**Containerized test environments:**
- Testcontainers for database/queue dependencies (PostgreSQL, Redis, RabbitMQ)
- Docker Compose for multi-service integration tests
- Ephemeral environments (Neon branching, PlanetScale branching) for database tests

**Key optimization metrics:**
- CI feedback time should be <10 minutes for PR checks
- E2E tests can run in parallel with unit tests (independent)
- Security scans (Semgrep) are fast enough for every PR
- DAST and mutation testing are too slow for PR checks — run nightly

### Implications for the Toolkit

**Confidence: High.** The toolkit should:

1. Generate GitHub Actions workflow templates based on project type
2. Include test splitting configuration for large test suites (Playwright sharding, pytest-xdist, Jest --shard)
3. Recommend caching strategies per dependency type
4. The `--quality-gate` flag should support tier-based execution: `--quality-gate-tier T1` for inter-batch, `--quality-gate-tier T3` for pre-merge

### Sources

- [OneUpTime — How to Run Tests in Parallel in GitHub Actions](https://oneuptime.com/blog/post/2025-12-20-github-actions-parallel-tests/view)
- [Marcus Felling — Optimizing GitHub Actions Workflows](https://marcusfelling.com/blog/2025/optimizing-github-actions-workflows-for-speed)
- [JeeviAcademy — Caching, Parallelism, and Test Optimization](https://www.jeeviacademy.com/how-to-speed-up-your-ci-cd-pipeline-caching-parallelism-and-test-optimization/)
- [WarpBuild — Concurrent tests in GitHub Actions](https://www.warpbuild.com/blog/concurrent-tests)

---

## Testing Strategy Matrix

**Project Type x Testing Layer -> Recommended Tools and Approaches:**

| Layer | Python API | Node.js API | React/Preact | Full-Stack | Monorepo |
|-------|-----------|-------------|-------------|------------|----------|
| **Shape** | Pyramid | Pyramid | Trophy | Hybrid | Per-package |
| **Static** | mypy, ruff | TypeScript, ESLint | TypeScript, ESLint | Both | Per-package |
| **Unit** | pytest, Hypothesis | Vitest, fast-check | Vitest + RTL | Both | Nx affected |
| **Integration** | pytest + httpx, factory_boy | Vitest + supertest | Vitest + RTL | Pact contracts | Nx affected |
| **E2E** | Playwright (API) | Playwright | Playwright | Playwright | Playwright (app) |
| **Visual** | N/A | N/A | Chromatic or Percy | Chromatic or Percy | Chromatic or Percy |
| **A11y** | N/A | N/A | axe-core + pa11y | axe-core + pa11y | axe-core + pa11y |
| **Performance** | k6 or Locust | k6 | Lighthouse CI | k6 + Lighthouse | k6 |
| **Security** | Bandit + Semgrep | Semgrep + npm audit | Semgrep | All | Per-package |
| **Mutation** | mutmut | Stryker | Stryker | Both | Per-package |
| **Contract** | Pact (if multi-svc) | Pact (if multi-svc) | Pact consumer | Pact (both sides) | Pact (cross-pkg) |
| **Data** | factory_boy | fishery/@faker-js | MSW + fixtures | Factory per layer | Shared factory pkg |
| **CI Pattern** | pytest-xdist parallel | Vitest threads | Playwright sharding | Fan-out/fan-in | Nx affected + cache |

---

## Quality Gate Enhancement Proposal

### Current State

```
quality-gate.sh:
  Check 0: validate-all.sh (toolkit self-check)
  Check 1: lesson-check.sh (anti-pattern grep, <2s)
  Check 2: Lint (ruff / eslint)
  Check 2.5: ast-grep structural analysis (advisory)
  Check 3: Test suite (auto-detect: pytest / npm test / make test)
  Check 4: License check (optional)
  Check 5: Memory check (advisory)
```

### Proposed Enhancement: Tiered Quality Gate

```
quality-gate.sh --tier T0|T1|T2|T3|T4

T0 (Instant, every batch, <10s):
  - lesson-check.sh
  - Compile/syntax check
  - Test count regression

T1 (Fast, every batch, <60s):
  - T0 checks
  - Lint (ruff / eslint)
  - Unit tests only (pytest -m unit / vitest --filter unit)
  - ast-grep structural analysis

T2 (Medium, every batch - default, <5min):
  - T1 checks
  - Integration tests (full test suite)
  - Contract tests (Pact verify)
  - Dependency security scan (npm audit / pip-audit)
  - AI test quality checks:
    - Weak assertion detection (assert is not None, assert True)
    - Mock count check (>3 mocks per test = warning)
    - Test name quality (no test_1, test_2 patterns)

T3 (Pre-merge, every 3rd batch or --pre-merge, <15min):
  - T2 checks
  - E2E tests (Playwright)
  - Visual regression (if configured)
  - Accessibility scan (axe-core + pa11y on key pages)
  - Semgrep SAST scan
  - Coverage report with risk-zone analysis

T4 (Nightly/Weekly, scheduled, <60min):
  - T3 checks
  - Mutation testing (mutmut / Stryker on changed files)
  - DAST scan (OWASP ZAP against staging)
  - Performance test baseline (k6)
  - Full dependency audit (Snyk / Trivy)
  - Flaky test report generation
```

### Implementation Changes to quality-gate.sh

1. Add `--tier` flag (default: T2 for backward compatibility)
2. Add `--project-type` flag to select appropriate tools
3. Add per-layer test counting: track unit/integration/e2e counts separately in `.run-plan-state.json`
4. Add AI test quality checks as new check functions
5. Add `testing-strategy.json` reader to configure which tools to run

### State File Enhancement

```json
{
  "test_counts": {
    "1": {"unit": 10, "integration": 5, "e2e": 2, "total": 17},
    "2": {"unit": 20, "integration": 8, "e2e": 2, "total": 30}
  },
  "quality_metrics": {
    "mutation_score": 0.62,
    "coverage": 0.78,
    "flaky_tests": ["test_login_redirect", "test_websocket_reconnect"],
    "ai_test_quality": {
      "weak_assertions": 3,
      "over_mocked": 1,
      "happy_path_only": 5
    }
  }
}
```

---

## Test Template Recommendations

### What the Toolkit Should Provide

**1. Python API Test Template**
```
tests/
  conftest.py            # Shared fixtures, test database setup, factory registration
  factories/
    __init__.py
    user.py              # factory_boy UserFactory with realistic defaults
  unit/
    test_models.py       # Pure logic tests, no DB
    test_validators.py   # Input validation, Hypothesis properties
  integration/
    test_api.py          # httpx/TestClient endpoint tests
    test_db.py           # Database operation tests with transaction rollback
  contracts/
    test_consumer.py     # Pact consumer tests (if multi-service)
  e2e/
    test_flows.py        # Playwright API tests for critical paths
  performance/
    load_test.js         # k6 baseline load test
```

**2. Node.js API Test Template**
```
tests/
  setup.ts               # Vitest global setup, test database
  factories/
    index.ts
    user.factory.ts       # fishery UserFactory
  unit/
    models.test.ts
    validators.test.ts    # fast-check property tests
  integration/
    api.test.ts           # supertest endpoint tests
    database.test.ts      # Testcontainers or transaction rollback
  contracts/
    consumer.test.ts      # Pact consumer tests
  e2e/
    playwright.config.ts
    flows.spec.ts         # Playwright e2e
  performance/
    load.k6.js            # k6 baseline
```

**3. React/Preact Frontend Template**
```
src/
  components/
    Button/
      Button.tsx
      Button.test.tsx     # RTL component test
      Button.stories.tsx  # Storybook story + interaction test
  __tests__/
    integration/
      login-flow.test.tsx  # Multi-component integration test
    e2e/
      playwright.config.ts
      auth.spec.ts         # Playwright e2e
      visual.spec.ts       # Playwright visual comparison
  test/
    setup.ts               # Vitest setup, MSW handlers
    mocks/
      handlers.ts          # MSW API mocks
    factories/
      user.factory.ts
```

**4. Full-Stack Template**
```
packages/
  api/
    tests/                 # Backend templates (see #2)
  web/
    tests/                 # Frontend templates (see #3)
  contracts/
    consumer.test.ts       # Pact: web -> api contract
    provider.test.ts       # Pact: api verifies web contract
  e2e/
    playwright.config.ts   # Cross-stack e2e
    critical-paths.spec.ts # Login, checkout, core workflows
  shared/
    test-utils/            # Shared test utilities
    factories/             # Shared data factories
```

### Skill/Command Integration

**New skill: `test-strategy`**
- Analyzes project type and existing test infrastructure
- Generates `testing-strategy.json` with recommended shape, tools, and targets
- Scaffolds test directories and initial configuration
- Configures quality gate tiers for the project

**Enhancement to `writing-plans` skill:**
- Plans must include test layer targets per batch: "Batch 3 should add 5 integration tests and 2 e2e tests"
- Plans must specify which quality gate tier each batch should pass

**Enhancement to `test-driven-development` skill:**
- TDD cycle should specify test TYPE (unit/integration/e2e) for each test
- Red-green-refactor should include mutation testing validation: "After green, check mutation score"
- Include property-based test generation for appropriate functions

---

## Sources

### Academic / Research

- [Petrovic et al. — Does mutation testing improve testing practices? (ICSE 2021)](https://arxiv.org/abs/2103.07189)
- [Google — Practical Mutation Testing at Scale](https://homes.cs.washington.edu/~rjust/publ/practical_mutation_testing_tse_2021.pdf)
- [Meta — LLMs Are the Key to Mutation Testing and Better Compliance](https://engineering.fb.com/2025/09/30/security/llms-are-the-key-to-mutation-testing-and-better-compliance/)
- [Red Hat Research — Choosing LLMs for high-quality unit tests](https://research.redhat.com/blog/2025/04/21/choosing-llms-to-generate-high-quality-unit-tests-for-code/)
- [Red Hat Research — Benchmarking LLM-generated unit tests](https://research.redhat.com/blog/2025/09/03/student-research-yields-a-new-tool-for-benchmarking-llm-generated-unit-tests/)
- [Are "Solved Issues" in SWE-bench Really Solved Correctly?](https://arxiv.org/html/2503.15223v1)
- [INRIA — Is Code Quality Related to Test Coverage?](https://inria.hal.science/hal-01653728v1/document)
- [University of Illinois — An Empirical Analysis of Flaky Tests](https://mir.cs.illinois.edu/lamyaa/publications/fse14.pdf)

### Industry / Practitioner

- [Martin Fowler — On the Diverse and Fantastical Shapes of Testing](https://martinfowler.com/articles/2021-test-shapes.html)
- [Kent C. Dodds — Write tests. Not too many. Mostly integration.](https://kentcdodds.com/blog/write-tests)
- [Kent C. Dodds — The Testing Trophy and Testing Classifications](https://kentcdodds.com/blog/the-testing-trophy-and-testing-classifications)
- [web.dev — Testing Strategies That Fit](https://web.dev/articles/ta-strategies)
- [Microsoft — Consumer-Driven Contract Testing](https://microsoft.github.io/code-with-engineering-playbook/automated-testing/cdc-testing/)
- [Storybook — How to test UIs](https://storybook.js.org/docs/writing-tests)
- [Storybook — Component Testing](https://storybook.js.org/blog/component-testing/)

### Tool Comparisons

- [BrowserStack — Playwright vs Cypress 2025](https://www.browserstack.com/guide/playwright-vs-cypress)
- [Katalon — Playwright vs Cypress Key Differences](https://katalon.com/resources-center/blog/playwright-vs-cypress)
- [BugBug — Cypress vs Playwright in 2026](https://bugbug.io/blog/test-automation-tools/cypress-vs-playwright/)
- [Percy AI Visual Review Agent](https://bug0.com/knowledge-base/percy-visual-regression-testing)
- [axe-core vs PA11Y](https://www.craigabbott.co.uk/blog/axe-core-vs-pa11y/)
- [k6 vs Artillery vs Locust](https://medium.com/@sohail_saifi/load-testing-your-api-k6-vs-artillery-vs-locust-66a8d7f575bd)
- [OX Security — Top 10 SAST Tools](https://www.ox.security/blog/static-application-security-sast-tools/)
- [Nx vs Turborepo Comprehensive Guide](https://www.wisp.blog/blog/nx-vs-turborepo-a-comprehensive-guide-to-monorepo-tools)

### Pact / Contract Testing

- [Pact Docs — Introduction](https://docs.pact.io/)
- [Pact — Convince Me](https://docs.pact.io/faq/convinceme)
- [Sachith — Contract Testing Best Practices 2025](https://www.sachith.co.uk/contract-testing-with-pact-best-practices-in-2025-practical-guide-feb-10-2026/)
- [PactFlow — AI Code Review for Contract Tests](https://pactflow.io/blog/create-best-practice-tests-with-code-review/)

### CI/CD and Infrastructure

- [OneUpTime — Parallel Tests in GitHub Actions](https://oneuptime.com/blog/post/2025-12-20-github-actions-parallel-tests/view)
- [Marcus Felling — Optimizing GitHub Actions](https://marcusfelling.com/blog/2025/optimizing-github-actions-workflows-for-speed)
- [WarpBuild — Concurrent tests in GitHub Actions](https://www.warpbuild.com/blog/concurrent-tests)
- [StackHawk + Semgrep — SAST/DAST Correlation](https://www.stackhawk.com/blog/stackhawk-semgrep-sast-dast-integration/)

### Test Data and Flakiness

- [Neon — Database testing with fixtures and seeding](https://neon.com/blog/database-testing-with-fixtures-and-seeding)
- [BunnyShell — Best Practices for E2E Testing 2025](https://www.bunnyshell.com/blog/best-practices-for-end-to-end-testing-in-2025/)
- [Reproto — How to Fix Flaky Tests in 2025](https://reproto.com/how-to-fix-flaky-tests-in-2025-a-complete-guide-to-detection-prevention-and-management/)
- [Rainforest QA — Reducing the burden of flaky tests](https://www.rainforestqa.com/blog/flaky-tests)
