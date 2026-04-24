# Contributing

## Repo purpose

Knowledge and content layer for M365 compliance — framework skills, deployment-agent designs, populated baselines, scan primitives. Consumed by the Multi-Tenant Compliance Portal (separate repo) as a git submodule.

## Branching

- `main` — production-ready. CI must be green to merge.
- `feat/<framework-or-area>` — feature branches.
- `fix/<summary>` — bug fixes.
- `rel/v<N.N.N>` — release branches when cutting tagged versions.

All changes land via PR. Direct pushes to `main` discouraged.

## Versioning

Independent semver for each artefact class:

| Artefact | Semver bump rule |
|---|---|
| Framework skill | Major: content reorg or citation restructure. Minor: new section, new RTS reference. Patch: typo/cosmetic. |
| Baseline profile | Major: removed setting or changed semantic. Minor: new setting added. Patch: cosmetic. |
| Scan script | Major: breaking output shape change. Minor: new captured field. Patch: fix. |
| Evidence bundle schema | Major only when breaking — downstream consumers (portal, auditors) depend on it. |

Top-level repo tag (`vX.Y.Z`) cuts a coordinated release across artefacts for portal submodule pinning.

## Before opening a PR

1. Run CI locally where practical:

   ```bash
   # baseline schema validation
   npx -y ajv-cli validate -s baselines/schema/baseline.schema.json -d <your baseline> --spec=draft2020 -c ajv-formats --strict=false
   # PS script analysis
   pwsh -c "Invoke-ScriptAnalyzer -Path scripts -Recurse -Severity @('Error','Warning')"
   ```

2. If adding a new framework skill, add at least one mapping row to `skills/mapping/control-map/map.csv`.
3. If changing a populated baseline, bump the `version:` field and note the change in the PR body.
4. If adding/changing a scan script, bump the `producedBy` version string in its JSON output (e.g. `Invoke-EntraScan.ps1@1.1.0`).

## PowerShell conventions

- **Strict.** `$ErrorActionPreference = 'Stop'` + `Set-StrictMode -Version 3.0` at top of every script.
- **Idempotent reads.** Scan scripts never mutate state, return immediately on re-run.
- **No plaintext secrets.** Only Key Vault URIs through `Connect-Tenant.ps1`.
- **Emit JSON, not objects.** Return value from a script is a path or a simple summary; data is written as JSON artefact files.
- **Fail loudly per script, softly per workload.** A script that can't read Purview should warn in the manifest and keep going — not crash the orchestrator.

## Schema/content rules

- Control IDs in populated baselines must trace back to [controls.md](skills/frameworks/cis-m365/controls.md). If you're adding a setting without a CIS v6 reference, tag it `# (non-CIS, internal)` with a reason.
- Every `replaces:` directive must reference a `baseline-id` that actually exists in a lower layer (CI cannot enforce this yet — reviewers catch it).
- Regulatory citations (DORA article numbers, NIS 2 article numbers, HIPAA §) must be literal — no paraphrasing of text. When uncertain, omit rather than invent.

## Reviewers

- Any framework content change: someone who can verify the regulatory citation. In practice, the repository owner for now.
- Any baseline change with rollout ring 2 or 3 implication: practitioner with operational context + security lead.
- Schema changes: require PR sign-off + a note in the PR body on downstream consumer impact.

## Secret hygiene

- `.gitignore` blocks the common patterns but is not sufficient. Before committing, `git diff --cached` and eyeball for anything resembling a GUID+secret pair, PEM block, or `AZ_`/`AAD_` env var value.
- If a secret slips in, rotate it immediately (don't rely on `git filter-repo` to hide it — assume it's exposed).

## How to add a new framework (quick reference)

1. `mkdir skills/frameworks/<name>/`
2. Copy `cis-m365/` layout (SKILL.md + articles.md/controls.md + m365-translation.md + evidence.md as applicable)
3. Frontmatter — name and description are required (CI enforces).
4. Add rows to `skills/mapping/control-map/map.csv` for applicable M365 controls.
5. (Optional) Create `baselines/profiles/<name>-overlay.yaml` layering on cis-l1-l2.
6. Update `README.md` status section + `MEMORY.md` index if the framework needs a regulatory watchpoint.

## How to add a new scan script

1. Copy the shape of `Invoke-EntraScan.ps1`.
2. Add the script name to `Invoke-TenantScan.ps1`'s dispatch map.
3. Add the workload name to the `artefacts[*].workload` enum in the evidence bundle schema.
4. Document under `scripts/README.md`.
