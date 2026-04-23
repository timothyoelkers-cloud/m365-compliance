<#
.SYNOPSIS
    Read-only scan of Microsoft Defender XDR configuration — Secure Score (history + current),
    Defender for Cloud Apps state, alert policies. DfO policies are captured by Invoke-ExchangeScan.ps1
    (they share Exchange cmdlets); this script focuses on cross-workload Defender surface.

.DESCRIPTION
    Uses Graph Security API for Secure Score and SecureScoreControlProfiles. MDA/MDI/MDE state read via
    available endpoints where licensed.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputPath,
    [int]$SecureScoreHistoryDays = 90
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$ctx = Get-MgContext -ErrorAction Stop
if ($ctx.TenantId -ne $TenantId) {
    throw "Graph context tenant ($($ctx.TenantId)) does not match -TenantId ($TenantId)."
}

Import-Module Microsoft.Graph.Security -ErrorAction Stop

function Safe { param([scriptblock]$B,[string]$L) try { & $B } catch { Write-Warning "$L failed: $($_.Exception.Message)"; $null } }

$data = [ordered]@{
    schemaVersion = '1.0.0'
    tenantId      = $TenantId
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    producedBy    = 'Invoke-DefenderScan.ps1@1.0.0'
    secureScore          = $null
    secureScoreHistory   = @()
    secureScoreProfiles  = @()
    alertPoliciesGraph   = @()
    defenderForCloudApps = $null
    defenderForIdentity  = $null
}

$data.secureScore = Safe -L 'SecureScore' -B {
    Get-MgSecuritySecureScore -Top 1 -ErrorAction Stop | Select-Object Id, CreatedDateTime, CurrentScore, MaxScore, ActiveUserCount, LicensedUserCount, EnabledServices
}

$data.secureScoreHistory = Safe -L 'SecureScoreHistory' -B {
    Get-MgSecuritySecureScore -Top $SecureScoreHistoryDays -ErrorAction Stop |
        Select-Object CreatedDateTime, CurrentScore, MaxScore |
        Sort-Object CreatedDateTime
}

$data.secureScoreProfiles = Safe -L 'SecureScoreProfiles' -B {
    Get-MgSecuritySecureScoreControlProfile -All |
        Select-Object Id, Title, ControlCategory, MaxScore, ActionType, Tier, ImplementationCost, UserImpact, Rank, ActionUrl |
        Sort-Object Rank
}

# Alert policies (newer unified) — Graph beta endpoint. Best-effort.
$data.alertPoliciesGraph = Safe -L 'AlertPoliciesGraph' -B {
    # GET /beta/security/alerts_v2 is for instances, not policies. Policies live behind Purview (Get-ProtectionAlert)
    # which is covered in Purview scan. Here we sample recent high-severity alerts for trend indication.
    Get-MgSecurityAlertV2 -Top 100 -Filter "severity eq 'high'" -ErrorAction SilentlyContinue |
        Select-Object Id, Title, Severity, Status, Category, DetectionSource, CreatedDateTime
}

$data.defenderForCloudApps = Safe -L 'MDA' -B {
    # Verify via Graph: device registrations under cloudAppSecurity are limited; prefer the MDA REST API
    # which requires a tenant-specific base URL (https://<tenant>.portal.cloudappsecurity.com).
    # We capture portal-state via Graph Security policy where possible; deeper MDA reads belong to a separate
    # script that takes the MDA API token explicitly.
    @{
        note = 'MDA detailed state requires a dedicated MDA API token. Populate via separate script with MDA-specific credential.'
    }
}

$data.defenderForIdentity = Safe -L 'MDI' -B {
    # Similar — MDI (Entra ID protection integration) status is partially exposed via Graph,
    # but sensor health requires the MDI API / portal.
    @{
        note = 'MDI sensor health requires MDI API. Use Graph /identityProtection/riskyUsers + riskDetections as proxy.'
        riskyUserCount = (Get-MgRiskyUser -Top 1 -ErrorAction SilentlyContinue | Measure-Object).Count
    }
}

$json = $data | ConvertTo-Json -Depth 20
$json | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
