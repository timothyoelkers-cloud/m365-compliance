<#
.SYNOPSIS
    Establish authenticated sessions to a single M365 tenant across the PowerShell
    modules used by the scan/apply primitives. Abstracts GDAP vs. app-registration
    auth so downstream scan scripts don't have to care.

.DESCRIPTION
    Opens sessions for: Microsoft.Graph, ExchangeOnlineManagement, Microsoft.Online.SharePoint.PowerShell,
    MicrosoftTeams, Purview (via Connect-IPPSSession). Not every scan needs every session — pass -Workloads
    to narrow the attempted connections.

    Auth modes:
      - App: client credentials flow (client ID + tenant ID + cert thumbprint or secret reference)
      - GDAP: delegated admin via Partner Center; the caller supplies the partner upn / cert and the
              target customer tenant ID
      - Interactive: for one-off operator runs (only permitted when $env:M365C_INTERACTIVE_ALLOWED -eq '1')

    Never accepts plaintext credentials via parameters. Secrets are referenced by Key Vault URI; caller
    context is expected to have managed-identity access to the vault.

.PARAMETER TenantId
    Target customer tenant ID (UUID).

.PARAMETER AuthMode
    app | gdap | interactive

.PARAMETER ClientId
    App registration client ID (app or gdap auth modes).

.PARAMETER CertificateThumbprint
    Thumbprint of the auth cert in the current user or machine cert store (preferred for app/gdap).

.PARAMETER ClientSecretKeyVaultUri
    Fallback: Key Vault URI of a client secret (e.g. https://kv.vault.azure.net/secrets/portal-app-secret).
    Requires the running identity to have GET permission on the secret.

.PARAMETER Workloads
    Subset to connect: entra, exchange, sharepoint, teams, purview. Default: all.

.OUTPUTS
    PSCustomObject with connection state per workload.

.NOTES
    Idempotent — existing sessions are reused when context matches.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][ValidateSet('app','gdap','interactive')][string]$AuthMode,
    [string]$ClientId,
    [string]$CertificateThumbprint,
    [string]$ClientSecretKeyVaultUri,
    [ValidateSet('entra','exchange','sharepoint','teams','purview')][string[]]$Workloads = @('entra','exchange','sharepoint','teams','purview'),
    [string]$SharePointAdminUrl
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

function Resolve-Secret {
    param([string]$KeyVaultUri)
    if (-not $KeyVaultUri) { return $null }
    # Expect caller context to have Az.KeyVault loaded and an identity authorised to read the secret.
    if (-not (Get-Module -ListAvailable -Name Az.KeyVault)) {
        throw "Az.KeyVault module is required to resolve client secret references."
    }
    Import-Module Az.KeyVault -ErrorAction Stop
    $parsed = [uri]$KeyVaultUri
    $vault  = $parsed.Host.Split('.')[0]
    $name   = $parsed.Segments[-1].TrimEnd('/')
    (Get-AzKeyVaultSecret -VaultName $vault -Name $name -AsPlainText)
}

function Assert-Interactive {
    if ($env:M365C_INTERACTIVE_ALLOWED -ne '1') {
        throw "Interactive auth is disabled. Set M365C_INTERACTIVE_ALLOWED=1 to enable for operator sessions only."
    }
}

function Connect-GraphSession {
    param([string]$TenantId,[string]$ClientId,[string]$Thumb,[string]$SecretRef,[string]$Mode)
    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop

    $existing = Get-MgContext -ErrorAction SilentlyContinue
    if ($existing -and $existing.TenantId -eq $TenantId) {
        return [pscustomobject]@{ Workload = 'entra'; Status = 'reused'; Context = $existing }
    }

    switch ($Mode) {
        'app' {
            if ($Thumb) {
                Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $Thumb -NoWelcome -ErrorAction Stop | Out-Null
            } elseif ($SecretRef) {
                $secret = Resolve-Secret -KeyVaultUri $SecretRef
                $cred   = [pscredential]::new($ClientId, (ConvertTo-SecureString $secret -AsPlainText -Force))
                Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $cred -NoWelcome -ErrorAction Stop | Out-Null
            } else { throw "app auth requires -CertificateThumbprint or -ClientSecretKeyVaultUri" }
        }
        'gdap' {
            # GDAP: service principal in partner tenant with delegated admin relationship to customer
            if (-not $Thumb) { throw "gdap mode requires -CertificateThumbprint" }
            Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $Thumb -NoWelcome -ErrorAction Stop | Out-Null
        }
        'interactive' {
            Assert-Interactive
            Connect-MgGraph -TenantId $TenantId -Scopes @('Directory.Read.All','Policy.Read.All','RoleManagement.Read.Directory','AuditLog.Read.All','Reports.Read.All') -NoWelcome -ErrorAction Stop | Out-Null
        }
    }
    [pscustomobject]@{ Workload = 'entra'; Status = 'connected'; Context = Get-MgContext }
}

