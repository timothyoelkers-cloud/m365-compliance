# scripts/ — PowerShell scan primitives

Runnable PowerShell 7 scripts that read tenant state across M365 workloads and emit structured JSON for the portal's diff engine. These are the deployable implementation of the `m365-*` agent designs — the portal's scan runner containers entry-point these; practitioners also invoke them directly from Claude Code or a shell.

## Layout

```
scripts/
├── common/
│   ├── Connect-Tenant.ps1          Auth abstraction (GDAP / app-reg / interactive)
│   ├── Resolve-Baseline.ps1        Layered merger (global → profile chain → overrides)
│   ├── Compare-TenantState.ps1     Rule-driven diff engine
│   └── diff-rules.yaml             Starter rule set (~30 controls)
├── scan/                           Read-only — captures current tenant state
│   ├── Invoke-TenantScan.ps1
│   ├── Invoke-EntraScan.ps1
│   ├── Invoke-ConditionalAccessScan.ps1
│   ├── Invoke-ExchangeScan.ps1
│   ├── Invoke-SharePointScan.ps1
│   ├── Invoke-TeamsScan.ps1
│   ├── Invoke-PurviewScan.ps1
│   ├── Invoke-DefenderScan.ps1
│   ├── Invoke-IntuneScan.ps1
│   └── Invoke-PowerBIScan.ps1
├── apply/                          Write — reconciles tenant to baseline (gated)
│   ├── Set-ConditionalAccess.ps1   Conditional Access — full per-policy plan/apply/rollback
│   └── Set-PurviewBaseline.ps1     Purview tenant-wide settings (UAL, retention, label/DLP gap detection)
├── orchestrate/                    End-to-end tenant pipeline
│   └── Invoke-TenantApply.ps1      Resolve baseline + scan diff + per-workload plan/apply + reports
└── report/                         Customer / auditor-facing markdown reports
    ├── New-FrameworkReport.ps1     Framework-scoped audit-prep report (cis-m365, dora, nis2, hipaa)
    └── New-ExecutiveSummary.ps1    Multi-framework cover doc (status snapshot + top findings + drift register)
```

## Design principles

- **Read-only.** These scripts never write to a tenant. Apply is a separate module built after scan matures.
- **Idempotent.** Safe to re-run. Safe to schedule.
- **Fail-loud per-workload, not per-script.** A single workload failing is captured as a warning in the bundle; the orchestrator still emits a bundle for the workloads that succeeded.
- **Evidence conforms to schema.** Output matches [baselines/schema/evidence-bundle.schema.json](../baselines/schema/evidence-bundle.schema.json).
- **No plaintext secrets.** `Connect-Tenant.ps1` resolves secrets via Key Vault by URI; never accepts them as parameters.

## Dependencies

```powershell
# Core
Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module ExchangeOnlineManagement -Scope CurrentUser
Install-Module Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser
Install-Module MicrosoftTeams -Scope CurrentUser
Install-Module Az.KeyVault -Scope CurrentUser   # for Connect-Tenant secret resolution
```

Containerised runs: base image should be `mcr.microsoft.com/powershell:7.4-ubuntu-22.04` with the above modules pre-installed. Pin module versions in the Dockerfile.

## Auth modes

`Connect-Tenant.ps1 -AuthMode` accepts:

| Mode | When to use | Prereqs |
|---|---|---|
| `app` | Direct app-registration in customer tenant | Client ID + cert thumbprint (preferred) or Key Vault-stored secret ref |
| `gdap` | MSP with Partner Center delegated admin | GDAP relationship established; service principal in partner tenant with cert |
| `interactive` | Operator ad-hoc runs | `M365C_INTERACTIVE_ALLOWED=1` env var; Global Reader or scoped reader role |

The auth mode is an attribute of the tenant in the portal's tenant registry. Runners don't choose — they receive the mode.

## Running a full scan (manual)

```powershell
# 1. Connect
pwsh scripts/common/Connect-Tenant.ps1 `
    -TenantId      '00000000-0000-0000-0000-000000000000' `
    -AuthMode      'app' `
    -ClientId      'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' `
    -CertificateThumbprint 'ABC123...' `
    -Workloads     @('entra','exchange','sharepoint','teams','purview')

# 2. Orchestrate scan
pwsh scripts/scan/Invoke-TenantScan.ps1 `
    -TenantId       '00000000-0000-0000-0000-000000000000' `
    -OutputRoot     './evidence' `
    -BaselineGitSha 'abc123def' `
    -BaselineProfiles @('cis-l1-l2@1.0.0','dora-overlay@1.0.0') `
    -Operator       'ops@corp.example' `
    -SigningCertThumbprint 'DEF456...'
