<#
.SYNOPSIS
    Read-only scan of SharePoint Online + OneDrive for Business tenant-level configuration.
    Covers CIS v6 Section 7.

.DESCRIPTION
    Captures tenant-level settings (sharing, link defaults, anonymous link expiry), sync client
    restriction state, and a sample of site-level sharing overrides for sites exceeding tenant defaults.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputPath,
    [int]$SiteSampleSize = 100
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not (Get-Command Get-SPOTenant -ErrorAction SilentlyContinue)) {
    throw "SharePoint Online session not present. Run Connect-Tenant.ps1 with -Workloads sharepoint first."
}

function Safe { param([scriptblock]$B,[string]$L) try { & $B } catch { Write-Warning "$L failed: $($_.Exception.Message)"; $null } }

$data = [ordered]@{
    schemaVersion = '1.0.0'
    tenantId      = $TenantId
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    producedBy    = 'Invoke-SharePointScan.ps1@1.0.0'
    tenant        = $null
    syncRestriction = $null
    sitesWithExtendedSharing = @()
    sharingDomainRestrictions = $null
    geoLocations  = @()
}

$data.tenant = Safe -L 'SPOTenant' -B {
    Get-SPOTenant | Select-Object `
        SharingCapability, `
        OneDriveSharingCapability, `
        DefaultSharingLinkType, `
        DefaultLinkPermission, `
        RequireAnonymousLinksExpireInDays, `
        ExternalUserExpirationRequired, `
        ExternalUserExpireInDays, `
        PreventExternalUsersFromResharing, `
        ShowEveryoneClaim, `
        ShowAllUsersClaim, `
        ShowEveryoneExceptExternalUsersClaim, `
        SharingDomainRestrictionMode, `
        NotifyOwnersWhenItemsReshared, `
        NotifyOwnersWhenInvitationsAccepted, `
        ConditionalAccessPolicy, `
        AllowedDomainListForSyncClient, `
        BlockMacSync, `
        DisableReportProblemDialog, `
        DenyAddAndCustomizePages, `
        LegacyAuthProtocolsEnabled, `
        OneDriveForGuestsEnabled, `
        OrphanedPersonalSitesRetentionPeriod, `
        ODBAccessRequests, `
        ODBMembersCanShare, `
        EmailAttestationRequired, `
        EmailAttestationReAuthDays, `
        DefaultOneDriveMode, `
        ProvisionSharedWithEveryoneFolder, `
        CustomizedExternalSharingServiceUrl, `
        DisallowInfectedFileDownload
}

$data.syncRestriction = Safe -L 'SyncRestriction' -B {
    Get-SPOTenantSyncClientRestriction | Select-Object TenantRestrictionEnabled, AllowedDomainList, BlockMacSync, OptOutOfGrooveBlock, OptOutOfGrooveSoftBlock
}

$data.sharingDomainRestrictions = Safe -L 'SharingDomainRestrictions' -B {
    $t = Get-SPOTenant
    [ordered]@{
        mode          = $t.SharingDomainRestrictionMode
        allowedDomains= @($t.SharingAllowedDomainList -split ' ' | Where-Object { $_ })
        blockedDomains= @($t.SharingBlockedDomainList -split ' ' | Where-Object { $_ })
    }
}

# Site-level overrides — find sites that share *more* widely than tenant default
$data.sitesWithExtendedSharing = Safe -L 'SiteSharing' -B {
    $t = Get-SPOTenant
    $tenantCap = $t.SharingCapability
    $severity = @{ Disabled = 0; ExistingExternalUserSharingOnly = 1; ExternalUserSharingOnly = 2; ExternalUserAndGuestSharing = 3 }
    $tenantSev = $severity[$tenantCap]
    Get-SPOSite -Limit $SiteSampleSize -IncludePersonalSite:$false |
        Where-Object { $severity[$_.SharingCapability] -gt $tenantSev } |
        Select-Object Url, SharingCapability, Template, LockState, StorageQuota
}

$data.geoLocations = Safe -L 'GeoLocations' -B { Get-SPOGeoStorageQuota -ErrorAction SilentlyContinue }

$json = $data | ConvertTo-Json -Depth 20
$json | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
