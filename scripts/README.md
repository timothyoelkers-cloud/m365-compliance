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
└── apply/                          Write — reconciles tenant to baseline (gated)
    └── Set-ConditionalAccess.ps1   Conditional Access (template; other workloads tbd)
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

### Tenant policy mapping

CA policies are matched to baseline ids via `baselines/tenants/<tenant>/ca.tenant-map.yaml` (template at [baselines/tenants/_template/ca.tenant-map.yaml](../baselines/tenants/_template/ca.tenant-map.yaml)). When the map is absent, the script falls back to displayName matching — brittle, but workable on first sync. After the first apply, the orchestrator should write the map back.

## What's not here yet

- **Other apply primitives** — Set-Entra, Set-Exchange, Set-SharePoint, Set-Teams, Set-Purview, Set-Defender, Set-Intune. Each clones the Set-ConditionalAccess pattern.
- **Baseline → Graph translator** — populated baselines use our YAML names (e.g. `include`, `exclude_groups`); Graph wants Microsoft's names (`includeUsers`, `excludeGroups`). Currently the planner reports the encoding difference as drift in the conditions field. The fix is a per-workload normalisation function applied before diff.
- **Power BI async workspace scan** — the `/admin/workspaces/getInfo` two-step dance. Placeholder in [Invoke-PowerBIScan.ps1](scan/Invoke-PowerBIScan.ps1) — build out when the portal runner infra exists to track async jobs.
- **Defender for Cloud Apps deep read** — requires a dedicated MDA API token; needs a second connect primitive. Note in [Invoke-DefenderScan.ps1](scan/Invoke-DefenderScan.ps1).
- **Graph throttling backoff** — the per-script reads are modest today. When running across hundreds of tenants concurrently, add a per-tenant-id token bucket and exponential backoff in a shared helper.