```

Output: `./evidence/<tenant-id>/<timestamp>/{manifest.json, bundle.sha256, <workload>.json, …}`

## Apply primitives — current state

[Set-ConditionalAccess.ps1](apply/Set-ConditionalAccess.ps1) ships as the **template** for write-path work. It establishes the pattern that the other workloads will follow:

| Mode | Effect |
|---|---|
| `plan` (default) | Read scan + baseline → compute plan.json with create/patch/unchanged/untracked actions. **No writes.** |
| `apply` | Walk the plan and call `New-/Update-MgIdentityConditionalAccessPolicy`. Refuses without `-ApprovalRef` and refuses if any safety invariant is blocked. |
| `rollback` | Same engine pointed at a previous resolved baseline — diff produces the reverse direction naturally. |

Safety invariants (apply refuses if any are violated):

- Break-glass exclusion present on every user-blocking policy in the plan.
- No state transition skipping `enabledForReportingButNotEnforced`.
- Non-block policies must declare grant controls or an authentication strength.
- `authenticationStrength` references resolve to a known strength id (declared in the baseline or built-in).
- No empty `users` / `applications` blocks.

Plan output is **fully testable against the synthetic fixture** (no tenant required) — see [tests/end-to-end.Tests.ps1](../tests/end-to-end.Tests.ps1) and [tests/verify_fixture.py](../tests/verify_fixture.py).

### Purview apply

[Set-PurviewBaseline.ps1](apply/Set-PurviewBaseline.ps1) covers the same plan/apply/rollback shape against tenant-wide Purview settings. Distinct from CA in that there's no per-policy GUID mapping — most settings are tenant singletons.

Action vocabulary:

| Action | When |
|---|---|
| `enable` | Tenant flag is off, baseline asks for on (e.g. UAL toggle). |
| `extend-retention` | Baseline retention > current. Always allowed. |
| `shorten-retention` | Baseline retention < current. **Refused without `-ApprovalRef containing 'retention-reduce'`** (effectively destructive). |
| `create` | Baseline declares a label / DLP policy not present in tenant. v1 emits a deferred change record — full label/DLP creation belongs to dedicated apply primitives (`Set-PurviewLabels.ps1` / `Set-PurviewDlp.ps1`, planned). |
| `unchanged` | Tenant matches baseline. |

Safety invariants enforced before apply:

- **UAL is never silently disabled.** A baseline asking for `unified_audit_log_enabled: false` against a tenant that has it on is treated as a destructive control change and refused at plan time.
- **Audit retention reductions require explicit approval** (`-ApprovalRef` containing `retention-reduce`).

### Tenant policy mapping

CA policies are matched to baseline ids via `baselines/tenants/<tenant>/ca.tenant-map.yaml` (template at [baselines/tenants/_template/ca.tenant-map.yaml](../baselines/tenants/_template/ca.tenant-map.yaml)). When the map is absent, the script falls back to displayName matching — brittle, but workable on first sync. After the first apply, the orchestrator should write the map back.

## Reporting

[New-FrameworkReport.ps1](report/New-FrameworkReport.ps1) generates an audit-prep markdown document scoped to a single framework. Inputs: a `findings.json` (output of `Compare-TenantState.ps1`) plus the `control-map.csv`. Optional: the resolved baseline (sharpens the "deployed" check).

```powershell
pwsh scripts/report/New-FrameworkReport.ps1 `
    -Framework    dora `
    -FindingsPath ./evidence/<tenant>/<ts>/findings.json `
    -ResolvedBaselinePath ./resolved-baselines/<tenant>.json `
    -OutputPath   ./reports/<tenant>-dora-<ts>.md `
    -TenantDisplayName "Acme Bank Ltd"
```

Output sections:

- **Headline** — covered / drift / partial-only / uncovered framework references.
- **Coverage matrix** — one row per framework reference with primary + partial controls and any failing.
- **Findings** — scoped to the framework, grouped by severity, with current/desired/evidence.
- **Evidence index** — which scan artefacts back which framework references (auditor handoff).
- **Gaps** — references with no primary deployed, drift, or no coverage at all, with proposed action.

The mapped scope is limited to controls in `skills/mapping/control-map/map.csv`. Requirements outside the map need manual review against the framework skill.

