# Gap Analysis — Procedure and Report

Gap analysis reads the baseline deployed to a tenant against the target framework set, using [map.csv](map.csv) as the join table.

## Inputs

1. **Target framework set** — e.g. `{cis-m365, dora, nis2}` for an EU financial-services tenant.
2. **Deployed baseline** — tenant-level YAML from `baselines/examples/` or as customised. Lists the control IDs actually enabled.
3. **Live tenant state (optional but preferred)** — evidence export from the tenant, so the gap report reflects real state not intent.

## Procedure

1. Load `map.csv` filtered to `framework ∈ target_set`.
2. Build the set of framework requirement refs referenced in the filtered map (the "universe").
3. Subtract — for each framework requirement ref:
   - If at least one row has `coverage_type = primary` **and** its control is in the deployed baseline → **covered**.
   - Else if one or more rows have `coverage_type = partial` and all are in the deployed baseline → **covered-by-partials** (flag for review).
   - Else → **gap**.
4. Enumerate requirement refs not in the map's universe at all — these are framework requirements M365 configuration cannot address (governance, TPP contracts, training workflow) → **out-of-scope-for-tenant**.
5. Optionally, verify each "covered" row against live tenant state — if the actual control is misconfigured or missing, reclassify as **drift**.

## Output report shape

```markdown
# Gap Report — <tenant> — <date>

## Target frameworks
- cis-m365 (v<benchmark version>)
- dora
- nis2

## Summary
- Covered:                   <n>
- Covered-by-partials:       <n>
- Drift:                     <n>
- Gap (tenant-addressable):  <n>
- Out of tenant scope:       <n>

## Gaps (tenant-addressable)

### framework: dora — Art 12 — Backup, restoration, recovery
- No matching primary control in deployed baseline.
- Proposed remediation: procure third-party M365 backup solution; record in baseline; schedule restore test.
- Owner: <>
- Target date: <>

### framework: nis2 — Art 21(2)(d) — Supply chain security
- Partial coverage only (app consent policy) — missing cross-tenant access restrictions.
- Proposed remediation: enable `m365.entra.cross-tenant-access.strict`.

## Covered-by-partials (review)
<rows>

## Out of tenant scope (process/governance)
- dora.Art.5 governance
- nis2.Art.20 governance
- hipaa.§164.316 policies & docs
- ...
```

## Operational cadence

| Frequency | Gap analysis type |
|---|---|
| On baseline change | Full re-run against all tagged tenants |
| Weekly | Drift-focused run against live tenant state (not intent) |
| On framework revision | Re-walk the map to identify newly ingested requirements without coverage |
| Per audit / supervisor inspection | Framework-scoped report, with evidence packaged per row |

## Evidence packaging when responding to a gap

Each gap closure produces:

1. Baseline change (git commit to `baselines/`).
2. Deployment run via the relevant workload agent, with before/after evidence artefact.
3. Map update if the closure introduces a new control ID.
4. Gap report re-generated to confirm closure.

## Limitations — worth stating to the user

- The map is only as accurate as the most recent review. Frameworks revise; Microsoft renames/moves settings; map rows rot.
- `primary` is a judgment call, not a regulator's verdict. A sufficiently hostile auditor can dispute any `primary` rating — record justification in notes.
- Gap analysis does not cover governance/process. A tenant scoring 100% covered still needs the policy documents, training records, incident drills, and contracts behind them.
