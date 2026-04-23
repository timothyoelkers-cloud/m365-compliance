<#
.SYNOPSIS
    Compare a resolved tenant baseline against a scan bundle and emit a findings
    array conforming to baselines/schema/evidence-bundle.schema.json (findings block).

.DESCRIPTION
    Reads:
      - ResolvedBaseline: output of Resolve-Baseline.ps1
      - Bundle: a scan bundle directory (containing manifest.json + per-workload JSON)
      - Rules: a YAML rule set (default: scripts/common/diff-rules.yaml)

    For each rule, extracts a value from the baseline by dot-path, extracts a value
    from the appropriate scan JSON by dot-path, applies the comparison mode, and
    emits a finding entry when the tenant state does not meet the baseline.

    Supported dot-path syntax:
      - Simple:         entra.authorization_policy.guest_user_role_id
      - Typed object:   policies[displayName=CIS L1 — Block legacy authentication].state
      - Named list id:  entra.conditional_access_policies[id=cis-l1-ca-002-mfa-all-users].state
      - Wildcard list:  dkimSigningConfig[*].Enabled   (returns array of values)

    Supported compareMode values:
      equals, notEquals, greaterOrEqual, lessOrEqual, contains, notContains,
      presentAndNotNull, presentAndNotEmpty, allTrue, invertedEquals,
      equalsZeroWhenBaseline, tenantSettingDisabled

    Rules whose baseline path resolves to null (i.e. the baseline doesn't declare
    an expectation) are skipped — findings only arise where the baseline asks for
    something and the tenant state doesn't meet it.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResolvedBaselinePath,
    [Parameter(Mandatory)][string]$BundlePath,
    [string]$RulesPath,
    [string]$OutputPath,
    [switch]$AppendToManifest
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not $RulesPath) {
    $RulesPath = Join-Path (Split-Path -Parent $PSCommandPath) 'diff-rules.yaml'
}
if (-not (Test-Path $RulesPath))          { throw "Rules file not found: $RulesPath" }
if (-not (Test-Path $ResolvedBaselinePath)){ throw "Resolved baseline not found: $ResolvedBaselinePath" }
if (-not (Test-Path $BundlePath))         { throw "Bundle path not found: $BundlePath" }

if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Install-Module powershell-yaml -Scope CurrentUser -Force -AcceptLicense | Out-Null
}
Import-Module powershell-yaml -ErrorAction Stop

$baseline = Get-Content -Raw -LiteralPath $ResolvedBaselinePath | ConvertFrom-Json -Depth 30 -AsHashtable
$rules    = ConvertFrom-Yaml -Yaml (Get-Content -Raw -LiteralPath $RulesPath)
$manifest = Get-Content -Raw -LiteralPath (Join-Path $BundlePath 'manifest.json') | ConvertFrom-Json -Depth 30 -AsHashtable

$workloadData = @{}
foreach ($art in $manifest.artefacts) {
    $path = Join-Path $BundlePath $art.path
    if (Test-Path $path) {
        $workloadData[$art.workload] = Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -Depth 30 -AsHashtable
    } else {
        Write-Warning "Artefact missing: $path (workload=$($art.workload))"
    }
}

function Get-ByPath {
    param($Root, [string]$Path)
    if ($null -eq $Root -or [string]::IsNullOrEmpty($Path)) { return $null }

    $segments = @()
    $buffer = ''
    $i = 0
    while ($i -lt $Path.Length) {
        $ch = $Path[$i]
        if ($ch -eq '.') {
            if ($buffer) { $segments += $buffer; $buffer = '' }
            $i++; continue
        }
        if ($ch -eq '[') {
            if ($buffer) { $segments += $buffer; $buffer = '' }
            $end = $Path.IndexOf(']', $i)
            if ($end -lt 0) { throw "Unclosed '[' in path: $Path" }
            $segments += $Path.Substring($i, $end - $i + 1)
            $i = $end + 1; continue
        }
        $buffer += $ch; $i++
    }
    if ($buffer) { $segments += $buffer }

    $current = $Root
    for ($si = 0; $si -lt $segments.Count; $si++) {
        $seg = $segments[$si]
        if ($null -eq $current) { return $null }

        if ($seg -match '^\[\*\]$') {
            if (-not ($current -is [System.Collections.IList])) { return $null }
            if ($si -eq $segments.Count - 1) { return $current }
            $remainder = ($segments[($si+1)..($segments.Count-1)]) -join '.'
            $out = @()
            foreach ($item in $current) {
                $out += , (Get-ByPath -Root $item -Path $remainder)
            }
            return ,$out
        }
        if ($seg -match '^\[(?<k>[^=]+)=(?<v>.+)\]$') {
            $k = $Matches.k; $v = $Matches.v
            if (-not ($current -is [System.Collections.IList])) { return $null }
            $current = $current | Where-Object {
                ($_ -is [System.Collections.IDictionary]) -and $_.Contains($k) -and [string]$_[$k] -eq $v
            } | Select-Object -First 1
            continue
        }
        if ($current -is [System.Collections.IDictionary]) {
            if ($current.Contains($seg)) { $current = $current[$seg] } else { return $null }
        } elseif ($current -is [pscustomobject]) {
            if ($current.PSObject.Properties.Name -contains $seg) { $current = $current.$seg } else { return $null }
        } else {
            return $null
        }
    }
    return $current
}