Sample reports against the synthetic fixture: [tests/expected-cis-m365-report.md](../tests/expected-cis-m365-report.md), [tests/expected-dora-report.md](../tests/expected-dora-report.md), [tests/expected-nis2-report.md](../tests/expected-nis2-report.md), [tests/expected-hipaa-report.md](../tests/expected-hipaa-report.md).

## Orchestration

[Invoke-TenantApply.ps1](orchestrate/Invoke-TenantApply.ps1) ties the whole pipeline together for a single tenant — one entry point that resolves the baseline, runs the diff engine, dispatches each workload's apply primitive, generates the framework reports, and aggregates everything into a consolidated tenant plan.

```powershell
pwsh scripts/orchestrate/Invoke-TenantApply.ps1 `
    -TenantConfigPath baselines/tenants/<id>/tenant.yaml `
    -ScanBundlePath   evidence/<tenant>/<ts>/ `
    -OutputDir        out/<tenant>/<ts>/ `
    -Mode             plan
```

Modes:

| Mode | Effect |
|---|---|
| `audit` | Resolve baseline + run diff + produce findings + reports. **Read-only.** No per-workload plans. |
| `plan` (default) | Audit, plus runs every workload apply primitive in plan mode. Produces `tenant-plan.json` (consolidated). **Read-only.** |
| `apply-pilot` | Plan, then apply each workload's plan to its pilot ring. Requires `-ApprovalRef`. Refuses if any workload's plan has `blockedBy`. |
| `apply-broad` | Same as apply-pilot but broad scope. |
| `rollback` | Apply against an alternate (prior) baseline. |

Pre-flight gates (audit performs read-only ones; apply modes add destructive-change ones):

1. **Tenant identity consistency** — scan `tenantId`, baseline `tenant.id`, and `-TenantId` all match.
2. **Break-glass posture** — baseline declares a non-empty `entra.break_glass.group_id`.
3. **Licence sufficiency** (best-effort warning) — baseline references P2 features but `tenant.licensing.tier` doesn't include P2/E5.
4. **Workload plan blocked-by=0** (apply only) — every per-workload plan must show no safety blockers.

The orchestrator is **forward-compatible**: when a new `Set-<Workload>.ps1` is added to `apply/`, register it in `$script:WorkloadApplyScripts` at the top of the orchestrator and it'll be planned and applied alongside the rest.

Sample output structure:

```text
out/<tenant>/<ts>/
├── tenant-plan.json              ← consolidated cross-workload plan
├── resolved-baseline.json
├── findings.json
├── conditional-access/
│   └── plan.json
├── purview/
│   └── plan.json
└── reports/
    ├── cis-m365.md
    ├── dora.md
    ├── nis2.md
    ├── hipaa.md
    └── executive-summary.md
```

### Multi-framework executive summary

[New-ExecutiveSummary.ps1](report/New-ExecutiveSummary.ps1) produces a single board-room ready document covering all configured frameworks. Sections:

- **Status snapshot** — one row per framework with covered / drift / partial-only / uncovered / total / score, plus a combined row. Score = `(covered + 0.5 × partial-only) / total`.
- **Top N findings** — sorted by severity, then by how many frameworks each finding affects (multi-framework findings rank higher).
- **Drift register** — every (framework, ref) pair with at least one failing control.
- **Uncovered register** — every reference with no deployed control.
- **Recommended next actions** — prioritised by drift > uncovered > partial.

Sample: [tests/expected-executive-summary.md](../tests/expected-executive-summary.md).

## What's not here yet

- **Other apply primitives** — Set-Entra, Set-Exchange, Set-SharePoint, Set-Teams, Set-Purview, Set-Defender, Set-Intune. Each clones the Set-ConditionalAccess pattern; each will need its own baseline-to-API normaliser similar to `ConvertTo-GraphCaPolicy`.
- **Power BI async workspace scan** — the `/admin/workspaces/getInfo` two-step dance. Placeholder in [Invoke-PowerBIScan.ps1](scan/Invoke-PowerBIScan.ps1) — build out when the portal runner infra exists to track async jobs.
- **Defender for Cloud Apps deep read** — requires a dedicated MDA API token; needs a second connect primitive. Note in [Invoke-DefenderScan.ps1](scan/Invoke-DefenderScan.ps1).
- **Graph throttling backoff** — the per-script reads are modest today. When running across hundreds of tenants concurrently, add a per-tenant-id token bucket and exponential backoff in a shared helper.
