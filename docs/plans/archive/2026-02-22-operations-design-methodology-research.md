# Operations Design & Design Methodology Research

> **Purpose:** Research military and business operations design methodology to enhance the autonomous coding toolkit's research phase integration.
>
> **Date:** 2026-02-22
>
> **Builds on:** `2026-02-22-research-phase-integration.md`, `2026-02-22-mab-research-round2.md`
>
> **Sources:** 4 parallel research agents (military doctrine, business methodology, cross-domain transfers, Notion workspace), 80+ web sources, 30+ Notion pages

---

## Executive Summary

Military and business design methodologies converge on a single meta-insight: **you cannot plan your way to a good outcome if you have not first correctly framed the problem.** Every framework examined — from JP 5-0 to McKinsey's issue trees to Toyota's A3 — enforces a formal gate between understanding the problem and designing a solution. The autonomous coding toolkit's proposed research phase (Stage 1.5) is this gate. This report maps 18 frameworks to concrete pipeline enhancements.

### Key Findings

1. **The problem statement is the most leveraged investment** in the entire process. Military doctrine (ADM), McKinsey (issue trees), and IDEO (POV statements) all formalize problem definition as a distinct, gated phase.
2. **Design and planning are different cognitive modes** that must be sequenced correctly. ADM → MDMP, Define → Ideate, A3 left side → right side. Our pipeline already does this (brainstorm → plan), but lacks the structured research that bridges them.
3. **Adversarial review must be institutionalized**, not optional. Red teams, murder boards, ACH, and believability-weighted voting all exist because groupthink is structural, not personal.
4. **End-state backward is the only coherent direction.** EBO, Amazon's Working Backwards, and RAND's RDM all design from desired outcome to required actions — never forward from available resources.
5. **Confidence levels and alternative analysis** (ICD 203) are the most underexploited transfer opportunity. Most software design docs do not express confidence or enumerate scored alternatives.

---

## Part I: Military Operations Design

### 1.1 Joint/Army Operational Design (JP 5-0, ADP 5-0)

Operational design is the cognitive work that **precedes** detailed planning. It answers: *What is the actual problem? What would success look like? What is the logical structure of the path from here to there?*

**The 13 Elements of Operational Design:**

| Element | Definition | Pipeline Analog |
|---------|-----------|-----------------|
| End State | Conditions that define success | PRD acceptance criteria |
| Center of Gravity | Source of power/capability | Core module under change |
| Decisive Points | Events/places that give marked advantage | Integration boundaries, API seams |
| Lines of Effort | Logical connections between decisive points | Batch sequences in plan |
| Direct vs. Indirect | Attack COG directly or erode supporting capabilities | Refactor vs. wrapper pattern |
| Operational Reach | Distance/duration before culmination | Context window budget |
| Culmination | Point where momentum can't be maintained | Context degradation threshold |
| Arranging Operations | Sequencing simultaneous/sequential actions | Batch ordering, parallelism |