function Test-Compare {
    param($Expected, $Actual, [string]$Mode)
    switch ($Mode) {
        'equals'             { return ($Actual -eq $Expected) }
        'notEquals'          { return ($Actual -ne $Expected) }
        'greaterOrEqual'     { return ($null -ne $Actual) -and ($Actual -ge $Expected) }
        'lessOrEqual'        { return ($null -ne $Actual) -and ($Actual -le $Expected) }
        'contains'           { return ($Actual -is [System.Collections.IList]) -and ($Actual -contains $Expected) }
        'notContains'        { return ($Actual -is [System.Collections.IList]) -and (-not ($Actual -contains $Expected)) }
        'presentAndNotNull'  { return ($null -ne $Actual) }
        'presentAndNotEmpty' { return ($null -ne $Actual) -and (($Actual | Measure-Object).Count -gt 0) }
        'allTrue'            { return ($Actual -is [System.Collections.IList]) -and (@($Actual | Where-Object { $_ -ne $true }).Count -eq 0) }
        'invertedEquals'     { return ($Actual -eq (-not $Expected)) }
        'equalsZeroWhenBaseline' {
            if ($Expected -eq $true) { return ($Actual -eq 0) } else { return $true }
        }
        'tenantSettingDisabled' {
            if ($Expected -eq 'disabled') { return ($null -eq $Actual -or $Actual -eq $false) }
            return $true
        }
        default { throw "Unknown compareMode: $Mode" }
    }
}

$findings = [System.Collections.Generic.List[hashtable]]::new()

foreach ($rule in $rules.rules) {
    $expected = Get-ByPath -Root $baseline.target -Path $rule.baselinePath
    if ($null -eq $expected) { continue }

    $scan = $workloadData[$rule.scanWorkload]
    if ($null -eq $scan) {
        [void]$findings.Add(@{
            id = $rule.id
            severity = 'info'
            workload = $rule.workload
            baselineControlId = $rule.baselineControlId
            cisRef = $rule.cisRef
            frameworkRefs = $rule.frameworks
            currentValue = $null
            desiredValue = $expected
            actionTaken = 'deferred'
            evidenceArtefact = "(no $($rule.scanWorkload) artefact in bundle)"
        })
        continue
    }

    $actual = Get-ByPath -Root $scan -Path $rule.scanPath
    $ok = Test-Compare -Expected $expected -Actual $actual -Mode $rule.compareMode

    if (-not $ok) {
        [void]$findings.Add(@{
            id = $rule.id
            severity = $rule.severity
            workload = $rule.workload
            baselineControlId = $rule.baselineControlId
            cisRef = $rule.cisRef
            frameworkRefs = $rule.frameworks
            currentValue = $actual
            desiredValue = $expected
            actionTaken = 'reported'
            evidenceArtefact = "$($rule.scanWorkload).json"
        })
    }
}

$severityOrder = @{ critical = 0; high = 1; medium = 2; low = 3; info = 4 }
$sorted = $findings | Sort-Object `
    @{ Expression = { $severityOrder[$_.severity] } }, `
    @{ Expression = { $_.workload } }, `
    @{ Expression = { $_.id } }

$result = @{
    generatedAt       = (Get-Date).ToUniversalTime().ToString('o')
    tenantId          = $manifest.tenant.tenantId
    runId             = $manifest.run.runId
    rulesFile         = (Resolve-Path $RulesPath).Path
    resolvedBaseline  = (Resolve-Path $ResolvedBaselinePath).Path
    summary = @{
        total    = $sorted.Count
        critical = @($sorted | Where-Object severity -eq 'critical').Count
        high     = @($sorted | Where-Object severity -eq 'high').Count
        medium   = @($sorted | Where-Object severity -eq 'medium').Count
        low      = @($sorted | Where-Object severity -eq 'low').Count
        info     = @($sorted | Where-Object severity -eq 'info').Count
    }
    findings = $sorted
}

if (-not $OutputPath) {
    $OutputPath = Join-Path $BundlePath 'findings.json'
}
$result | ConvertTo-Json -Depth 30 | Out-File -LiteralPath $OutputPath -Encoding utf8

if ($AppendToManifest) {
    $manifestPath = Join-Path $BundlePath 'manifest.json'
    $manifest.findings = $sorted
    $manifest.integrity.manifestSha256 = ''
    $manifest.integrity.signature = $null
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($manifest | ConvertTo-Json -Depth 30)))
    $manifestSha = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    $manifest.integrity.manifestSha256 = $manifestSha
    $manifest | ConvertTo-Json -Depth 30 | Out-File -LiteralPath $manifestPath -Encoding utf8
}

[pscustomobject]@{
    tenantId = $result.tenantId
    output   = (Resolve-Path $OutputPath).Path
    summary  = $result.summary
}
