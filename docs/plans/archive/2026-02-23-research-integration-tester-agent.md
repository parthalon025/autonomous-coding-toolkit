# Research: Integration Tester Agent for Cross-Service Boundary Validation

**Date:** 2026-02-23
**Status:** Complete
**Confidence:** High on patterns (multiple independent implementations); medium on agent structure (synthesized from field examples, not academic benchmarks)
**Domain classification:** Complicated (Cynefin) — known engineering patterns exist; adaptation to file-based, systemd-driven architecture requires contextual judgment

---

## Executive Summary

The target system has four known integration seams where individual services pass their own tests but bugs hide at the boundary: aria-hub → engine output files → ha-log-sync logbook; telegram-brief → notion-tools local replica; ollama-queue daemon → 10 Ollama-using timers; and shared env vars across services. This is textbook Cluster B: "Each layer passes its test; bug hides at the seam."

The field has solved this class of problem with three converging approaches: (1) contract testing at schema/interface boundaries, (2) end-to-end trace following a single value across all hops, and (3) black-box pipeline validation treating inter-service file/DB handoffs as input/output pairs. No existing Claude Code agent covers this for file-based, systemd-driven local architectures — the agent must be purpose-built.

**Recommended agent structure:** A single orchestrating agent with four specialized sub-probes — one per seam — plus a shared-env audit probe. Each probe executes a vertical trace: inject a known value at the upstream boundary, verify it arrives with correct schema at the downstream boundary, report pass/fail with evidence. No mocks. No internal inspection. Only observable outputs.

**Recommended agent name:** `integration-tester` — invoked as `/integration-tester` or dispatched via Task tool.

---

## Source Analysis

### Source 1: Airwallex Airtest — Claude Code Subagents for Integration Testing

