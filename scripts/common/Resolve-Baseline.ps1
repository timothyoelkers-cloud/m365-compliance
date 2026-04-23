<#
.SYNOPSIS
    Resolve a tenant's effective target-state baseline from the layered sources
    (global defaults -> profile chain -> tenant overrides) and emit a single JSON
    document that downstream tooling (diff engine, apply runners, the portal)
    consumes.

.DESCRIPTION
    Layering order (lowest precedence first):

      1. baselines/global/defaults.yaml
      2. baselines/global/break-glass.yaml
      3. For each profile in tenant.yaml's `profiles:` (in declared order):
           baselines/profiles/<name>.yaml
         Profile pin format: 'name@version-spec' (spec can be exact '1.2.0',
         tilde '~1.2', or caret '^1.2' — non-matching pins fail loudly).
      4. baselines/tenants/<tenant-id>/overrides.yaml (if present)

    Merge semantics:

      - Scalars / null values: later wins.
      - Objects: recursive merge.
      - Lists with an `id` field on items: named-merge (same id replaces; new
        ids append).
      - Lists without `id`: later wins (whole-list replacement).
      - `replaces: [id1, id2]` on a list item: when merging, items in lower
        layers whose id is in the replaces list are removed before this layer
        is applied. Used to let overlays supersede upstream CA / compliance
        / retention entries cleanly.

    Outputs a single JSON document plus (optionally) a validation status against
    baseline.schema.json when ajv is available on PATH.

.PARAMETER TenantConfigPath
    Path to a tenant.yaml (typically under baselines/tenants/<id>/).

.PARAMETER BaselinesRoot
    Path to the baselines/ directory. Defaults to the parent of the script's
    directory + '/baselines'.

.PARAMETER OutputPath
    File path for the resolved baseline JSON.

.PARAMETER Validate
    If present, validates the resolved output against baseline.schema.json via
    ajv (requires `npx` on PATH).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TenantConfigPath,
    [string]$BaselinesRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [switch]$Validate
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Verbose "Installing powershell-yaml for current user scope."
    Install-Module powershell-yaml -Scope CurrentUser -Force -AcceptLicense | Out-Null
}
Import-Module powershell-yaml -ErrorAction Stop

if (-not $BaselinesRoot) {
    $BaselinesRoot = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'baselines'
    if (-not (Test-Path $BaselinesRoot)) {
        $BaselinesRoot = Join-Path (Get-Location).Path 'baselines'
    }
}
if (-not (Test-Path $BaselinesRoot)) {
    throw "BaselinesRoot not found: $BaselinesRoot"
}

function Read-Yaml {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $text = Get-Content -Raw -LiteralPath $Path
    ConvertFrom-Yaml -Yaml $text -Ordered
}

function Test-IsDict {
    param($Value)
    if ($null -eq $Value) { return $false }
    $Value -is [System.Collections.IDictionary]
}

function Test-IsList {
    param($Value)
    if ($null -eq $Value) { return $false }
    ($Value -is [System.Collections.IList]) -and -not ($Value -is [string])
}

function Merge-LayeredValue {
    param($Base, $Overlay)

    if ($null -eq $Overlay) { return $Base }
    if ($null -eq $Base)    { return $Overlay }

    if ((Test-IsDict $Base) -and (Test-IsDict $Overlay)) {
        $out = [ordered]@{}
        foreach ($key in $Base.Keys)    { $out[$key] = $Base[$key] }
        foreach ($key in $Overlay.Keys) {
            if ($out.Contains($key)) {
                $out[$key] = Merge-LayeredValue -Base $out[$key] -Overlay $Overlay[$key]
            } else {
                $out[$key] = $Overlay[$key]
            }
        }
        return $out
    }

    if ((Test-IsList $Base) -and (Test-IsList $Overlay)) {
        $overlayHasIds = $true
        foreach ($item in $Overlay) {
            if (-not (Test-IsDict $item) -or -not $item.Contains('id')) { $overlayHasIds = $false; break }
        }
        $baseHasIds = $true
        foreach ($item in $Base) {
            if (-not (Test-IsDict $item) -or -not $item.Contains('id')) { $baseHasIds = $false; break }
        }

        if (-not ($overlayHasIds -and $baseHasIds)) {
            return $Overlay
        }

        $toRemove = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($item in $Overlay) {
            if ($item.Contains('replaces') -and (Test-IsList $item.replaces)) {
                foreach ($r in $item.replaces) { [void]$toRemove.Add($r) }
            }
        }

        $baseById = [ordered]@{}
        foreach ($item in $Base) {
            if ($toRemove.Contains($item.id)) { continue }
            $baseById[$item.id] = $item
        }

        foreach ($item in $Overlay) {
            if ($baseById.Contains($item.id)) {
                $baseById[$item.id] = Merge-LayeredValue -Base $baseById[$item.id] -Overlay $item
            } else {
                $baseById[$item.id] = $item
            }
        }

        return @($baseById.Values)
    }

    return $Overlay
}