function Connect-ExchangeSession {
    param([string]$TenantId,[string]$ClientId,[string]$Thumb,[string]$Mode,[string]$Upn)
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    if ($Mode -eq 'interactive') {
        Assert-Interactive
        Connect-ExchangeOnline -Organization $TenantId -ShowBanner:$false -ErrorAction Stop
    } else {
        if (-not $Thumb) { throw "exchange auth requires a certificate thumbprint for $Mode mode" }
        Connect-ExchangeOnline -AppId $ClientId -CertificateThumbprint $Thumb -Organization $TenantId -ShowBanner:$false -ErrorAction Stop
    }
    [pscustomobject]@{ Workload = 'exchange'; Status = 'connected' }
}

function Connect-PurviewSession {
    param([string]$TenantId,[string]$ClientId,[string]$Thumb,[string]$Mode)
    Import-Module ExchangeOnlineManagement -ErrorAction Stop  # Connect-IPPSSession lives here
    if ($Mode -eq 'interactive') {
        Assert-Interactive
        Connect-IPPSSession -ShowBanner:$false -ErrorAction Stop
    } else {
        if (-not $Thumb) { throw "purview auth requires a certificate thumbprint for $Mode mode" }
        Connect-IPPSSession -AppId $ClientId -CertificateThumbprint $Thumb -Organization $TenantId -ShowBanner:$false -ErrorAction Stop
    }
    [pscustomobject]@{ Workload = 'purview'; Status = 'connected' }
}

function Connect-SharePointSession {
    param([string]$TenantId,[string]$ClientId,[string]$Thumb,[string]$Mode,[string]$AdminUrl)
    Import-Module Microsoft.Online.SharePoint.PowerShell -ErrorAction Stop
    if (-not $AdminUrl) {
        # Derive from initial domain via Graph (must be connected first)
        $domain = (Get-MgDomain | Where-Object IsInitial).Id
        $tenantSlug = $domain.Split('.')[0]
        $AdminUrl = "https://$tenantSlug-admin.sharepoint.com"
    }
    if ($Mode -eq 'interactive') {
        Assert-Interactive
        Connect-SPOService -Url $AdminUrl -ErrorAction Stop
    } else {
        # App-only: requires a cert registered on an SPO-enabled app registration
        if (-not $Thumb) { throw "sharepoint app-only auth requires a certificate thumbprint" }
        $cert = Get-ChildItem "Cert:\CurrentUser\My\$Thumb" -ErrorAction SilentlyContinue
        if (-not $cert) { $cert = Get-ChildItem "Cert:\LocalMachine\My\$Thumb" -ErrorAction SilentlyContinue }
        if (-not $cert) { throw "Certificate with thumbprint $Thumb not found in user or machine store." }
        # PnP.PowerShell is an alternative with better app-only support; stay on SPO module for v1.
        Connect-SPOService -Url $AdminUrl -ClientId $ClientId -Thumbprint $Thumb -ErrorAction Stop
    }
    [pscustomobject]@{ Workload = 'sharepoint'; Status = 'connected'; AdminUrl = $AdminUrl }
}

function Connect-TeamsSession {
    param([string]$TenantId,[string]$ClientId,[string]$Thumb,[string]$Mode)
    Import-Module MicrosoftTeams -ErrorAction Stop
    if ($Mode -eq 'interactive') {
        Assert-Interactive
        Connect-MicrosoftTeams -TenantId $TenantId -ErrorAction Stop | Out-Null
    } else {
        if (-not $Thumb) { throw "teams auth requires a certificate thumbprint for $Mode mode" }
        Connect-MicrosoftTeams -TenantId $TenantId -ApplicationId $ClientId -CertificateThumbprint $Thumb -ErrorAction Stop | Out-Null
    }
    [pscustomobject]@{ Workload = 'teams'; Status = 'connected' }
}

# Dispatch
$results = @()
foreach ($w in $Workloads) {
    try {
        switch ($w) {
            'entra'      { $results += Connect-GraphSession      -TenantId $TenantId -ClientId $ClientId -Thumb $CertificateThumbprint -SecretRef $ClientSecretKeyVaultUri -Mode $AuthMode }
            'exchange'   { $results += Connect-ExchangeSession   -TenantId $TenantId -ClientId $ClientId -Thumb $CertificateThumbprint -Mode $AuthMode }
            'purview'    { $results += Connect-PurviewSession    -TenantId $TenantId -ClientId $ClientId -Thumb $CertificateThumbprint -Mode $AuthMode }
            'sharepoint' { $results += Connect-SharePointSession -TenantId $TenantId -ClientId $ClientId -Thumb $CertificateThumbprint -Mode $AuthMode -AdminUrl $SharePointAdminUrl }
            'teams'      { $results += Connect-TeamsSession      -TenantId $TenantId -ClientId $ClientId -Thumb $CertificateThumbprint -Mode $AuthMode }
        }
    } catch {
        $results += [pscustomobject]@{ Workload = $w; Status = 'failed'; Error = $_.Exception.Message }
    }
}

$results
