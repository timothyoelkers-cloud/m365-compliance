# Claude Code context for this repository

## What this repo is

Three-layer M365 compliance corpus:

1. **skills/** — framework knowledge (CIS M365 v6.0.1, DORA, NIS 2, HIPAA) and cross-framework control mapping. Authoritative narrative content.
2. **agents/** — subagent definitions for workload-scoped operations (Entra, CA, Intune, Purview, Defender, Exchange/SPO/Teams, orchestrator).
3. **baselines/** — config-as-data — schemas, global defaults, populated profiles, tenant templates. This is the source of truth the portal and agents consume.
4. **scripts/** — PowerShell 7 scan primitives + merger + diff engine. Runnable today; the portal's scan engine inherits from these.

See [README.md](README.md) for the full tree and the [baselines/README.md](baselines/README.md) for the layering/merge model.

## Environmental context

- User is a Microsoft 365 compliance practitioner supporting MSP-scale tenant fleets (dozens → thousands).
- Jurisdictions: UK, US, EMEA. Expect UK GDPR + NIS 2 in EU MS + DORA for financial tenants + HIPAA for US health tenants.
- Companion portal project lives in a separate repo (`m365-compliance-portal/`) and consumes this one as a submodule.

## Key conventions

### Frameworks and their detail

- Each framework skill under `skills/frameworks/<name>/` has a consistent shape: `SKILL.md` + framework-specific files (articles.md / controls.md / m365-translation.md / reporting.md / etc.).
- Never invent control IDs or regulation numbers. If you don't have a verified citation, flag it. The CIS v6 catalogue and the DORA RTS/ITS numbers have been research-verified; other content is clearly marked.

### Baselines

- Populated profiles in `baselines/profiles/*.yaml` reference CIS v6 IDs in trailing comments (e.g. `# 5.2.2.3 — block legacy auth`).
- Layered merge: `global/defaults.yaml` → `global/break-glass.yaml` → `profiles/<each>` in declared order → `tenants/<id>/overrides.yaml`. Named-merge on `id` field for list items; later wins on scalars.
- A profile layering a framework *overlay* (DORA / NIS 2 / HIPAA) sits on top of `cis-l1-l2` — never on its own.
- Use `replaces: [baseline-id-1, baseline-id-2]` on a CA/compliance/retention item to explicitly supersede an upstream-layer entry.

### Scripts

- PowerShell 7 target. `$ErrorActionPreference = 'Stop'`, `Set-StrictMode -Version 3.0` mandatory.
- Scan scripts are **read-only** and idempotent. Apply counterparts do not exist yet.
- Never accept plaintext secrets as parameters. Reference via Key Vault URI through `Connect-Tenant.ps1`.
- Failures in one workload warn but don't abort the orchestrator — the bundle manifest captures `warnings`.

### Control mapping

- [skills/mapping/control-map/map.csv](skills/mapping/control-map/map.csv) is the machine-readable source of truth for cross-framework mapping.
- `map.md` is a human-readable subset — regenerate by hand when the CSV changes substantially.
- `coverage_type` enum: `primary` / `partial` / `contributes-to`.

## Regulatory watchpoints (memory)

- **HIPAA** — final rule expected May 2026 per HHS OCR regulatory agenda. On publication, update `skills/frameworks/hipaa/` and remove the watch item from `project_hipaa_final_rule_watch.md` in memory.
- **NIS 2** — several EU Member States still not transposed as of April 2026 (see [national-transpositions.md](skills/frameworks/nis2/national-transpositions.md)). Re-check quarterly or on new customer engagement.
- **DORA** — Level 2 (RTS/ITS) is finalised in the OJEU; verify TLPT and subcontracting RTS numbers at customer engagement time.
- **CIS M365 Benchmark** — currently v6.0.1 (Oct 2025). CIS releases annually; expect v7 late 2026.

## Common tasks

**Add a framework skill**: copy `skills/frameworks/cis-m365/` as a template — SKILL.md, controls.md (or articles.md), m365-translation.md, evidence.md (if relevant). Update [MEMORY.md](../../.claude/projects/-Users-timothy-oelkers-VS-Code-Agent---Skills/memory/MEMORY.md) if the framework has a regulatory watchpoint.

**Add a control mapping**: append rows to `skills/mapping/control-map/map.csv` (one row per framework × control combination). Keep `map.md` in rough sync for the most interesting controls.

**Update a baseline**: edit `baselines/profiles/<name>.yaml`. Bump the profile's `version:` per semver (major if removing a setting, minor if adding, patch if cosmetic). CI validates against the schema.

**Run a scan**: see [docs/smoke-test.md](docs/smoke-test.md) or [scripts/README.md](scripts/README.md).

## What NOT to do

- Don't create files in `evidence/` or commit scan output — it may contain sensitive tenant data (gitignored).
- Don't reference tenant-specific GUIDs inside shared profiles. Those belong in `baselines/tenants/<id>/`.
- Don't write new scan logic in the framework skill files. Skills are knowledge; scripts are action.
- Don't encode imperative "change X to Y" steps in baselines — they declare desired state, reconciliation derives the delta.
- Don't commit unless the user explicitly asks.