function Resolve-ProfilePath {
    param([string]$Root, [string]$Pin)
    $parts = $Pin -split '@',2
    $name  = $parts[0]
    $spec  = if ($parts.Count -gt 1) { $parts[1] } else { '*' }

    $candidate = Join-Path $Root "profiles/$name.yaml"
    if (-not (Test-Path $candidate)) { throw "Profile '$name' not found at $candidate" }

    $doc = Read-Yaml -Path $candidate
    if ($doc.Contains('version')) {
        $ver = [string]$doc.version
        if ($spec -ne '*' -and $spec -ne $ver) {
            switch -regex ($spec) {
                '^~(\d+)\.(\d+)' {
                    $major = [int]$Matches[1]; $minor = [int]$Matches[2]
                    $vparts = $ver -split '\.'
                    if ([int]$vparts[0] -ne $major -or [int]$vparts[1] -ne $minor) {
                        throw "Profile '$name' version $ver does not satisfy tilde pin ~$major.$minor"
                    }
                }
                '^\^(\d+)\.' {
                    $major = [int]$Matches[1]
                    $vparts = $ver -split '\.'
                    if ([int]$vparts[0] -ne $major) {
                        throw "Profile '$name' version $ver does not satisfy caret pin ^$major.x"
                    }
                }
                default {
                    if ($spec -ne $ver) {
                        throw "Profile '$name' version $ver does not satisfy pin '$spec'"
                    }
                }
            }
        }
    }
    return @{ path = $candidate; doc = $doc; pin = $Pin }
}

$tenantDoc = Read-Yaml -Path $TenantConfigPath
if (-not $tenantDoc -or -not $tenantDoc.Contains('tenant')) {
    throw "$TenantConfigPath is not a tenant registry document (missing top-level 'tenant:' key)."
}
$tenantId = [string]$tenantDoc.tenant.id
$profiles = @($tenantDoc.profiles)

$layers = [System.Collections.Generic.List[pscustomobject]]::new()

$globalDefaults   = Join-Path $BaselinesRoot 'global/defaults.yaml'
$globalBreakGlass = Join-Path $BaselinesRoot 'global/break-glass.yaml'
if (Test-Path $globalDefaults)   { $layers.Add([pscustomobject]@{ name = 'global/defaults';    path = $globalDefaults;   doc = (Read-Yaml $globalDefaults) }) }
if (Test-Path $globalBreakGlass) { $layers.Add([pscustomobject]@{ name = 'global/break-glass'; path = $globalBreakGlass; doc = (Read-Yaml $globalBreakGlass) }) }

foreach ($pin in $profiles) {
    $info = Resolve-ProfilePath -Root $BaselinesRoot -Pin $pin
    $layers.Add([pscustomobject]@{ name = "profile/$pin"; path = $info.path; doc = $info.doc })
}

$overridesPath = Join-Path $BaselinesRoot "tenants/$tenantId/overrides.yaml"
$overridesPresent = Test-Path $overridesPath
if ($overridesPresent) {
    $layers.Add([pscustomobject]@{ name = "tenant/$tenantId/overrides"; path = $overridesPath; doc = (Read-Yaml $overridesPath) })
}

$resolved = [ordered]@{}
foreach ($layer in $layers) {
    $layerDoc = $layer.doc
    if (-not $layerDoc) { continue }
    $toMerge = [ordered]@{}
    foreach ($key in $layerDoc.Keys) {
        if ($key -in @('metadata','version','rollout')) { continue }
        $toMerge[$key] = $layerDoc[$key]
    }
    $resolved = Merge-LayeredValue -Base $resolved -Overlay $toMerge
}

$resolvedWithMeta = [ordered]@{
    schemaVersion    = '1.0.0'
    resolvedAt       = (Get-Date).ToUniversalTime().ToString('o')
    tenant           = $tenantDoc.tenant
    auth_mode        = if ($tenantDoc.Contains('auth')) { $tenantDoc.auth.mode } else { 'unknown' }
    profiles         = $profiles
    overridesPresent = $overridesPresent
    layersApplied    = @($layers | ForEach-Object { $_.name })
    target           = $resolved
}

$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$json = $resolvedWithMeta | ConvertTo-Json -Depth 30
$json | Out-File -LiteralPath $OutputPath -Encoding utf8

if ($Validate) {
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-Warning "-Validate requested but 'npx' not on PATH; skipping schema validation."
    } else {
        $schema = Join-Path $BaselinesRoot 'schema/baseline.schema.json'
        $targetOnly = Join-Path $outDir '.resolved.target.json'
        ($resolved + @{ version = '0.0.0-resolved'; metadata = @{ name = 'resolved'; kind = 'profile' } }) |
            ConvertTo-Json -Depth 30 |
            Out-File -LiteralPath $targetOnly -Encoding utf8
        $proc = & npx -y ajv-cli validate -s $schema -d $targetOnly --spec=draft2020 -c ajv-formats --strict=false 2>&1
        Remove-Item $targetOnly -Force -ErrorAction SilentlyContinue
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Schema validation reported issues:`n$proc"
        } else {
            Write-Verbose "Schema validation: PASS"
        }
    }
}

[pscustomobject]@{
    tenantId         = $tenantId
    output           = (Resolve-Path $OutputPath).Path
    profilesApplied  = $profiles
    overridesPresent = $overridesPresent
    layers           = @($layers | ForEach-Object { $_.name })
}