**URL:** [From 2 weeks to 2 hours — cutting integration test time using Claude Code Subagents](https://careers.airwallex.com/blog/using-claude-code-subagents/)

**What they built:** Airtest is an AI-generated, self-healing test platform initiated via a `/airtest` slash command. A General Agent orchestrates a team of specialists:

- Happy Path Agent (expected functionality)
- Unhappy Path Agent (error handling / failure modes)
- State Transition Agent (state changes across calls)
- Dependency Testing Agent (service interactions)
- End-to-End Flow Agent (complete workflow validation)
- Test Reviewer Agent (quality assessment of generated tests)
- Test Debugging Agent (diagnosis and fix of failing tests)
- Existing Tests Analysis Agent (coverage gap detection)

All agents share a persistent knowledge base containing API dependency mapping, business flow documentation, and recent code change impact. Agents have access to Code Search, Text Editor, Read, and Bash tools. The system generated 4,000+ integration tests and enabled 50 APIs to launch safely, reducing test time from 2 weeks to 2 hours.

**Key patterns to adopt:**
1. General agent + specialist decomposition. The orchestrator analyzes scope, delegates to the probe that matches the seam type, collects results, and writes a unified report.
2. The knowledge base pattern — the agent should maintain a `docs/integration-tester/seam-registry.json` mapping each seam's writer, reader, interface schema, and last-verified timestamp.
3. The Dependency Testing Agent maps directly to the integration-tester's probe model: one probe per service interaction, executing in isolation.

**What does not transfer:** Their architecture is API-call centric (HTTP request/response). The target system is file-based and systemd-driven. The "inject a request and verify the response" pattern must be adapted to "write a sentinel file at the upstream output path and verify it appears, transformed correctly, at the downstream input path."

---

### Source 2: OpenTelemetry Integration Test Pattern — Verify Trace Data Across Service Boundaries

**URL:** [How to Write Integration Tests That Verify Trace Data with OpenTelemetry](https://oneuptime.com/blog/post/2026-02-06-integration-tests-verify-trace-data-opentelemetry/view)

**Core pattern:** Integration tests that validate cross-service behavior follow a 5-step sequence:

1. Clear state — delete previous test data from the shared store
2. Send request — trigger cross-service workflow via the upstream entry point
3. Extract trace ID — retrieve the correlation identifier from the response or output
4. Poll downstream — wait for propagated data with timeout (10-15 seconds typical)
5. Assert structure — verify trace ID consistency, schema correctness, parent-child relationships, and data completeness

**Four critical cross-boundary assertions:**
- Shared correlation identifier (same trace ID across all hops)
- Service representation (all expected services produced output)
- Parent-child integrity (no orphaned references; each downstream output references the upstream source)
- Count sufficiency (expected number of artifacts arrive — e.g., 3 spans, 2 files, 1 DB row)

The polling-with-timeout pattern is critical because "spans may take a moment to be processed and exported" — the same is true of file-based pipelines where the upstream timer writes asynchronously.

**Key patterns to adopt:**
1. The 5-step sequence maps exactly to file-based integration testing: clear sentinel, trigger upstream, extract correlation ID embedded in output filename or content, poll downstream directory with timeout, assert schema.
2. The "clear state before each trace" principle prevents false positives from leftover artifacts — each probe run starts with a clean slate.
3. Deterministic correlation IDs: the agent injects a known sentinel value (e.g., `INTEGRATION_TEST_PROBE_2026-02-23T10:00:00Z`) into upstream data, then searches for that exact string downstream. This makes assertion unambiguous.

**What does not transfer:** OpenTelemetry's W3C `traceparent` headers and span exporters are specific to HTTP/RPC. File-based pipelines need correlation via embedded payload markers, not headers. The polling mechanism translates directly — poll a directory or file for the sentinel value instead of polling a trace backend.

---

### Source 3: Great Expectations — Black-Box Pipeline Validation

**URL:** [put-data-pipeline-under-test-with-pytest-and-great-expectations](https://github.com/greatexpectationslabs/put-data-pipeline-under-test-with-pytest-and-great-expectations)

**Core pattern:** Treat a pipeline as a black box. Prepare a known input dataset. Assert the output against a declarative specification. No internal inspection. Tests are parametrized from a JSON config:

```json
{
  "test_cases": [{
    "title": "logbook entries contain required fields",
    "input_file_path": "tests/fixtures/logbook-2026-02-23.json",
    "expectations_config_path": "tests/fixtures/logbook-schema.json"
  }]
}
```

The test runner reads config, executes the pipeline against each fixture, validates output against the expectations file, and reports failures with detailed assertion messages.

**Key patterns to adopt:**
1. The declarative expectations model — each seam should have a schema file (`seam-aria-engine-output.schema.json`, `seam-notion-replica.schema.json`) that serves as the contract. The integration-tester agent reads the schema and validates downstream output against it.
2. Fixture-based testing — the agent creates synthetic fixtures that represent minimal valid upstream output, injects them into the pipeline's input path, and checks downstream output. Decouples the integration test from live upstream timing.
3. The black-box principle — the agent never inspects internal service state (Python objects, in-memory caches). It only reads files, checks DB tables, or calls health endpoints that the service exposes externally.

**What does not transfer:** Great Expectations is a Python library for data validation, not an agent framework. The integration-tester agent uses its conceptual pattern (expectations-as-contracts) but implements it directly via Bash file inspection and Python schema validators, not the GX library itself.

---

### Source 4: Pact — Consumer-Driven Contract Testing

**URL:** [Pact Documentation](https://docs.pact.io/) | [Contract Testing Best Practices 2025](https://www.sachith.co.uk/contract-testing-with-pact-best-practices-in-2025-practical-guide-feb-10-2026/)

**Core concept:** A consumer (downstream service) defines what it expects from a provider (upstream service) in a contract. The provider verifies it meets those expectations. Only the parts of the interface actually consumed get tested — changes to unconsummed behavior don't break tests.

**Two key principles:**
1. Consumer-driven: the reader's needs define the contract, not the writer's full output schema. This prevents over-specification.
2. Can-I-Deploy check: before deploying any service, verify the latest version satisfies all consumer contracts. Gate deployments on contract compliance.

**Key patterns to adopt:**
1. The consumer-driven framing is exactly right for the target system: telegram-brief defines what it needs from the notion-tools replica (which fields, which structure); aria-hub defines what it needs from the engine output files. The integration-tester agent validates that the provider (upstream writer) satisfies these declared needs.
2. The contract-as-artifact pattern: store contracts in `docs/integration-tester/contracts/` as JSON files. The agent reads them to know what to assert. Contracts evolve with the system. This also serves as living documentation of cross-service dependencies.
3. Schema validation mode — for the file-based target system, use JSON Schema drafts rather than the Pact wire format. Each contract file specifies: `producer`, `consumer`, `interface_path` (file path or DB table), `schema` (JSON Schema), `freshness_ttl_minutes` (how old the file can be before it's stale).

**What does not transfer:** Pact's HTTP mock server and broker are for API-based systems. The target system needs file-path and SQLite-table contracts, not HTTP request/response pairs.

---

### Source 5: Microservices Testing Honeycomb — Integration at Every Seam

**URL:** [microservices-testing · GitHub Topics](https://github.com/topics/microservices-testing)

**Core pattern:** Spotify's honeycomb model for microservices prioritizes integration tests over unit tests because individual units are trivially simple — the complexity lives at service-to-service boundaries. Each boundary gets its own integration test. Unit tests are minimal. E2E tests are rare.

Applied to the target system:
- Individual service unit tests already exist (ha-aria/tests/, ollama-queue/tests/)
- The gap is integration tests at the four seams
- E2E ("did the whole system produce a valid HA automation suggestion today") is too slow for daily validation

**Key patterns to adopt:**
1. One test per seam, not one test for the whole system. The four seams in the target system each have different writers, readers, file formats, and timing characteristics. Bundling them into one test makes failures unattributable.
2. The honeycomb framing justifies the integration-tester as a first-class component, not an afterthought. Each seam test is as important as any unit test.

---

### Source 6: Seam Theory — Michael Feathers, Working Effectively with Legacy Code

**URL:** [Seams | Testing Effectively With Legacy Code | InformIT](https://www.informit.com/articles/article.aspx?p=359417&seqNum=2)

**Core concept:** A seam is "a place where you can alter behavior in your program without editing in that place." For integration testing, seams are the boundaries where one service hands off data to another. The key insight: at a seam, you can insert test probes without modifying the services themselves.

**Three seam types (adapted to the target system):**

| Feathers Seam Type | Target System Equivalent |
|-------------------|-------------------------|
| Link seams (swap library implementations) | Swap real output file paths with test fixture paths |
| Object seams (inject mock objects via interfaces) | Inject sentinel values into DB tables or file content |
| Preprocessing seams (use macros/env vars to alter behavior) | Set `INTEGRATION_TEST_MODE=1` env var to redirect output paths |

**Key patterns to adopt:**
1. The link seam pattern: the integration-tester does not need to run the full service. It can write a synthetic upstream artifact at the path the downstream service reads from, then verify the downstream service correctly consumes it. This decouples probe timing from timer schedules.
2. The seam-as-attachment-point: each seam is a specific file path, DB table, or API endpoint that both services agree on. The integration contract IS the seam definition.

---

### Source 7: VoltAgent Awesome Claude Code Subagents — test-automator Pattern

**URL:** [awesome-claude-code-subagents](https://github.com/VoltAgent/awesome-claude-code-subagents) | [test-automator agent](https://github.com/VoltAgent/awesome-claude-code-subagents/blob/main/categories/04-quality-security/test-automator.md)

**Core pattern:** The test-automator agent is a senior test automation engineer persona with a constrained tool set (Bash, Read, Write, Grep) and a structured execution mandate. It:
1. Analyzes codebase architecture and existing coverage (Existing Tests Analysis pattern)
2. Generates diverse test cases using Equivalence Class Partitioning and Boundary Value Analysis
3. Executes tests autonomously and debugs failures in a loop
4. Reports structured results

The wshobson/agents repo adds the full-stack-orchestration pattern: orchestrator chains `backend-architect → database-architect → frontend-developer → test-automator → security-auditor → deployment-engineer → observability-engineer` for boundary validation during feature development.

**Key patterns to adopt:**
1. The constrained tool set is essential. The integration-tester agent should have exactly: Bash (for file inspection, systemd queries, Python one-liners), Read (for contract and log files), Grep (for sentinel value search). No Write beyond test artifacts. No edit of service code.
2. The Equivalence Class Partitioning principle: test one normal case and one failure case at each seam. For aria-engine → ha-log-sync: normal (today's log file exists, schema valid) + failure (log file missing, simulate stale sync).
3. Structured result format: each probe emits a standard record — `seam_id`, `status` (PASS/FAIL/SKIP), `evidence` (what was checked), `latency_seconds`, `timestamp`. The orchestrator aggregates into a summary report.

---

### Source 8: Systemd Health Check Patterns

**URL:** [How to monitor systemd service liveness | Netdata](https://www.netdata.cloud/blog/systemd-service-liveness/) | [Monitoring SystemD services with Healthchecks.io](https://passbe.com/2022/healthchecks-io-systemd-checks/)

**Core pattern:** Systemd services expose health via three mechanisms: (1) active/failed state (`systemctl is-active`), (2) journal log recency (`journalctl -u <service> --since "5 min ago"`), (3) output file freshness (mtime check on the last-written artifact).

For the integration-tester, these become pre-probe health checks: before tracing through a seam, verify the upstream service is alive and has produced a recent artifact. A dead upstream service means the probe can fail fast with a clear cause rather than timing out.

**Key patterns to adopt:**
1. Pre-probe health check sequence: `systemctl is-active <service>` → check artifact mtime → proceed to trace. If pre-check fails, report `status: SKIP` with cause instead of running the trace and producing a false failure.
2. Journal log parsing as evidence: after a probe run, the agent should grep the relevant service's journal for error-level entries in the probe window. This catches failures that don't manifest in output files (e.g., service ran but silently dropped records).

---

## Synthesis: Best Patterns to Adopt

### Pattern 1: Sentinel Value Injection (Primary)

Inject a uniquely identifiable value at the upstream boundary of each seam. Verify it arrives at the downstream boundary. This is the core Cluster B trap: the sentinel reveals whether data actually flows across the seam, not just whether each side can process data in isolation.

Implementation for file-based seams:
```python
sentinel = f"INTEGRATION_PROBE_{datetime.utcnow().isoformat()}Z"
# Write sentinel into upstream artifact (or verify it exists in live data)
# Wait with timeout for sentinel to appear downstream
# Assert schema validity of the downstream artifact containing the sentinel
```

For seams that cannot accept injected data (live telemetry pipelines), use the freshness + schema check pattern instead: verify the downstream artifact was written within the expected window AND matches the declared schema.

### Pattern 2: Declarative Contracts as Source of Truth

Store one contract per seam in `docs/integration-tester/contracts/`. Each contract declares:

```json
{
  "seam_id": "aria-engine-to-hub",
  "producer_service": "aria-engine (systemd timer)",
  "consumer_service": "aria-hub (aria serve)",
  "interface_path": "~/ha-logs/intelligence/",
  "interface_type": "file_directory",
  "schema_file": "contracts/schemas/aria-engine-output.schema.json",
  "freshness_ttl_minutes": 1440,
  "probe_strategy": "freshness_and_schema",
  "notes": "Engine writes daily; hub reads on demand. Stale = engine timer failed."
}
```

The contract is the agent's instruction set. Adding a new seam = adding a contract file. No code changes.

### Pattern 3: Pre-Probe Health Check + 5-Step Trace

Each probe follows this sequence (adapted from OpenTelemetry integration test pattern):

1. **Health check** — `systemctl is-active <producer_service>` + artifact mtime check
2. **Clear state** — if using sentinel injection, ensure no prior sentinels pollute the check
3. **Trigger / Observe** — inject sentinel or identify latest live artifact
4. **Poll downstream** — with configurable timeout (default 30s for file-based, 5s for DB-based)
5. **Assert** — schema validation + freshness + sentinel presence (where applicable)

### Pattern 4: Black-Box Only, No Internal Inspection

The agent never reads Python source code of services or inspects in-memory state. It only reads:
- Files at declared interface paths
- SQLite DB tables (as flat files via `sqlite3` CLI)
- systemd journal output
- HTTP health endpoints where exposed

This forces the contracts to be complete — if the agent cannot verify a seam from external observables, the seam lacks a proper external interface and that is itself a finding.

### Pattern 5: Structured Result Emission

Every probe emits:

```json
{
  "seam_id": "aria-engine-to-hub",
  "timestamp": "2026-02-23T10:00:00Z",
  "status": "PASS",
  "checks": [
    {"name": "producer_alive", "result": "PASS", "evidence": "systemctl is-active aria-engine: active"},
    {"name": "artifact_freshness", "result": "PASS", "evidence": "current.json mtime 14 min ago, TTL 1440 min"},
    {"name": "schema_valid", "result": "PASS", "evidence": "validated against aria-engine-output.schema.json, 0 errors"},
    {"name": "downstream_reachable", "result": "PASS", "evidence": "aria hub API /health returned 200"}
  ],
  "latency_seconds": 2.3,
  "failures": []
}
```

The orchestrator aggregates all probe results into a Markdown summary report.

### Pattern 6: Shared Env Var Audit Probe

A fifth probe type — not a seam trace but an env var consistency audit. For each shared variable in `~/.env`:
- Identify all services that consume it (grep service files for variable name)
- Verify the variable is set and non-empty in the loaded environment
- Check that each consuming service is active (alive and recently active)

This catches the "key was rotated in ~/.env but one service still has the old value baked in" class of failure. It also catches services that expect a variable the env file no longer provides.

---

## Recommended Agent Structure

### Agent Identity

**File:** `~/.claude/agents/integration-tester.md` (or `agents/integration-tester.md` in the toolkit)
**Invocation:** Task tool (`integration-tester`) or `/integration-tester` slash command
**Model:** sonnet (diagnostic reasoning; not architecture-level complexity)
**Tools:** Bash, Read, Grep (no Write beyond `/tmp/integration-tester-results/`)

### Agent Prompt Structure

```markdown
# Integration Tester Agent

You are an integration boundary tester. Your job is to verify that data flows correctly
across service seams — not that individual services work, but that handoffs between them
work. You catch Cluster B bugs: the upstream passes its test, the downstream passes its test,
but the data never arrives correctly at the seam.

## Operating Principles

1. Black box only. Never read service source code to infer behavior. Only check external
   observables: files, DB tables, HTTP endpoints, systemd status.
2. Evidence-based assertions. Every PASS and FAIL must include quoted evidence (file content,
   command output, timestamp). No inferred assertions.
3. One probe per seam. Do not bundle multiple seams into one check — failures must be
   unambiguously attributable.
4. Fail fast with cause. If a pre-probe health check fails (service down, no recent artifact),
   report SKIP with cause. Do not run the full trace and report a misleading FAIL.
5. No side effects. Do not write to live service data paths. Test artifacts go to /tmp/.

## Seam Inventory

Load contracts from: docs/integration-tester/contracts/*.json
Run each contract's probe strategy in sequence.
Aggregate results into: /tmp/integration-tester-results/report-<timestamp>.md

## Probe Strategies

### freshness_and_schema
1. Check producer service is active (systemctl is-active)
2. Find most recent artifact at interface_path
3. Check artifact mtime is within freshness_ttl_minutes
4. Validate artifact schema against schema_file
5. PASS if all checks pass; FAIL with evidence on any failure

### sentinel_injection
1. Check producer service is active
2. Write sentinel file to producer's output staging area (if writable)
3. Wait up to timeout_seconds for sentinel to propagate to consumer's input path
4. Validate propagated artifact schema
5. Clean up sentinel artifacts

### db_row_trace
1. Check producer service is active
2. Query producer DB table for most recent row
3. Extract correlation ID from row
4. Query consumer DB table for row with matching correlation ID
5. Assert schema of consumer row

### env_audit
1. Read ~/.env for declared variables
2. For each variable, grep ~/.config/systemd/user/*.service for consumers
3. Verify variable is non-empty in current environment (source ~/.env)
4. Verify each consuming service is active
5. Report any mismatch between declared variables and consuming services

## Output Format

Write a Markdown report with:
- Summary table (seam_id, status, latency)
- Per-seam detail section with evidence
- Action items for each FAIL
```

### Seam Registry (Four Target Seams)

| Seam ID | Producer | Interface | Consumer | Probe Strategy | Key Risk |
|---------|----------|-----------|----------|---------------|----------|
| `aria-engine-to-hub` | aria engine timers | `~/ha-logs/intelligence/` (JSON files) | aria hub | freshness_and_schema | Engine timer fails silently; hub reads stale data |
| `ha-log-sync-to-engine` | ha-log-sync timer | `~/ha-logs/logbook/` (JSON files) | aria engine | freshness_and_schema | Sync fails; engine trains on missing or partial logbook |
| `telegram-brief-to-notion` | notion-tools sync timer | `~/Documents/notion/` (directory) | telegram-brief | freshness_and_schema | Notion sync fails; brief references stale local replica |
| `ollama-queue-to-timers` | ollama-queue daemon | `~/.local/share/ollama-queue/queue.db` | 10 Ollama-using timers | db_row_trace | Queue daemon down; timers silently fail on submit |

Plus the cross-cutting env audit probe targeting: `HA_URL`, `HA_TOKEN`, `TELEGRAM_BOT_TOKEN`, `CHAT_ID`, `NOTION_API_KEY`.

### Contract Files to Create

```
docs/integration-tester/
├── README.md                          — seam inventory and probe strategy guide
├── contracts/
│   ├── aria-engine-to-hub.json
│   ├── ha-log-sync-to-engine.json
│   ├── telegram-brief-to-notion.json
│   ├── ollama-queue-to-timers.json
│   └── env-audit.json
└── schemas/
    ├── aria-engine-output.schema.json
    ├── ha-logbook-entry.schema.json
    ├── notion-replica-index.schema.json
    └── ollama-queue-job.schema.json
```

### Slash Command

**File:** `commands/integration-tester.md`

```markdown
# Integration Tester

Runs integration boundary probes across all registered seams.

Usage:
- `/integration-tester` — run all probes
- `/integration-tester seam <seam-id>` — run one probe
- `/integration-tester env` — run env audit only

Reads contracts from: docs/integration-tester/contracts/
Writes report to: /tmp/integration-tester-results/report-<timestamp>.md
```

---

## Implementation Priority

| Priority | Task | Rationale |
|----------|------|-----------|
| 1 | Write seam contracts + schemas for all 4 seams | Contracts are the agent's source of truth; nothing else works without them |
| 2 | Implement `freshness_and_schema` probe | Covers 3 of 4 seams; highest immediate value |
| 3 | Implement env audit probe | Catches the env-rotation-breaks-multiple-services failure class |
| 4 | Write the agent prompt file | Orchestrates the probes |
| 5 | Create slash command | Invocation convenience |
| 6 | Implement `db_row_trace` for ollama-queue | Requires sqlite3 query against live DB; more complex |
| 7 | Wire into quality-gate.sh (optional) | Run integration probe on deploy; not blocking |

Confidence: High on priority 1-4 (clear requirements, known patterns). Medium on priority 6 (sqlite3 schema must be verified against actual queue.db structure first). Low on priority 7 (integration into quality gate increases gate latency; may be better as a separate daily check).

---

## Risks and Open Questions

**Risk 1: Live data timing.** The freshness_and_schema probe depends on the upstream service having run recently. If the integration tester is run during a dead period (service timer hasn't fired in 24+ hours due to machine sleep), the probe will FAIL for timing reasons unrelated to the seam health. Mitigation: use freshness_ttl_minutes conservatively (e.g., 1440 minutes = 24h for daily timers) and distinguish "stale" from "invalid schema."

**Risk 2: Sentinel injection side effects.** Writing sentinel files to upstream output directories could confuse the downstream service if the sentinel is malformed. Mitigation: the sentinel strategy should only be used for seams where a test-flag file path can be agreed upon (e.g., `~/ha-logs/intelligence/INTEGRATION_TEST_PROBE.json` — file the hub ignores by naming convention). For production seams, use freshness_and_schema (read-only) instead.

**Risk 3: Schema drift.** If the upstream service changes its output format without updating the contract schema file, the probe fails on every run — not because the seam is broken but because the contract is stale. Mitigation: the agent should detect schema validation failures and suggest running `update-contract --seam <id>` to regenerate the schema from the current live artifact. Add schema update to the service's deploy checklist.

**Open question:** Should the integration-tester run continuously (systemd timer, every 30min) or on-demand? Given the file-based, timer-driven architecture, the seams produce data on 15-minute to daily intervals. A 30-minute continuous probe would generate mostly SKIP results for intra-day intervals. Recommendation: run on-demand (slash command) and once daily (systemd timer at 07:00 after the overnight batch timers complete).

---

## Sources

- [Create custom subagents - Claude Code Docs](https://code.claude.com/docs/en/sub-agents)
- [From 2 weeks to 2 hours — cutting integration test time using Claude Code Subagents (Airwallex)](https://careers.airwallex.com/blog/using-claude-code-subagents/)
- [How to Write Integration Tests That Verify Trace Data with OpenTelemetry (OneUptime)](https://oneuptime.com/blog/post/2026-02-06-integration-tests-verify-trace-data-opentelemetry/view)
- [put-data-pipeline-under-test-with-pytest-and-great-expectations (Great Expectations Labs)](https://github.com/greatexpectationslabs/put-data-pipeline-under-test-with-pytest-and-great-expectations)
- [great_expectations — Always know what to expect from your data](https://github.com/great-expectations/great_expectations)
- [Pact — Introduction](https://docs.pact.io/)
- [Contract testing with Pact — Best Practices in 2025](https://www.sachith.co.uk/contract-testing-with-pact-best-practices-in-2025-practical-guide-feb-10-2026/)
- [Contract Testing vs. Schema Testing (Pactflow)](https://pactflow.io/blog/contract-testing-using-json-schemas-and-open-api-part-1/)
- [Seams | Testing Effectively With Legacy Code (InformIT / Michael Feathers)](https://www.informit.com/articles/article.aspx?p=359417&seqNum=2)
- [awesome-claude-code-subagents (VoltAgent)](https://github.com/VoltAgent/awesome-claude-code-subagents)
- [Intelligent automation and multi-agent orchestration for Claude Code (wshobson/agents)](https://github.com/wshobson/agents)
- [Claude Code QA agents (darcyegb/ClaudeCodeAgents)](https://github.com/darcyegb/ClaudeCodeAgents)
- [OpenTelemetry Context Propagation](https://opentelemetry.io/docs/concepts/context-propagation/)
- [Distributed Tracing Tools for Microservices 2026 (SigNoz)](https://signoz.io/blog/distributed-tracing-tools/)
- [How to monitor systemd service liveness (Netdata)](https://www.netdata.cloud/blog/systemd-service-liveness/)
- [Monitoring SystemD services with Healthchecks.io](https://passbe.com/2022/healthchecks-io-systemd-checks/)
- [microservices-testing examples (andreschaffer/microservices-testing-examples)](https://github.com/andreschaffer/microservices-testing-examples)
