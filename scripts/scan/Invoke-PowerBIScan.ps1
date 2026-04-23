<#
.SYNOPSIS
    Read-only scan of Power BI tenant settings. Covers CIS v6 Section 9.

.DESCRIPTION
    Reads tenant-level Power BI admin settings via the Power BI REST Admin API. Requires a token acquired
    against https://analysis.windows.net/powerbi/api — callers typically use the same app registration as
    the rest of the portal with Power BI Service admin permissions consented.

    This script expects an access token to be passed in or sourced from MSAL (app-only auth).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$AccessToken  # Power BI Service token
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$headers = @{ Authorization = "Bearer $AccessToken"; 'Content-Type' = 'application/json' }

function Invoke-PbiAdmin {
    param([string]$Path)
    try {
        Invoke-RestMethod -Method GET -Uri "https://api.powerbi.com$Path" -Headers $headers -ErrorAction Stop
    } catch {
        Write-Warning "Power BI Admin $Path failed: $($_.Exception.Message)"
        $null
    }
}

$data = [ordered]@{
    schemaVersion = '1.0.0'
    tenantId      = $TenantId
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    producedBy    = 'Invoke-PowerBIScan.ps1@1.0.0'
    tenantSettings = $null
    capacities    = @()
    activeWorkspaces = @()
    externalUsers = @()
    orphanedWorkspaces = @()
}

# Tenant settings — full snapshot
$data.tenantSettings = Invoke-PbiAdmin -Path '/v1.0/myorg/admin/tenantsettings'

# Capacities (Premium / PPU / Fabric)
$data.capacities = Invoke-PbiAdmin -Path '/v1.0/myorg/admin/capacities'

# Workspace scan — scoped to 100 for cost
$data.activeWorkspaces = Invoke-PbiAdmin -Path '/v1.0/myorg/admin/groups?%24top=100&%24filter=state eq ''Active'''

# External users / guests
$data.externalUsers = Invoke-PbiAdmin -Path '/v1.0/myorg/admin/widelySharedArtifacts/linksSharedToWholeOrganization?%24top=100'

# Orphaned workspaces (no admin)
# Requires scan-result API — a two-call pattern (POST scan, then GET result). Included as a TODO.
$data.orphanedWorkspaces = @{ note = 'Requires async scanning API (POST /admin/workspaces/getInfo + GET scanResult). Implement in portal runner.' }

$json = $data | ConvertTo-Json -Depth 25
$json | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
