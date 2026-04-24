# Smoke-test plan

The first time you run this stack against a real tenant, expect cmdlet drift — a module name or parameter that has been renamed, a permission that needs to be consented, or a feature that requires a licence the tenant doesn't have. This checklist exists to catch those fast with a low-stakes dev/test tenant.

**Do this before running against any customer tenant.**

## Prerequisites

### Tenant

- A **dev/test tenant** you can safely run reads against (a Microsoft Developer Program tenant works).
- **Global Reader** role on that tenant for your operator account, *or* an app registration with the scopes listed under "App registration" below.
- **Entra ID P2** trial activated if you want PIM + Identity Protection reads to succeed (they're optional — the scan marks them as null otherwise).

### Local environment

- **PowerShell 7.4+** (`pwsh --version`).
- Modules:

  ```powershell
  Install-Module Microsoft.Graph                          -Scope CurrentUser -AcceptLicense -Force
  Install-Module ExchangeOnlineManagement                 -Scope CurrentUser -AcceptLicense -Force
  Install-Module Microsoft.Online.SharePoint.PowerShell   -Scope CurrentUser -AcceptLicense -Force
  Install-Module MicrosoftTeams                           -Scope CurrentUser -AcceptLicense -Force
  Install-Module Az.KeyVault                              -Scope CurrentUser -AcceptLicense -Force  # optional for smoke test
  Install-Module powershell-yaml                          -Scope CurrentUser -AcceptLicense -Force
  Install-Module PSScriptAnalyzer                         -Scope CurrentUser -AcceptLicense -Force  # CI parity
  ```

- `npx` on PATH (Node.js 20+) if you want `-Validate` schema checks.
- Approximate disk: 100–500 MB per scan bundle for large tenants; a few MB for a dev tenant.

### App registration (if not using interactive)

Create an app registration in the target tenant with **application permissions** (admin consent required):

| Permission | Needed by |
|---|---|
| `Policy.Read.All`                                        | Entra, CA |
| `Directory.Read.All`                                     | Entra |
| `User.Read.All`                                          | Entra (admin accounts) |
| `Group.Read.All`                                         | Entra (break-glass group) |
| `RoleManagement.Read.Directory`                          | Entra, PIM |
| `RoleManagementPolicy.Read.Directory`                    | PIM role settings |
| `IdentityRiskEvent.Read.All`, `IdentityRiskyUser.Read.All` | Defender (risky users) |
| `AuditLog.Read.All`                                      | CA (sign-in history) |
| `Reports.Read.All`                                       | Entra (auth methods registration stats) |
| `AccessReview.Read.All`                                  | Entra (access reviews) |
| `SecurityEvents.Read.All`                                | Defender (Secure Score) |
| `DeviceManagementManagedDevices.Read.All`                | Intune |
| `DeviceManagementConfiguration.Read.All`                 | Intune |
| `DeviceManagementServiceConfig.Read.All`                 | Intune |
| `DeviceManagementApps.Read.All`                          | Intune (app protection) |
| `DeviceManagementRBAC.Read.All`                          | Intune (scope tags) |
| `Exchange.ManageAsApp`                                   | Exchange module (plus the `Global Reader` or `Exchange Administrator` Entra role on the service principal) |
| `SharePoint: Sites.FullControl.All`                      | SharePoint module |
| `Teams: access_as_user` *(delegated)* or equivalent app permissions | Teams module |
| Power BI Service: `Tenant.Read.All`                      | Power BI admin reads |

Generate a self-signed certificate, install it locally, and upload the public key to the app registration. The scripts use certificate-based auth by preference.

## Stage 1 — connect

```powershell
cd "/path/to/Agent & Skills"

$tenantId = '<dev-tenant-guid>'
$clientId = '<app-registration-client-id>'
$thumb    = '<certificate-thumbprint>'

pwsh scripts/common/Connect-Tenant.ps1 `
    -TenantId $tenantId `
    -AuthMode 'app' `
    -ClientId $clientId `
    -CertificateThumbprint $thumb `
    -Workloads @('entra','exchange','sharepoint','teams','purview')
```

**Expected output:** a table with `Workload`, `Status=connected` (or `reused`) for each workload.

**Common failures:**

| Symptom | Usual cause |
|---|---|
| `AADSTS700027` or `AADSTS7000215` | Wrong cert thumbprint or cert not uploaded to app reg |
| `Insufficient privileges to complete the operation` | Admin consent not granted on one of the Graph permissions |
| `Connect-SPOService : The remote server returned an error: (403) Forbidden` | App reg missing `Sites.FullControl.All`, or certificate not associated with an SPO-enabled app |
| `Get-OrganizationConfig : Access is denied` | Exchange app role not assigned (need `Exchange.ManageAsApp` + Entra role) |

## Stage 2 — single-workload scan

Start narrow. Entra has the cleanest surface — try it first:

```powershell
pwsh scripts/scan/Invoke-EntraScan.ps1 `
    -TenantId $tenantId `
    -OutputPath ./evidence/smoke/entra.json
```

**Expected output:** path printed; JSON file exists at `evidence/smoke/entra.json`, ~50–500 KB on a small dev tenant.

**Inspect it:**

```powershell
# Quick structural sanity check
jq 'keys' evidence/smoke/entra.json
jq '.authMethodsPolicy | keys' evidence/smoke/entra.json
```

Look for:

- `authorizationPolicy` present and non-null
- `authMethodsPolicy` with each method present (state: enabled/disabled)
- `privilegedRoles` array non-empty (at least Global Administrator)

**Common failures:**

| Symptom | Fix |
|---|---|
| `Get-MgRoleManagementPolicyAssignment : The term ... is not recognized` | `Microsoft.Graph` module too old — `Update-Module Microsoft.Graph` |
| All PIM fields null | Tenant has no P2 licence — expected on most dev tenants; ignore for smoke |
| `NullReferenceException` inside `Get-MgPolicyRoleManagementPolicyAssignment` | Known Graph SDK regression on some versions — pin to Microsoft.Graph 2.15+ |

Repeat for each workload you can reach:

```powershell
pwsh scripts/scan/Invoke-ConditionalAccessScan.ps1 -TenantId $tenantId -OutputPath ./evidence/smoke/ca.json
pwsh scripts/scan/Invoke-ExchangeScan.ps1          -TenantId $tenantId -OutputPath ./evidence/smoke/exchange.json
pwsh scripts/scan/Invoke-SharePointScan.ps1        -TenantId $tenantId -OutputPath ./evidence/smoke/sharepoint.json
pwsh scripts/scan/Invoke-TeamsScan.ps1             -TenantId $tenantId -OutputPath ./evidence/smoke/teams.json
pwsh scripts/scan/Invoke-PurviewScan.ps1           -TenantId $tenantId -OutputPath ./evidence/smoke/purview.json
pwsh scripts/scan/Invoke-DefenderScan.ps1          -TenantId $tenantId -OutputPath ./evidence/smoke/defender.json
pwsh scripts/scan/Invoke-IntuneScan.ps1            -TenantId $tenantId -OutputPath ./evidence/smoke/intune.json
```

Track which scripts fail and capture the exception text. Most drift fixes are one-line param changes; log them in the commit message when you fix.

## Stage 3 — orchestrated scan + evidence bundle

```powershell
pwsh scripts/scan/Invoke-TenantScan.ps1 `
    -TenantId         $tenantId `
    -OutputRoot       ./evidence `
    -BaselineGitSha   (git rev-parse --short HEAD) `
    -BaselineProfiles @('cis-l1-l2@1.0.0') `
    -Operator         (whoami) `
    -Workloads        @('entra','conditional-access','exchange','sharepoint','teams','purview')
```

**Expected:** a bundle under `evidence/<tenant-id>/<timestamp>/` containing:

```
manifest.json          <-- matches baselines/schema/evidence-bundle.schema.json
bundle.sha256          <-- hash chain
entra.json
conditional-access.json
exchange.json
sharepoint.json
teams.json
purview.json
```

Validate the manifest against schema:

```powershell
npx -y ajv-cli validate `
    -s baselines/schema/evidence-bundle.schema.json `
    -d evidence/<tenant>/<ts>/manifest.json `
    --spec=draft2020 -c ajv-formats --strict=false
```

## Stage 4 — baseline resolution

Copy the tenant template and populate:

```powershell
$dest = "baselines/tenants/$tenantId"
Copy-Item baselines/tenants/_template $dest -Recurse
# Edit $dest/tenant.yaml — set tenant.id, auth.mode, profiles list
```

Resolve the layered baseline:

```powershell
pwsh scripts/common/Resolve-Baseline.ps1 `
    -TenantConfigPath  "baselines/tenants/$tenantId/tenant.yaml" `
    -OutputPath        "./resolved-baselines/$tenantId.json" `
    -Validate
```

**Expected:** JSON file containing `target` with merged `entra`, `exchange`, `sharepoint`, `teams`, `purview`, etc. No schema errors (with `-Validate`).

**Sanity checks:**

```powershell
jq '.layersApplied'                ./resolved-baselines/$tenantId.json
jq '.target.entra.break_glass'    ./resolved-baselines/$tenantId.json
jq '.target.purview.unified_audit_log_enabled' ./resolved-baselines/$tenantId.json
```

## Stage 5 — diff / findings

```powershell
pwsh scripts/common/Compare-TenantState.ps1 `
    -ResolvedBaselinePath "./resolved-baselines/$tenantId.json" `
    -BundlePath           "./evidence/$tenantId/<timestamp>" `
    -OutputPath           "./evidence/$tenantId/<timestamp>/findings.json"
```

**Expected:** a `findings.json` with a `summary` block (counts by severity) and `findings` array. On a fresh dev tenant with defaults, expect many findings (most settings will not match the CIS L1+L2 baseline — that's the point).

Sample:

```powershell
jq '.summary' evidence/<tenant>/<ts>/findings.json
jq '.findings[0]' evidence/<tenant>/<ts>/findings.json
```

## Stage 6 — decision time

Based on what broke:

- **If scripts ran cleanly and findings look sensible** → the stack works. Log a PR-ready commit with any cmdlet-drift fixes. You're ready to run against staging tenants.
- **If a workload script is broken** → fix forward in that one script. Don't commit workarounds to other scripts.
- **If findings are clearly wrong** (e.g. ticking "MFA not enabled" when tenant clearly has it) → the rule's `scanPath` is mapped to the wrong JSON field. Adjust `scripts/common/diff-rules.yaml`.
- **If the resolver output surprises you** → check `layersApplied`; expected order is `global/defaults` → `global/break-glass` → each profile → `overrides`.

## What to record

After a smoke test, update this file's "Known cmdlet drift" section below with anything you had to adjust:

## Known cmdlet drift (populate as discovered)

| Module | Version | Symptom | Fix |
|---|---|---|---|
| *populated by first smoke test* | | | |

## Teardown

Evidence bundles in `./evidence/` may contain tenant identifiers — **gitignored**, don't commit.

```powershell
Remove-Item ./evidence/smoke -Recurse -Force
Remove-Item ./resolved-baselines -Recurse -Force -ErrorAction SilentlyContinue
```

Disconnect sessions:

```powershell
Disconnect-MgGraph
Disconnect-ExchangeOnline -Confirm:$false
Disconnect-SPOService
Disconnect-MicrosoftTeams
```
