---
name: control-map
description: Cross-framework control mapping between CIS M365, DORA, NIS 2, HIPAA (extensible). Use when the user asks how a single M365 control satisfies multiple frameworks, wants a gap analysis against a target framework set, or needs consolidated audit evidence packaged per framework. Keeps framework skills framework-local; this skill owns the connections.
---

# Control Map — Cross-Framework Mapping for M365

Purpose: map a single concrete M365 control (a setting, policy, or capability) to every framework requirement it satisfies, in both directions.

Why separate from the framework skills: mappings are M×N (framework × control) and change under two different forces (framework changes on regulator time; M365 controls change on Microsoft's release cadence). Keeping them here stops each framework skill from duplicating mapping rows and drifting out of sync.

## When this skill applies

- User asks "what does [M365 control] satisfy across our frameworks?"
- User wants a gap analysis: "we deploy baseline X — which framework rows does that leave exposed?"
- User needs to produce audit evidence in terms of a specific framework, drawing from M365 controls deployed for unrelated reasons.
- Cross-mapping a new framework as it's added.

## Structure

Core artefact: [map.csv](map.csv) (machine-readable) plus [map.md](map.md) (human-readable mirror).

Row granularity: **one row per M365 control surface + framework combination**. A single CA policy for phishing-resistant MFA produces one row against CIS, one against DORA Art 9(2)(d), one against NIS 2 Art 21(2)(j), one against HIPAA §164.312(d). Four rows — same control.

Columns:

| Column | Meaning |
|---|---|
| control_id | Internal ID for the M365 control surface (e.g. `m365.entra.ca.mfa-phishing-resistant`) |
| control_description | One-line description |
| m365_workload | entra / exchange / sharepoint / teams / defender / intune / purview |
| graph_or_ps_reference | Path to the setting (Graph URL, PS cmdlet, admin path) |
| framework | cis-m365 / dora / nis2 / hipaa |
| framework_ref | The framework-specific reference (e.g. DORA Art 9(2)(d); NIS 2 Art 21(2)(j); HIPAA §164.312(d); CIS 1.1.3) |
| coverage_type | primary / partial / contributes-to |
| evidence_artefact | What to capture as evidence (e.g. `conditionalAccess.policies.json` filtered to this policy) |
| notes | Caveats, dependencies, or prerequisite controls |

## Coverage types

- **primary** — this control is sufficient on its own to satisfy the framework requirement for technical implementation (assuming it is actually deployed and proven).
- **partial** — the control covers a material part of the requirement but at least one other control is needed for full coverage.
- **contributes-to** — the control is relevant but only a minor piece of the overall requirement (common for process-heavy obligations like DORA governance or NIS 2 Art 20).

The coverage type guides gap analysis: a requirement with only **contributes-to** rows is effectively uncovered by M365 — it needs process controls outside the tenant.

## Reference row — one worked example

| control_id | control_description | m365_workload | graph_or_ps_reference | framework | framework_ref | coverage_type | evidence_artefact | notes |
|---|---|---|---|---|---|---|---|---|
| m365.entra.ca.mfa-phishing-resistant | Conditional Access policy requiring phishing-resistant MFA (FIDO2 / WHfB / cert-based) for all users | entra | `GET /identity/conditionalAccess/policies` + `authenticationStrength` | cis-m365 | <Rec ID once ingested> | primary | CA policy JSON snapshot | Requires authentication methods policy registrations; pilot ring first to avoid lockout |
| m365.entra.ca.mfa-phishing-resistant | (same) | entra | (same) | dora | Art 9(2)(d) Protection — logical access control | primary | (same) | Pair with PIM (m365.entra.pim.*) for full Art 9(2)(d) coverage |
| m365.entra.ca.mfa-phishing-resistant | (same) | entra | (same) | nis2 | Art 21(2)(j) MFA / secure authentication | primary | (same) | NIS 2 allows MFA generically; this gives you the defensible answer |
| m365.entra.ca.mfa-phishing-resistant | (same) | entra | (same) | hipaa | §164.312(d) Person/entity authentication | primary | (same) | NPRM will likely elevate MFA from implicit to mandatory; posture is already correct |

The 4 rows above are one control's mapping signature. Multiply this shape for every control in the baseline.

## Operations

### Add a new control
1. Append a row per framework to [map.csv](map.csv) and [map.md](map.md).
2. If the control is baseline, add it to the relevant `baselines/examples/*.yaml` profile.

### Add a new framework
1. Create the framework skill under `skills/frameworks/<name>/`.
2. Walk the existing control catalogue and add one row per applicable control to the map.
3. Identify framework requirements with no covering control — these are gaps; open tickets.

### Gap analysis against a target framework set
1. Filter map to the union of `framework` values in scope.
2. For each requirement reference, check at least one `primary` or the sum of `partial` rows would cover it.
3. Produce a gap report: framework references with **no coverage** or only **contributes-to** rows.
4. Hand to the relevant framework skill for process/organisational remediation.

### Evidence packaging for audit
1. Auditor names the framework (e.g. NIS 2 Art 21(2)(j)).
2. Filter map to that `framework_ref`.
3. For each row, pull the current `evidence_artefact` from the tenant.
4. Package: one framework ref → N evidence files → one ZIP with a manifest mapping back to the map.
5. Retain the evidence package with timestamp + SHA of the bundle.

## Related files

- [map.csv](map.csv) — machine-readable mapping (source of truth for tooling).
- [map.md](map.md) — human-readable mirror, grouped by control.
- [gap-analysis.md](gap-analysis.md) — gap analysis procedure and report template.
