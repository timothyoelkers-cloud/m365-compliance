<#
.SYNOPSIS
    Orchestrate a full read-only tenant scan across every workload and emit a signed evidence bundle
    that conforms to baselines/schema/evidence-bundle.schema.json.

.DESCRIPTION
    Executes the per-workload scan primitives in a safe read-only order, aggregates their JSON artefacts
    into a single evidence bundle directory with a manifest and SHA-256 chain. This is the entry point
    the portal's scan runner containers invoke.

    Assumes the session connections have already been established via Connect-Tenant.ps1 (or equivalent).

.PARAMETER TenantId
.PARAMETER OutputRoot         Bundle root directory (a timestamped subdirectory is created here).
.PARAMETER BaselineGitSha     Git SHA of the baseline repo state; embedded in the manifest.
.PARAMETER BaselineProfiles   Profile identifiers (name@version) embedded in the manifest.
.PARAMETER Operator           Caller identity — user UPN, service principal ID, or managed identity name.
.PARAMETER Workloads          Subset of workloads to scan (default: all).
.PARAMETER PowerBIAccessToken Optional token for Power BI scan; pass from caller.
.PARAMETER SigningCertThumbprint Optional certificate thumbprint to sign the manifest SHA.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputRoot,
    [Parameter(Mandatory)][string]$BaselineGitSha,
    [string[]]$BaselineProfiles = @(),
    [Parameter(Mandatory)][string]$Operator,
    [ValidateSet('entra','conditional-access','exchange','sharepoint','teams','purview','defender','intune','powerbi')]
    [string[]]$Workloads = @('entra','conditional-access','exchange','sharepoint','teams','purview','defender','intune'),
    [string]$PowerBIAccessToken,
    [string]$SigningCertThumbprint
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$runId = [guid]::NewGuid().ToString()
$startedAt = (Get-Date).ToUniversalTime()
$ts = $startedAt.ToString('yyyyMMddTHHmmssZ')
$bundleDir = Join-Path $OutputRoot "$TenantId/$ts"
New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null

$scripts = @{
    'entra'              = 'Invoke-EntraScan.ps1'
    'conditional-access' = 'Invoke-ConditionalAccessScan.ps1'
    'exchange'           = 'Invoke-ExchangeScan.ps1'
    'sharepoint'         = 'Invoke-SharePointScan.ps1'
    'teams'              = 'Invoke-TeamsScan.ps1'
    'purview'            = 'Invoke-PurviewScan.ps1'
    'defender'           = 'Invoke-DefenderScan.ps1'
    'intune'             = 'Invoke-IntuneScan.ps1'
    'powerbi'            = 'Invoke-PowerBIScan.ps1'
}

function Get-FileSha256 {
    param([string]$Path)
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower()
}

$artefacts = @()
$warnings  = @()
$errors    = @()

foreach ($w in $Workloads) {
    $scriptName = $scripts[$w]
    $scriptPath = Join-Path $here $scriptName
    if (-not (Test-Path $scriptPath)) {
        $errors += "Missing scan script: $scriptName"
        continue
    }
    $out = Join-Path $bundleDir "$w.json"
    try {
        Write-Host "Scanning $w -> $out"
        switch ($w) {
            'powerbi' {
                if (-not $PowerBIAccessToken) { $warnings += "powerbi skipped: no -PowerBIAccessToken supplied"; continue }
                & $scriptPath -TenantId $TenantId -OutputPath $out -AccessToken $PowerBIAccessToken | Out-Null
            }
            default { & $scriptPath -TenantId $TenantId -OutputPath $out | Out-Null }
        }
        if (Test-Path $out) {
            $info = Get-Item $out
            $artefacts += [ordered]@{
                workload   = $w
                path       = (Resolve-Path $out).Path.Replace($bundleDir + [IO.Path]::DirectorySeparatorChar, '').Replace($bundleDir + '/', '')
                sha256     = Get-FileSha256 -Path $out
                bytes      = [int64]$info.Length
                producedBy = "$scriptName@1.0.0"
            }
        } else {
            $warnings += "$w produced no output"
        }
    } catch {
        $errors += "$w failed: $($_.Exception.Message)"
    }
}

$completedAt = (Get-Date).ToUniversalTime()

# Build manifest (signature field computed last)
$manifest = [ordered]@{
    schemaVersion = '1.0.0'
    tenant        = [ordered]@{ tenantId = $TenantId }
    run           = [ordered]@{
        runId        = $runId
        mode         = 'audit'
        startedAt    = $startedAt.ToString('o')
        completedAt  = $completedAt.ToString('o')
        operator     = [ordered]@{
            kind        = if ($Operator -match '@') { 'user' } elseif ($Operator -match '^[0-9a-f\-]{36}$') { 'service-principal' } else { 'managed-identity' }
            id          = $Operator
            displayName = $Operator
        }
    }
    baseline      = [ordered]@{
        gitSha   = $BaselineGitSha
        profiles = @($BaselineProfiles | ForEach-Object {
            $parts = $_ -split '@',2
            [ordered]@{ name = $parts[0]; version = if ($parts.Count -gt 1) { $parts[1] } else { 'unknown' } }
        })
        overridesPresent = $false
    }
    artefacts     = $artefacts
    findings      = @()
    integrity     = [ordered]@{
        manifestSha256 = ''
        signature      = $null
    }
}

# Manifest hash: hash the JSON with integrity.signature = null, integrity.manifestSha256 = ''
$manifestForHash = $manifest | ConvertTo-Json -Depth 25
$hashBytes = [System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($manifestForHash))
$manifestSha = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
$manifest.integrity.manifestSha256 = $manifestSha

# Optional signing
if ($SigningCertThumbprint) {
    try {
        $cert = Get-ChildItem "Cert:\CurrentUser\My\$SigningCertThumbprint" -ErrorAction SilentlyContinue
        if (-not $cert) { $cert = Get-ChildItem "Cert:\LocalMachine\My\$SigningCertThumbprint" -ErrorAction SilentlyContinue }
        if ($cert) {
            $rsa = $cert.PrivateKey
            $sig = $rsa.SignData([Text.Encoding]::UTF8.GetBytes($manifestSha), [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $manifest.integrity.signature = [ordered]@{
                alg   = 'RS256'
                kid   = $SigningCertThumbprint
                value = [Convert]::ToBase64String($sig)
            }
        } else { $warnings += "Signing cert $SigningCertThumbprint not found; manifest unsigned." }
    } catch {
        $warnings += "Manifest signing failed: $($_.Exception.Message)"
    }
}

$manifestPath = Join-Path $bundleDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 25 | Out-File -LiteralPath $manifestPath -Encoding utf8

# Sidecar — separate hash chain file for quick integrity verification
$chainPath = Join-Path $bundleDir 'bundle.sha256'
$chainLines = @("$manifestSha  manifest.json")
$chainLines += $artefacts | ForEach-Object { "$($_.sha256)  $($_.path)" }
$chainLines -join "`n" | Out-File -LiteralPath $chainPath -Encoding ascii

[pscustomobject]@{
    runId        = $runId
    tenantId     = $TenantId
    bundlePath   = (Resolve-Path $bundleDir).Path
    manifestSha  = $manifestSha
    artefacts    = $artefacts.Count
    warnings     = $warnings
    errors       = $errors
}
