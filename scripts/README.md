# scripts/ — PowerShell scan primitives

Runnable PowerShell 7 scripts that read tenant state across M365 workloads and emit structured JSON for the portal's diff engine. These are the deployable implementation of the `m365-*` agent designs — the portal's scan runner containers entry-point these; practitioners also invoke them directly from Claude Code or a shell.

## Layout

```
scripts/
├── common/
│   └── Connect-Tenant.ps1          Auth abstraction (GDAP / app-reg / interactive)
└── scan/
    ├── Invoke-TenantScan.ps1       Orchestrator — signed evidence bundle output
    ├── Invoke-EntraScan.ps1
    ├── Invoke-ConditionalAccessScan.ps1
    ├── Invoke-ExchangeScan.ps1
    ├── Invoke-SharePointScan.ps1
    ├── Invoke-TeamsScan.ps1
    ├── Invoke-PurviewScan.ps1
    ├── Invoke-DefenderScan.ps1
    ├── Invoke-IntuneScan.ps1
    └── Invoke-PowerBIScan.ps1
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

## What's not here yet

- **Apply primitives** — the write-path counterparts. Intentionally deferred until scan is proven at scale.
- **Power BI async workspace scan** — the `/admin/workspaces/getInfo` two-step dance. Placeholder in [Invoke-PowerBIScan.ps1](scan/Invoke-PowerBIScan.ps1) — build out when the portal runner infra exists to track async jobs.
- **Defender for Cloud Apps deep read** — requires a dedicated MDA API token; needs a second connect primitive. Note in [Invoke-DefenderScan.ps1](scan/Invoke-DefenderScan.ps1).
- **Graph throttling backoff** — the per-script reads are modest today. When running across hundreds of tenants concurrently, add a per-tenant-id token bucket and exponential backoff in a shared helper.
