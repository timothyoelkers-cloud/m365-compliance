# Baselines — Config-as-Data for Multi-Tenant M365 Deployment

Baselines describe **what a tenant should look like**. Deployment agents read baselines and reconcile tenant state against them. Framework skills describe **why** — baselines turn that into settings.

## Principles

1. **One source of truth per baseline, versioned in git.** Every deployment traces back to a specific commit SHA.
2. **Composable, not monolithic.** A tenant baseline is layered: global defaults → framework overlays → tenant overrides. The final applied config is the merged result.
3. **Declarative only.** Baselines declare desired state; they contain no imperative steps. Agents own the reconciliation.
4. **Target-state complete, origin-state agnostic.** A baseline says "this is how the tenant must look", not "change X to Y". Reconciliation derives the delta from live state.
5. **No secrets.** Baselines reference secret material by identifier (Key Vault URI, managed identity); actual values never land in the baseline file.

## Directory layout

```
baselines/
├── README.md                      (this file)
├── schema/
│   └── baseline.schema.json       JSON schema — validated in CI
├── global/
│   ├── defaults.yaml              Organisation-wide defaults (break-glass policy, region preferences, logging targets)
│   └── break-glass.yaml           Break-glass account definitions (group names, not credentials)
├── profiles/
│   ├── cis-l1.yaml                CIS M365 Level 1 — minimum viable hardening
│   ├── cis-l1-l2.yaml             CIS M365 L1 + selected L2
│   ├── dora-financial.yaml        DORA-bound entity overlay
│   ├── nis2-essential.yaml        NIS 2 Essential entity overlay
│   ├── nis2-important.yaml        NIS 2 Important entity overlay
│   └── hipaa-covered-entity.yaml  HIPAA Covered Entity overlay
├── tenants/
│   └── <tenant-id>/
│       ├── tenant.yaml            Tenant metadata: name, region, licence mix, applicable frameworks
│       ├── overrides.yaml         Tenant-specific exceptions, documented
│       └── ca.tenant-map.yaml     baseline-id ↔ CA policy GUID map (agent-managed)
└── examples/
    └── acme-health-ltd/           Worked example of a layered tenant config
```

## Layering and merge

Merge order (lowest precedence first):

1. `global/defaults.yaml`
2. Each profile referenced by the tenant, in the order listed in `tenant.yaml`.
3. `tenants/<tenant-id>/overrides.yaml`.

Merge semantics:

- Scalars and objects: later wins.
- Lists where order is significant (e.g. CA policies, named locations): **named merge** by `id` field — later value replaces earlier value with the same `id`; items not in later are preserved.
- Lists where order is a set (e.g. `exclude_groups`): **union**.
- Explicit `null` from a higher layer removes an item from the merged result (for rare cases where a tenant genuinely must not deploy something).

## Versioning

- Baselines use semantic versioning: `1.4.2` (major.minor.patch).
- Major = breaking change (setting removed, renamed, or shifting semantic).
- Minor = new setting added that tenants may be required to adopt.
- Patch = cosmetic / documentation-only.
- Profile files carry a `version:` stanza. Tenant files pin a profile version range (e.g. `~1.4`).
- CI validates that no tenant pins a non-existent version.

## Tenant metadata (required in `tenant.yaml`)

```yaml
tenant:
  id: 00000000-0000-0000-0000-000000000000
  name: Example Co
  display_name: Example Co (UK HQ)
  region: EU-North               # aligns with M365 datacentre geo
  jurisdictions: [GB, IE]        # applicable legal jurisdictions
  licensing:
    tier: E5                     # E3 | E5 | Business Premium | mixed
    addons:
      - Microsoft 365 E5 Compliance
      - Entra ID Governance
  frameworks:
    - cis-m365            # use profile cis-l1-l2
    - nis2-important      # entity is an Annex II important entity in Germany
  profiles:
    - cis-l1-l2@~1.4
    - nis2-important@~1.2
  break_glass:
    group_id: grp-ca-break-glass
    member_count_expected: 2
    monitoring_alerts: [alert-bg-signin-any, alert-bg-mfa-exclusion-change]
  tags:
    owner: alice@example.com
    environment: production
    tier: tier-1
```

## Tenant-class rollout rings

For dozens-to-thousands tenants, rollout is banded:

| Ring | Tenant class | Example | Rollout cadence |
|---|---|---|---|
| 0 — canary | internal / own tenant | MSP's own | Immediate on merge |
| 1 — pilot | 2–5 friendly customer tenants | design-partner tenants | Within 24h of canary green |
| 2 — broad | remainder of a region | e.g. all UK tenants | 5–10 business days after pilot |
| 3 — special | regulated / bespoke | named financial customer | Last, only after written approval |

Profiles carry a `rollout:` block describing which rings a new version is valid for. Agents reject applying a v1.5.0 to ring 3 tenants until it has reached `rollout.rings: [0,1,2,3]`.

## CI validation (required before merge)

1. `baselines/**/*.yaml` validates against `schema/baseline.schema.json`.
2. Every `id` within a list is unique.
3. Every `exclude_groups` references a group declared in `break-glass.yaml` or in profiles.
4. No duplicate CA policy definitions (by `id`) across a tenant's merged profiles without an explicit override.
5. Profile version pins exist.
6. No secret-looking values (regex for common patterns — a belt-and-braces check, not a replacement for secrets management).

## Evidence and reversibility

- Every apply produces an evidence bundle stored under `evidence/<tenant-id>/<timestamp>/` (outside this repo, in the evidence store).
- Apply bundles include before + after snapshots so a point-in-time rollback is possible.
- Rollback is: check out previous baseline version + re-run apply. Because reconciliation is declarative, this converges the tenant to the older state.

## Anti-patterns (don't)

- Don't encode imperative "change X to Y" steps. If you find yourself writing that, the baseline is wrong.
- Don't reference tenant-specific GUIDs in shared profiles. Those belong in `tenants/<tenant-id>/`.
- Don't embed live framework citations that change with regulator edits. Reference the framework skill by name; let the skill hold the citation.
- Don't let a tenant override introduce a new control. If it's needed, it belongs in a profile (so it's reusable) or the global default (if universal).
