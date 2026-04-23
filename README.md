# M365 Compliance Skills & Agents

Claude Code skills and subagents for configuring Microsoft 365 tenants against regulatory and industry frameworks. Built for UK / US / EMEA engagements operating at dozens-to-thousands of tenants.

## Architecture

Three layers, deliberately separated so framework changes don't require deployment rewrites and deployment tooling can be reused across frameworks.

```
skills/
├── frameworks/          Layer 1 — domain knowledge, tool-light
│   ├── cis-m365/        CIS Microsoft 365 Foundations Benchmark (prescriptive technical)
│   ├── dora/            EU Digital Operational Resilience Act (financial entities)
│   ├── nis2/            EU NIS 2 Directive (essential/important entities)
│   └── hipaa/           US HIPAA Security + Privacy + Breach Notification Rules
└── mapping/             Layer 3 — cross-framework reasoning
    └── control-map/     Bidirectional control mapping, gap analysis, evidence consolidation

agents/                  Layer 2 — workload-scoped deployment agents (framework-agnostic)
├── m365-conditional-access.md         CA policies, auth strengths, sign-in what-if
├── m365-entra.md                      Identity core (non-CA): auth methods, PIM, guest, app governance
├── m365-intune.md                     Device compliance, config profiles, endpoint security, app protection
├── m365-purview.md                    Sensitivity labels, DLP, retention, audit, Insider Risk
├── m365-defender.md                   Defender XDR (DfO, MDE, MDI, MDA, Secure Score, Attack Sim)
├── m365-exchange-sharepoint-teams.md  Mail-flow, sharing, meeting/messaging policies
└── m365-tenant-baseline.md            Orchestrator — sequences all workload agents with ring-based rollout

baselines/               Config-as-data — the actual settings applied to tenants
├── schema/              JSON schemas: baseline document + evidence bundle manifest
├── global/              Tenant-agnostic defaults (break-glass, audit log default)
├── profiles/            Populated framework profiles — cis-l1, cis-l1-l2, dora-overlay, nis2-overlay, hipaa-overlay
└── examples/            Reference starter baselines

scripts/                 Runnable PowerShell 7 scan primitives (the portal's scan engine source)
├── common/
│   ├── Connect-Tenant.ps1           Auth abstraction (GDAP / app-reg / interactive, Key Vault secrets)
│   ├── Resolve-Baseline.ps1         Layered merger — global + profile chain + overrides → resolved JSON
│   ├── Compare-TenantState.ps1      Diff engine — resolved baseline + scan bundle → findings array
│   └── diff-rules.yaml              Starter rule set (~30 controls) consumed by the diff engine
└── scan/
    ├── Invoke-TenantScan.ps1        Orchestrator — signed evidence bundle
    ├── Invoke-EntraScan.ps1
    ├── Invoke-ConditionalAccessScan.ps1
    ├── Invoke-ExchangeScan.ps1
    ├── Invoke-SharePointScan.ps1
    ├── Invoke-TeamsScan.ps1
    ├── Invoke-PurviewScan.ps1
    ├── Invoke-DefenderScan.ps1
    ├── Invoke-IntuneScan.ps1
    └── Invoke-PowerBIScan.ps1

docs/                    Operational runbooks (smoke test, future apply procedures)
└── smoke-test.md        End-to-end practitioner checklist: connect → scan → resolve → diff

.github/workflows/       CI — schema validation, CSV sanity, PSScriptAnalyzer, markdownlint
```

### Why three layers

- **Frameworks change slowly, on regulator time.** Isolating them keeps regulation-driven edits to one directory.
- **Deployment is workload-specific and tool-heavy.** Conditional Access, Intune, and Purview have different APIs, different idempotency rules, and different blast radii. One agent per workload keeps permission scopes and failure modes contained.
- **Cross-mapping is a distinct reasoning task.** Same control satisfies DORA Art 9, NIS 2 Art 21(2)(d), HIPAA §164.312(a), CIS section X. Consolidating that is its own skill, not something to bake into every framework skill.

### How the layers interact

A typical "configure Tenant X to DORA Level 1" flow:

1. User (or orchestrator) invokes the **DORA skill** to load requirements.
2. DORA skill references **control-map** to translate each DORA article to M365-specific controls.
3. **m365-tenant-baseline** orchestrator selects a baseline from `baselines/examples/` matching the framework profile.
4. Orchestrator delegates to workload agents (`m365-conditional-access`, `m365-entra`, `m365-purview`, …) to apply config.
5. Each workload agent applies idempotently, reports drift, and returns evidence artefacts.
6. **evidence-consolidation** (within control-map) packages evidence against all frameworks the tenant is subject to.

## Scale considerations (dozens → thousands of tenants)

This suite assumes:

- **Config-as-data.** Tenant settings live in versioned JSON/YAML baselines. Agents diff current state vs. baseline and apply changes; they do not carry settings in prose.
- **Idempotency first.** Every deployment action is safe to re-run. Partial failures are expected at scale.
- **Multi-tenant auth context.** Agents expect to be invoked with a tenant identifier and an already-authenticated Graph/PowerShell session (delegated, app-only, or Partner Center / GDAP). They do not manage credentials.
- **Drift detection is a first-class operation.** `--check` / read-only modes produce a drift report without changing state.
- **Phased rollouts.** Baselines carry a `rollout` stanza describing ring assignment (pilot → broad).

See [baselines/schema/baseline.schema.json](baselines/schema/baseline.schema.json) for the shape.

## Installation

Skills and agents in this repo are authored under the workspace; to use them with Claude Code:

```bash
# Symlink (recommended during iteration):
ln -s "/Users/timothy.oelkers/VS Code/Agent & Skills/skills"  ~/.claude/skills
ln -s "/Users/timothy.oelkers/VS Code/Agent & Skills/agents" ~/.claude/agents

# Or copy for a stable snapshot:
cp -R "/Users/timothy.oelkers/VS Code/Agent & Skills/skills"  ~/.claude/
cp -R "/Users/timothy.oelkers/VS Code/Agent & Skills/agents" ~/.claude/
```

For project-scoped use (shared with a team via git), put this whole tree inside a repo and move `skills/` and `agents/` to `.claude/skills` and `.claude/agents` at the repo root.

## Status

- **CIS M365 Benchmark** — skill populated for **v6.0.1** (released 31 October 2025; 140 controls across Entra / Exchange / SharePoint / OneDrive / Teams / Power BI). [controls.md](skills/frameworks/cis-m365/controls.md) is a working draft of ~130 recommendations — **verify against the official CIS Workbench v6.0.1 PDF** before customer-facing use.
- **DORA** — skill populated with 5-pillar structure, article-level reference, incident-reporting cadence (4h / 72h / 1mo), Chapter V third-party risk.
- **NIS 2** — skill populated with Art 20 governance, Art 21(2) ten measures, 24h / 72h / 1mo reporting. National transposition annex is a stub — populate per-Member-State as engagements appear.
- **HIPAA** — skill populated with Security + Privacy + Breach Notification Rules. **NPRM status verified April 2026:** comment period closed March 2025, final rule on HHS regulatory agenda for **May 2026** with ~240-day compliance runway.
- **Control mapping** — schema + 28 mapping rows across 7 reference controls (CIS / DORA / NIS 2 / HIPAA), gap-analysis procedure, evidence packaging spec.
- **Deployment agents** — all 7 built: conditional-access, entra, intune, purview, defender, exchange-sharepoint-teams, tenant-baseline orchestrator.
- **Baselines** — schema (baseline + evidence bundle manifest), global defaults, break-glass reference, and five populated profiles: `cis-l1`, `cis-l1-l2`, `dora-overlay`, `nis2-overlay`, `hipaa-overlay`, plus a tenant registry template.
- **Scan primitives** — nine PowerShell 7 scan scripts (Entra, CA, Exchange, SharePoint/OneDrive, Teams, Purview, Defender, Intune, Power BI) plus an orchestrator (`Invoke-TenantScan.ps1`) that emits a SHA-chained, optionally RS256-signed evidence bundle matching the manifest schema.
- **Baseline merger** — [`Resolve-Baseline.ps1`](scripts/common/Resolve-Baseline.ps1) layers global + profile chain + overrides with named-merge semantics (`replaces:` directives, tilde/caret version pins) and emits the resolved target state.
- **Diff engine** — [`Compare-TenantState.ps1`](scripts/common/Compare-TenantState.ps1) joins resolved baseline against a scan bundle and produces a sorted findings array; rule set in [`diff-rules.yaml`](scripts/common/diff-rules.yaml) (~30 rules across all workloads, framework-tagged).
- **Auth abstraction** — [`Connect-Tenant.ps1`](scripts/common/Connect-Tenant.ps1) handles GDAP, direct app-registration, and operator-interactive auth under one interface; secrets resolved via Azure Key Vault URIs.
- **Smoke-test runbook** — [`docs/smoke-test.md`](docs/smoke-test.md) — end-to-end checklist for first-run validation against a dev tenant.
- **CI** — GitHub Actions workflow validating baseline YAML against the schema, sanity-checking the control-map CSV, linting skill/agent frontmatter, running PSScriptAnalyzer, and running markdownlint.

## Portal separation

The **Multi-Tenant Compliance Portal** is a separate project (see `AGENTS.md` / portal repo) that consumes this workspace as a git submodule. This repo is the **knowledge and content layer**; the portal is the **application layer**. See the architecture discussion in the commit history for the full rationale.

## Contributing new frameworks

Copy `skills/frameworks/cis-m365/` as a template. Each framework skill must include:

1. **SKILL.md** with YAML frontmatter (name, description).
2. **controls.md** — the control catalogue, organised by the framework's native structure (sections, articles, subparts).
3. **m365-translation.md** — control → M365 setting(s) mapping.
4. **evidence.md** — what auditors want to see, where it lives in M365.
5. **applicability.md** — which entities/tenants the framework binds, jurisdictional scope, effective dates.