**Center of Gravity Analysis (Strange's CG-CC-CR-CV Model):**

```
Center of Gravity → Critical Capabilities → Critical Requirements → Critical Vulnerabilities
```

Attack logic: identify CVs → strike them → degrades CRs → degrades CCs → neutralizes COG. For our pipeline: identify the critical vulnerability in the codebase (the weakest integration seam, the most fragile module) and address it first, not last.

**Sources:** JP 5-0 (2020), ADP 5-0 (2019), Joint Staff J-7 Planner's Handbook for Operational Design (2011), Strange & Iron CG-CC-CR-CV paper

### 1.2 Army Design Methodology (ADM) — Framing Before Planning

ADM was formalized after Iraq/Afghanistan exposed the failure of procedural planning against adaptive problems. It handles **ill-structured ("wicked") problems** — problems with no definitive formulation, no single correct answer, and no stopping rule.

**ADM → MDMP Continuum (the key insight):**

```
[ADM: Conceptual]                       [MDMP: Detailed]
    ─────────────────────────────────────────►
Understand      Visualize     Describe   Plan     Prepare   Execute   Assess
   │                │              │
Frame OE     Frame Problem   Op Approach
```

ADM outputs become MDMP inputs:
- ADM produces: problem statement + operational approach + commander's intent
- MDMP ingests those and produces: COAs, wargaming, decision, OPORD

**The Four ADM Activities:**

1. **Frame the Operational Environment** — Understand the systems at play (PMESII: Political, Military, Economic, Social, Infrastructure, Information). Map known/unknown/assumed.
2. **Frame the Problem** — Identify the tension between current state and desired end state. The problem statement articulates *why* the gap exists, not just that it exists.
3. **Develop the Operational Approach** — Generate a broad conceptual solution. This is a hypothesis, not a plan.
4. **Reframe** — When realities challenge the original frame, revise. This is doctrine, not failure.

**Pipeline mapping:** ADM's "Frame → Approach → Reframe" is exactly what our proposed research phase does: understand the codebase landscape (Frame OE), identify the real problem vs. the stated problem (Frame Problem), and produce a research artifact that informs PRD generation (Operational Approach).

**The Israeli Cautionary Tale (SOD):** Brigadier General Naveh's Systemic Operational Design applied critical theory (Foucault, Derrida, Deleuze) to operational art. It was intellectually ambitious but catastrophically unusable — in the 2006 Lebanon War, commanders were so absorbed in systems-thinking abstractions that tactical execution collapsed. **Lesson: design methodology must be sophisticated enough to handle real complexity but disciplined enough to generate actionable outputs.**

**Sources:** ATP 5-0.1 (2015), ADP 5-0 (2019), Small Wars Journal "Using ADM to Frame Problems" (2023), "Rise and Recession of Military Design Thinking" (StrategycentraI.io)

### 1.3 OODA Loop (Boyd) — Orientation as Design

Boyd's OODA (Observe-Orient-Decide-Act) is often trivialized as a speed loop. In reality, **Orient is the center of gravity** of the entire model — the decisive node where mental models are built and destroyed.

```
OBSERVE ──► ORIENT ──► DECIDE ──► ACT
   ▲           │                    │
   └── [Implicit Guidance & Control]│
             ◄───────────────────────┘
```

Orient synthesizes: genetic heritage, cultural traditions, prior experience, new information, and active analysis/synthesis. The output is an **updated mental model of reality**, which shapes what gets observed next and what gets decided.

**"Destruction and Creation" (Boyd, 1976):** The epistemological engine — drawing on Godel, Heisenberg, and thermodynamics:
- **Destructive deduction**: Breaking existing mental models apart (analysis)
- **Creative induction**: Recombining elements into new, more accurate models (synthesis)

Every model degrades as conditions change. Effective orientation requires continuously destroying and rebuilding mental models. **This maps directly to ADM's "reframe" and to our pipeline's context degradation problem** — stale context is a degraded mental model.

**Sources:** Boyd's "Discourse on Winning and Losing," OODA Loop Wikipedia, DAU "Revisiting Boyd" (2021)

### 1.4 Effects-Based Operations (EBO) — Designing Around Outcomes

EBO reverses the traditional planning direction:

```
Traditional: Forces Available → Targets → Effects (hoped for)
EBO: Desired Strategic End State → Required Effects → Targets/Actions
```

This is pure backwards planning from end state. It introduced the Effects Matrix: for each strategic objective, specify the required effect, target system, desired behavioral outcome, and assessment criteria.

**Mattis killed institutionalized EBO in 2008** — not because the concept was wrong, but because the tooling promised deterministic prediction in complex adaptive systems. The underlying logic (design from end state backward) survived and is embedded in current JP 5-0 doctrine.

**Pipeline mapping:** Our PRD already does backwards planning (acceptance criteria → implementation tasks). EBO's lesson is that the criteria must describe **effects** (behavioral changes in the system), not **targets** (files to modify).

**Sources:** Deptula "EBO: Change in the Nature of Warfare," Air & Space Forces "Assault on EBO," Mattis criticism (Air University)

### 1.5 Intelligence Preparation of the Battlefield (IPB)

IPB is the intelligence community's contribution to operational design — it structures environment analysis **before** planning begins.

**Four-Step IPB Process:**

| Step | Activity | Pipeline Analog |
|------|----------|-----------------|
| 1. Define the OE | Identify geographic area and time horizons | Identify affected files, modules, APIs |
| 2. Describe Environmental Effects | Analyze terrain using OAKOC | Map dependencies, integration seams, test coverage |
| 3. Evaluate the Threat | Build threat models and doctrine templates | Identify failure patterns, anti-patterns, tech debt |
| 4. Determine Threat COAs | Predict adversary courses of action | Predict where integration will break, where tests will fail |

**The pipeline connection:** IPB is literally what the research phase should produce — a structured analysis of the codebase landscape that feeds into PRD generation. The research artifact's `latent_issues` and `reuse_components` fields are IPB Steps 3 and 4.

**Sources:** FM 34-130, ATP 2-01.3, GlobalSecurity.org IPB Overview

### 1.6 Red Teaming and Adversarial Review

Formalized after post-9/11 planning failures. The Army stood up UFMCS (University of Foreign Military and Cultural Studies) at Fort Leavenworth in 2004.

**Four Red Team Functions:**
1. **Devil's Advocacy** — argue the strongest case against the current plan
2. **Alternative Analysis** — generate alternative interpretations
3. **Team A/Team B** — two competing teams argue opposite conclusions
4. **Cultural Empathy Analysis** — model how adversaries will perceive and respond

**Cognitive Biases Targeted:** Mirror imaging, groupthink, confirmation bias, cultural missteps.

**Murder boards:** Before a plan goes to the commander, a senior officer (often outside the chain of command) attacks the plan mercilessly. This is the military's institutionalized pre-mortem.

**Pipeline mapping:** Our MAB competitive mode is Team A/Team B. The lesson scanner is Devil's Advocacy. What's missing: **a formal alternative analysis step** in the research phase that enumerates competing approaches with explicit scoring.

**Sources:** UFMCS Red Team Handbook, Applied Critical Thinking Handbook v8.1, Army Press "Group Psychology of Red Teaming"

### 1.7 Mission Command — Design Through Intent

**Centralized intent, decentralized execution.** Commander's intent has three mandatory components:

1. **Purpose (Why)** — how the operation contributes to higher objectives
2. **Method (What/How broadly)** — enough frame without over-specifying
3. **End State** — desired conditions at conclusion

Mission Command acknowledges that **no plan survives contact**. Design compensates not by making the plan more detailed, but by ensuring everyone understands the logic well enough to adapt.

**Pipeline mapping:** The plan header (Goal, Architecture, Tech Stack) is commander's intent. The batch structure is mission orders. The quality gates are decision support templates. The agent executing each batch is the subordinate commander exercising disciplined initiative within intent.

**Sources:** ADP 6-0 (2019), Army.mil "Mission Command Requires Sharp Commander's Intent"

### 1.8 NATO COPD — The Full Pipeline

**Comprehensive Operations Planning Directive (COPD v3.1, 2023):**

| Phase | Name | Pipeline Stage |
|-------|------|---------------|
| 1 | Initial Situational Awareness | Brainstorming (explore context) |
| 2 | Strategic Assessment | Research phase (understand landscape) |
| 3 | Military Response Options | PRD generation (define options) |
| 4 | Strategic CONOPS Development | Plan writing (detailed execution) |
| 5 | Execution | Batch execution |
| 6 | Transition | Finishing branch (merge/PR/discard) |

The CPOE (Comprehensive Preparation of the Environment) is NATO's equivalent of IPB — adding political, economic, social, and information dimensions. **Our research phase is CPOE for code.**

**Sources:** NATO AJP-5, COPD V3.0 Implications paper, Major Roche "Using COPD at Tactical Level"

---

## Part II: Business Design Methodology

### 2.1 McKinsey/BCG — Hypothesis-Driven Design

**The 7-Step Problem-Solving Process:**

1. Define the problem (one-sentence key question)
2. Structure the problem (MECE issue tree / hypothesis tree)
3. Prioritize issues (impact × ease matrix)
4. Develop work plan (analysis, end-product, source, owner, timing per issue)
5. Conduct analyses
6. Synthesize findings (Pyramid Principle — answer first, then support)
7. Communicate

**MECE (Mutually Exclusive, Collectively Exhaustive):** Invented by Barbara Minto at McKinsey in the 1970s. If you cannot make your issue tree MECE, you do not understand the problem structure. This is a design forcing function.

**Day 1 Answer:** Form a testable initial hypothesis within 48-72 hours. The entire workplan is built to confirm or kill that hypothesis. This is not guessing — it is structured prediction from problem decomposition.

**Pyramid Principle:** Level 1 = governing thought (one sentence). Level 2 = 3-5 supporting arguments. Level 3 = underlying data. Answer-first communication — no building to a conclusion.

**Pipeline mapping:** The research artifact should produce a MECE decomposition of the problem space. The "Day 1 Answer" maps to the research phase's initial hypothesis about which approach will work. The hypothesis tree feeds PRD generation.

**Sources:** Minto "The Pyramid Principle," McKinsey "Seven-Step Problem-Solving Process," IGotAnOffer MECE Framework

### 2.2 IDEO/Stanford d.school — Design Thinking

**The Define Phase as Structured Research:**

The d.school's insight: "Define" is not writing a problem statement at a whiteboard. It is a synthesis discipline that transforms messy qualitative data into an actionable problem frame.

**Key tools:**
- **POV Statement:** `[User] needs [need] because [insight]` — user + need + insight, all three required
- **How Might We (HMW):** Reframe insights as design opportunities
- **Affinity Diagram:** Cluster observations into themes
- **Journey Map:** Visual timeline with emotional highs/lows

**Quality bar:** POV statements must be grounded in observed behavior, not assumptions. The "insight" must be non-obvious — something discovered, not assumed.

**Pipeline mapping:** The brainstorming phase already does empathize + define. The research phase adds rigor: POV statements become research questions, HMW questions become design alternatives, affinity diagrams become the structured research artifact.

**Sources:** Stanford d.school Process Guide, IxDF "5 Stages in Design Thinking"

### 2.3 Toyota — Genchi Genbutsu and A3

**Genchi genbutsu (go and see for yourself):** Before any countermeasure is proposed, Toyota requires physical presence at the actual site, direct observation, and handling of actual data. This is a quality gate, not a suggestion.

**A3 Problem Solving (fits on one sheet — the constraint is the point):**

| Left Side (Understanding) | Right Side (Action) |
|--------------------------|-------------------|
| Background/context | Target condition |
| Current condition (metrics, photos from gemba) | Countermeasures |
| Problem statement (measurable delta) | Implementation plan |
| Root cause analysis (5 Whys, Ishikawa) | Follow-up/confirmation |

**Value Stream Mapping:** Walk the stream physically. Map every step. Record cycle time, changeover time, uptime, batch size, WIP. Calculate lead time vs. value-added time ratio. The gap between current and future state maps defines the design scope.

**Pipeline mapping:** The research phase is our gemba walk — direct codebase observation before proposing changes. The A3's left side (current condition + root cause) maps to `reuse_components` and `latent_issues` in the research artifact. The constraint of fitting on one page maps to our 6000-char context budget.

**Sources:** Lean Enterprise Institute A3 Guide, Toyota A3 Problem-Solving website

### 2.4 Amazon — Working Backwards

**PR-FAQ:** Write the press release before building. Forces clarity because writing requires making implicit assumptions explicit.

**Press Release structure:** Headline (customer benefit), problem paragraph (pain being solved), solution paragraph (how it solves it), customer quote (captures experience).

**Internal FAQ:** The hard questions — how big is the market, what's the business model, what are the top 3 risks, how do we measure success, what does the team need?

**6-Page Narrative Memo:** Meetings begin with 20-30 minutes of silent reading. Questions only after everyone has read. This eliminates the HiPPO problem (Highest Paid Person's Opinion dominating).

**Disagree and Commit:** Disagree loudly with evidence before the decision. Once decided, execute fully. The memo creates a decision audit trail.

**Pipeline mapping:** Our PRD is a lightweight PR-FAQ (acceptance criteria = customer benefits as shell commands). The research artifact is the internal FAQ (what are the risks, what have we missed, what do we need). The plan document is the 6-pager.

**Sources:** The PRFAQ "Amazon Writing Culture," Writing Cooperative "Anatomy of an Amazon 6-pager"

### 2.5 Bridgewater — Systematized Disagreement

**Idea Meritocracy = Radical Truth + Radical Transparency + Believability-Weighted Decision Making**

**Issue Log:** Every mistake, disagreement, or problem is entered into a centralized log visible to the whole firm. Problems surface immediately. Patterns become training data.

**Believability-Weighted Voting:** Not all opinions are equal. Opinions weighted by demonstrated track record (Baseball Cards). If equal-weighted and believability-weighted votes diverge, discussion resumes.

**Pipeline mapping:** Our `logs/failure-patterns.json` is a lightweight Issue Log. The MAB's Thompson Sampling is believability-weighted voting — arms that have demonstrated better outcomes get more weight. The lesson system compounds learning like Baseball Cards.

**Sources:** Bridgewater Principles website, Bastian Moritz "Believability-Weighted System"

### 2.6 RAND Corporation — Research-to-Recommendation Pipeline

**Ten Practical Principles for Policy Analysis:**

1. Fit tools to the problem (simplest that work)
2. Define the problem before selecting methods
3. Identify the decision maker
4. Explain how the choice depends on key judgments
5. Open and explicit analysis (hidden assumptions = persistent error)
6. Use multiple methods (triangulate)
7. Examine uncertainty explicitly (sensitivity analysis)
8. Consider feasibility (political, organizational, technical)
9. Communicate clearly
10. Document (reproducible and auditable)

**Robust Decision Making (RDM):** Instead of optimizing under expected conditions, generate a wide range of possible futures and find strategies that perform acceptably across the widest range. Design for robustness, not optimality.

**Key insight:** Findings, Implications, and Recommendations are strictly separated. Conflating them is an analytical error.

**Pipeline mapping:** The research phase should separate findings (what the codebase analysis shows) from implications (what this means for the design) from recommendations (what we should do). RDM maps to our MAB — instead of picking the "best" approach, find one that degrades gracefully.

**Sources:** RAND "Ten Practical Principles" (PEA3956-1), RAND "Systems Analysis: A Tool for Choice" (P4860)

### 2.7 Wardley Mapping — Situational Awareness Before Strategy

**Core insight:** You cannot have a strategy without a map.

**Two axes:**
- Y-axis: Value Chain (visibility to user — top = user needs, bottom = infrastructure)
- X-axis: Evolution (Genesis → Custom → Product → Commodity)

**Why evolution matters:** The evolutionary stage determines the correct design approach:
- Genesis: explore, expect failure, protect from efficiency pressure
- Custom Built: develop capability, understand best practices
- Product: optimize, differentiate, watch for commoditization
- Commodity: buy don't build, focus on operational efficiency

**Strategic error:** Applying the wrong approach to the evolutionary stage. Innovating on commodity components wastes resources. Standardizing genesis components destroys competitive advantage.

**Pipeline mapping:** The research phase should classify components by maturity. A new module being built from scratch (genesis) needs different treatment than wiring into an existing well-tested library (commodity). This classification informs batch ordering and risk assessment.

**Sources:** Wardley Maps Wikipedia, Aktia Solutions "Introduction to Wardley Maps"

### 2.8 TOGAF ADM — Separation of Concerns

Enterprise architecture's contribution: separate "what the business needs" from "how technology delivers it."

**Phase A (Architecture Vision)** must be approved before **Phase B (Business Architecture)** which must be approved before **Phase C (Technology Architecture)**. Each is a gate.

**Pipeline mapping:** Our pipeline already enforces this: brainstorm (what) → plan (how) → execute (build). The research phase strengthens Phase A by adding structured codebase analysis.

### 2.9 Stage-Gate — The Innovation Pipeline

Robert Cooper's foundational research: **most product failures are failures of front-end definition, not execution.**

**The Fuzzy Front End (Stages 0-2):**
- Stage 0: Discovery/Ideation (generate candidate ideas)
- Stage 1: Scoping (rapid, low-cost preliminary assessment)
- Stage 2: Build the Business Case (primary design phase — product definition)

**Gate anatomy:** Deliverables (quality, not completion) + Criteria (Must-Meet pass/fail + Should-Meet scored) + Outputs (Go/Kill/Hold/Recycle).

**The Product Definition document (Gate 2)** is the key quality gate artifact. Cooper's research: projects with a stable, well-defined product definition before development are **3x more likely to succeed**.

**Pipeline mapping:** Our quality gates are Stage-Gate gates. The research phase is Stage 1 (scoping). The PRD is the Product Definition at Gate 2. The Go/Kill/Hold/Recycle decision maps to our research gate (proceed / block / defer).

**Sources:** Stage-Gate International overview, Toolshero "Stage Gate Process by Robert Cooper"

---

## Part III: Cross-Domain Transfers

### 3.1 Agile's Military Roots

**The lineage is biographical, not metaphorical.** Jeff Sutherland graduated West Point (1964), flew 100 combat missions over North Vietnam, was personally trained by John Boyd.

**OODA → Scrum mapping:**

| OODA | Scrum |
|------|-------|
| Observe | Sprint Review, Daily Standup |
| Orient | Backlog Refinement, Retrospective |
| Decide | Sprint Planning |
| Act | Sprint execution |

**Auftragstaktik → "Self-organizing teams":** Commanders specify intent and objective (what/why), leave method (how) to subordinates. Product Owners set the mission, teams determine execution.

**Full lineage:** US military WWII quality programs → Deming → Toyota TPS → Lean Manufacturing → Lean Software Development → Agile Manifesto (2001).

### 3.2 Chaos Engineering = Civilian Red Teaming

**Origin:** Prussian Kriegsspiel (1824) → RAND Cold War simulations → NSA Multics evaluation (1970s) → SEAL Team Six Red Cell → Netflix Chaos Monkey (2010).

| Simian Army Tool | Military Equivalent |
|-----------------|-------------------|
| Chaos Monkey (kills instances) | Attrition wargame |
| Latency Monkey (injects delays) | Communications degradation exercise |
| Chaos Kong (kills regions) | Theater-level degraded ops |

**The proof case:** Netflix's 2015 DynamoDB outage — Netflix experienced far less downtime than peers because chaos engineering had already forced them to solve the exact failure modes. This is "train as you fight."

### 3.3 ICD 203 — The Underexploited Transfer

**Nine Analytic Tradecraft Standards:**

1. Describe quality and credibility of sources
2. Express uncertainties with explicit probability language
3. Distinguish information from assumptions and judgments
4. Incorporate alternative analysis (enumerate competing hypotheses)
5. Demonstrate relevance and address implications
6. Use clear argumentation
7. Explain change from previous judgments
8. Make accurate assessments
9. Use effective visual information

**Analysis of Competing Hypotheses (ACH):** List all hypotheses; score evidence against each; identify which hypothesis has the **least contradicting evidence** (not the most supporting — a critical logical distinction).

**The gap:** Most software design docs do not express confidence levels, do not enumerate scored alternatives, and do not apply ACH. This is the single highest-value transfer opportunity from military/intelligence to software design.

**Pipeline mapping:** The research artifact should include confidence levels on latent issues and design changes, scored alternatives for architectural decisions, and explicit distinction between findings (data), implications (meaning), and recommendations (action).

### 3.4 Cynefin — Match Design Approach to Problem Type

| Domain | Characteristics | Design Approach |
|--------|---------------|----------------|
| Clear | Known cause-effect; best practices exist | Sense → Categorize → Respond |
| Complicated | Knowable; requires expert analysis | Sense → Analyze → Respond |
| Complex | Emergent; cause-effect only in retrospect | Probe → Sense → Respond |
| Chaotic | No discernible cause-effect | Act → Sense → Respond |

**The critical insight:** Applying Complicated-domain thinking (expert analysis, detailed upfront design) to Complex-domain problems is a primary cause of software project failure. Waterfall's failure mode is treating product development as Complicated when it's Complex.

**Pipeline mapping:** The research phase should classify the problem domain. A well-understood CRUD endpoint is Clear/Complicated — spec it, build it. A novel ML pipeline integration is Complex — probe with spikes, learn, then plan. This classification should influence batch strategy (detailed plan vs. exploratory spike).

### 3.5 NASA V-Model and Formal Design Reviews

**Review sequence:** MCR → SRR → PDR → CDR → TRR → ORR. Each is a gate.

**The lesson commercial software ignores:** Requirements traceability. NASA traces every design decision to a requirement and every requirement to a test. Most commercial software cannot.

**Columbia lesson:** Dissenting technical voices were filtered out before reaching decision-makers. Now codified: the design review process must create conditions for technical dissent to surface.

**Pipeline mapping:** Our PRD → plan → test structure is a lightweight V-model. Requirements traceability = PRD task IDs referenced in plan steps. The lesson about dissent = why the lesson scanner and MAB competitive mode exist.

### 3.6 Verified Transfer Cases

| Transfer | Origin | Destination | Vector |
|----------|--------|-------------|--------|
| OODA → Scrum | Boyd/USAF | Agile | Biographical (Sutherland) |
| AAR → Blameless Postmortem | Army NTC | Google SRE | Cultural (aviation CRM) |
| Red Team → Threat Modeling | RAND/NSA | Microsoft STRIDE, MITRE ATT&CK | Institutional (FFRDCs) |
| V-Model → Regulated Software | NASA/DoD | DO-178C, ISO 26262, IEC 62304 | Regulatory pressure |
| Kill Chain → DevSecOps | DoD | Platform One, Kessel Run | Bidirectional (Palantir/Anduril) |
| Red Cell → Penetration Testing | SEAL Team Six | Commercial security | Personnel migration |

---

## Part IV: Notion Workspace Findings

Your workspace contains deep applied coverage of military doctrine — primarily applied to career transition planning, not software pipeline design. Key assets:

### 4.1 Military Doctrine (Deep Coverage)

| Asset | File | Content |
|-------|------|---------|
| JP 5-0 Operational Design Reference | `notion/.../2fc24971-...ab9b-...` | Full 13 elements, MOP vs. MOE |
| ODF Generator Agent v1 | `notion/.../81382326-...` | AI agent grounded in JP 5-0, ADP 5-0, FM 3-05.20 |
| ODF Generator Agent v2 (JADC2) | `notion/.../efa33bcd-...` | JADC2 Sense-Make-Act, Mission Command, speed-of-relevance |
| Dynamic ODF System | `notion/.../29e24971-...` | Multi-agent architecture: Intake → Research → 6 LOE Agents → Risk → Decision → Sync |
| Strategic Frameworks & Methodologies | `notion/.../2a524971-...` | MDMP 7-step, IPB 4-step, CARVER matrix with scored examples |
| Military Intelligence System Prompt | `notion/.../29c24971-...` | IPB, F3EAD, CARVER, PMESII-PT, COG analysis, ICD 203 |

### 4.2 Decision Science (Deep Coverage)

| Asset | Content |
|-------|---------|
| Kahneman Deep Dive | System 1/2, prospect theory, planning fallacy, pre-mortem, reference-class forecasting |
| Superforecasting Brief | Tetlock's 10 Commandments, Brier scoring, granular belief updating |
| 20 Cognitive Biases | Individual and team debiasing: pre-mortem, outside view, devil's advocate |
| 8 Elements of Thought | Richard Paul/Linda Elder critical thinking framework |
| Think Like a Rocket Scientist | First principles ↔ IPB, backcasting ↔ MDMP reverse planning |

### 4.3 Business/Program Frameworks (Broad Coverage)

| Asset | Content |
|-------|---------|
| Framework Encyclopedia | Product (JTBD, RICE), Ops (OKRs, Lean, Six Sigma), PM (PMBOK, Agile), Program (SAFe, Stage-Gate, EVM) |
| Lean Six Sigma Green Belt | Job Instruction 4-Step, SWOT, FMEA, VSM, A3/Kaizen |
| SAFe Portfolio Vision | Maps to Commander's Intent — stable strategic direction enabling tactical flexibility |
| Policy Analysis | Bardach's Eightfold Path, Gil's Framework, 6-E Framework |

### 4.4 Coverage Gaps (Opportunities)

| Framework | Workspace Status | Opportunity |
|-----------|-----------------|-------------|
| Wardley Mapping | One shallow reference | Deep dive would complement strategic planning |
| Cynefin | Book in library, no applied page | Critical for problem classification |
| Amazon Working Backwards | Not present | PR-FAQ methodology applicable to PRD generation |
| RAND RDM | Not present | Robust decision-making under uncertainty |
| ICD 203 full implementation | Referenced but not applied | Confidence levels for design decisions |

---

## Part V: Cross-Framework Synthesis

### 5.1 The Universal Design Phase Meta-Pattern

Every framework has a distinct gate between "understanding the problem" and "designing a solution":

| Framework | Problem Definition Artifact | Gate |
|-----------|----------------------------|------|
| JP 5-0 / ADM | Problem statement + operational approach | ADM → MDMP transition |
| McKinsey | MECE issue tree + Day 1 Answer | Week 1 hypothesis review |
| IDEO d.school | POV statement (user + need + insight) | POV validation |
| Toyota | A3 left side (current condition + root cause) | A3 review |
| Amazon | PR-FAQ (customer pain + internal FAQ) | PR-FAQ review |
| Bridgewater | Issue Log + believability-weighted framing | Believability vote |
| RAND | Problem framing document | Peer review |
| Wardley | Value chain map + evolution placement | Doctrine check |
| TOGAF | Business Architecture baseline + gap analysis | Architecture Vision approval |
| Stage-Gate | Product Definition document | Gate 2 (Go to Development) |
| ICD 203 | ACH matrix + confidence levels | Alternative analysis review |

**Our pipeline currently:** Brainstorm (problem definition) → PRD (acceptance criteria) → Plan (detailed tasks). The research phase fills the gap between brainstorm and PRD — it is the structured analysis that every framework above demands before solution commitment.

### 5.2 What Military Doctrine Knows That Most Frameworks Don't

1. **The plan will fail contact.** Design for intent, not method. Commander's intent matters more than the synchronization matrix. Our plan header (Goal, Architecture) is intent; the batch details are the synchronization matrix.

2. **Orientation is the competitive advantage.** Boyd: the OODA loop is won or lost in Orient. The quality of pre-execution cognitive work determines execution quality more than execution technique.

3. **Adversarial review must be structural, not optional.** Groupthink is a property of cohesive teams under pressure, not a personality failure. Red teams exist because the alternative consistently produces plans with unexamined fatal assumptions.

4. **Reframing is doctrine, not failure.** ADM's fourth activity (Reframe) acknowledges that the initial problem frame will be wrong. The pipeline must support mid-execution reframing without treating it as a failure.

### 5.3 The Underexploited Transfers

**Highest-value transfers not yet in our pipeline:**

| Transfer | Source | Application | Impact |
|----------|--------|-------------|--------|
| Confidence levels | ICD 203 | Research artifact fields get `confidence: high/medium/low` | Prevents false precision in design decisions |
| ACH scoring | ICD 203 | Enumerate design alternatives, score against evidence | Prevents premature convergence |
| Cynefin classification | Snowden | Classify problem domain per batch → choose execution strategy | Prevents waterfall-on-complex errors |
| Wardley evolution | Wardley | Classify components by maturity → inform build-vs-reuse | Prevents innovating on commodity |
| COG-CC-CR-CV analysis | Strange | Identify critical vulnerability in codebase → address first | Prevents leaving worst risk for last |
| RDM robustness | RAND | Design for acceptable performance across futures, not optimal in one | Prevents brittle architecture |
| Murder board | Military | Formal adversarial review of plan before execution | Prevents groupthink in plan generation |

### 5.4 Revised Pipeline with Operations Design Integration

```
Stage 0   : Roadmap (multi-feature sequencing)
Stage 0.5 : Problem Framing ← NEW (ADM "Frame the Problem")
              - MECE decomposition of problem space
              - Cynefin domain classification
              - COG-CC-CR-CV analysis of codebase
Stage 1   : Brainstorm (explore intent → design → approval)
Stage 1.5 : Research ← ENHANCED
              - IPB-style codebase analysis (4-step)
              - ACH scoring of design alternatives
              - Confidence levels on all findings
              - Wardley evolution classification of components
              - Findings / Implications / Recommendations separation (RAND)
              - Research gate (Go/Kill/Hold)
Stage 2   : PRD (machine-verifiable acceptance criteria)
Stage 2.5 : Murder Board ← NEW (formal adversarial plan review)
              - Red team attacks the plan
              - Alternative analysis required
              - Pre-mortem: "imagine this failed — what went wrong?"
Stage 3   : Plan (TDD-structured tasks at 2-5 minute granularity)
Stage 3.5 : Isolate (git worktree)
Stage 4   : Execute (batch execution with quality gates)
Stage 5   : Verify (evidence-based gate)
Stage 5.5 : AAR ← NEW (after-action review)
              - What was planned vs. what happened
              - Root causes of deviations
              - Lessons for failure-patterns.json
Stage 6   : Finish (merge / PR / keep / discard)
```

### 5.5 Research Artifact Schema (Enhanced)

Based on the cross-framework synthesis, the research artifact should include:

```json
{
  "feature": "string",
  "date": "YYYY-MM-DD",
  "domain_classification": "clear | complicated | complex | chaotic",
  "problem_frame": {
    "current_state": "string (A3 left side — what is happening now)",
    "desired_state": "string (end state — what success looks like)",
    "gap": "string (why the gap exists, not just that it exists)",
    "root_causes": ["string (5 Whys / Ishikawa results)"]
  },
  "mece_decomposition": [
    {"branch": "string", "sub_branches": ["string"], "priority": "high|medium|low"}
  ],
  "alternatives": [
    {
      "approach": "string",
      "evidence_for": ["string"],
      "evidence_against": ["string"],
      "confidence": "high|medium|low",
      "recommended": true
    }
  ],
  "cog_analysis": {
    "center_of_gravity": "string (core module/capability under change)",
    "critical_capabilities": ["string"],
    "critical_requirements": ["string"],
    "critical_vulnerabilities": ["string (address these first)"]
  },
  "reuse_components": [
    {"requirement": "string", "file": "string", "gap": "none|partial|full", "evolution": "genesis|custom|product|commodity"}
  ],
  "latent_issues": [
    {"file": "string", "line": 0, "description": "string", "severity": "critical|high|medium|low", "confidence": "high|medium|low", "blocking": true}
  ],
  "design_changes": [
    {"change": "string", "rationale": "string", "blocking": true, "alternatives_considered": ["string"]}
  ],
  "findings_vs_implications_vs_recommendations": {
    "findings": ["string (what the data shows)"],
    "implications": ["string (what this means for the design)"],
    "recommendations": ["string (what we should do)"]
  },
  "prd_scope_delta": {"tasks_removable": [], "tasks_added": [], "estimated_task_reduction": 0}
}
```

---

## Part VI: Implementation Priorities

### Tier 1 (Highest value, lowest effort — enhance existing stages)

1. **Add confidence levels to research artifact** — every finding gets `high/medium/low` confidence
2. **Add alternatives scoring** — enumerate 2-3 approaches with evidence for/against (ACH-lite)
3. **Separate findings/implications/recommendations** in research output (RAND discipline)
4. **Add Cynefin classification** to plan header — determines execution strategy per batch

### Tier 2 (High value, moderate effort — new lightweight stages)

5. **Murder Board script** — adversarial review of generated plan before execution (pre-mortem + devil's advocacy)
6. **AAR step** after execution — structured what-planned-vs-what-happened with root cause → failure-patterns.json
7. **COG-CC-CR-CV analysis** in research phase — identify critical vulnerabilities to address first

### Tier 3 (High value, significant effort — new capabilities)

8. **Problem Framing stage** (Stage 0.5) — MECE decomposition + Cynefin classification before brainstorming
9. **Wardley evolution classification** of components — inform build-vs-reuse decisions
10. **Full ICD 203 implementation** — confidence vocabulary, source credibility, alternative analysis mandated

---

## Sources

### Military Doctrine
- JP 5-0 Joint Planning (2020)
- ADP 5-0 The Operations Process (2019)
- ATP 5-0.1 Army Design Methodology (2015)
- Joint Staff J-7 Planner's Handbook for Operational Design (2011)
- FM 34-130 Intelligence Preparation of the Battlefield
- ADP 6-0 Mission Command (2019)
- NATO AJP-5 Allied Joint Doctrine for Planning
- NATO COPD v3.1 (2023)
- UFMCS Red Team Handbook / Applied Critical Thinking Handbook v8.1
- Boyd, "Discourse on Winning and Losing" / "Destruction and Creation" (1976)
- Strange & Iron, "Understanding Centers of Gravity and Critical Vulnerabilities"

### Business Methodology
- Minto, "The Pyramid Principle" (McKinsey)
- Stanford d.school Design Thinking Process Guide
- Lean Enterprise Institute A3 Guide / Toyota Production System
- Amazon PR-FAQ / Working Backwards methodology
- Dalio, "Principles" (Bridgewater)
- RAND "Ten Practical Principles for Policy Analysis" (PEA3956-1)
- Wardley, "Wardley Maps" (Creative Commons)
- TOGAF Standard (The Open Group)
- Cooper, "Winning at New Products" (Stage-Gate)

### Cross-Domain
- Sutherland/Boyd OODA-to-Scrum lineage (Scrum Inc.)
- Netflix Chaos Monkey / Simian Army (Gremlin, SEI CMU)
- ICD 203 Analytic Standards (DNI)
- NASA Systems Engineering Handbook (NASA-HDBK-2203)
- Snowden, Cynefin Framework (Wikipedia, Deakin University)
- DoD Enterprise DevSecOps Fundamentals v2.5 (dodcio.defense.gov)
- Google Design Docs (Industrial Empathy / Malte Ubl)
- Team Topologies (Skelton & Pais)

### Notion Workspace
- JP 5-0 Operational Design Reference, ODF Generator Agents v1/v2
- Strategic Frameworks & Methodologies (MDMP, IPB, CARVER applied)
- Military Intelligence System Prompt (IPB, F3EAD, ICD 203)
- Kahneman Deep Dive, Superforecasting Brief
- Framework Encyclopedia, Lean Six Sigma Green Belt
- Think Like a Rocket Scientist, Kill Chain, Hundred-Year Marathon
