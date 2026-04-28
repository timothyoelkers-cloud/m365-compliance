<#
.SYNOPSIS
    Generate a framework-scoped audit-prep report from a tenant's findings, the
    control map, and (optionally) the resolved baseline. Produces markdown by
    default — the format auditors actually ask for.

.DESCRIPTION
    Walks the control-map CSV to enumerate framework requirements, joins to
    the findings produced by Compare-TenantState.ps1, and emits a markdown
    document with:

        - Cover (tenant id, framework name, run id, baseline gitsha, timestamp)
        - Coverage matrix — for each framework reference, how many controls map
          to it, how many are deployed, and whether any are failing
        - Findings table grouped by severity, scoped to the framework
        - Gaps — framework refs with no deployed primary control, or only
          contributes-to coverage
        - Evidence index — which scan artefacts back which framework refs

    The "framework universe" used for coverage analysis is the set of distinct
    framework_ref values appearing in skills/mapping/control-map/map.csv with
    framework=<requested>. It is NOT a full enumeration of regulatory text —
    only what's been mapped. Unmapped requirements are out of scope for
    automated reporting and surface in the manual gap analysis.

.PARAMETER Framework
    cis-m365 | dora | nis2 | hipaa

.PARAMETER FindingsPath
    Path to a findings.json produced by Compare-TenantState.ps1.

.PARAMETER ControlMapPath
    Path to skills/mapping/control-map/map.csv. Defaults to repo-relative.

.PARAMETER ResolvedBaselinePath
    Optional path to the resolved baseline JSON (Resolve-Baseline.ps1 output).
    Used to determine which controls are "deployed" (present in baseline).
    If omitted, every mapped control is assumed deployed.

.PARAMETER OutputPath
    Markdown file path.

.PARAMETER TenantDisplayName
    Optional override for the cover header.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('cis-m365','dora','nis2','hipaa')][string]$Framework,
    [Parameter(Mandatory)][string]$FindingsPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$ControlMapPath,
    [string]$ResolvedBaselinePath,
    [string]$TenantDisplayName
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not $ControlMapPath) {
    $here     = Split-Path -Parent $PSCommandPath
    $repoRoot = Resolve-Path (Join-Path $here '..\..') -ErrorAction SilentlyContinue
    if ($repoRoot) {
        $ControlMapPath = Join-Path $repoRoot.Path 'skills/mapping/control-map/map.csv'
    }
}
if (-not (Test-Path $ControlMapPath)) { throw "Control map not found: $ControlMapPath" }
if (-not (Test-Path $FindingsPath))   { throw "Findings file not found: $FindingsPath" }

$findings = Get-Content -Raw -LiteralPath $FindingsPath | ConvertFrom-Json -Depth 30 -AsHashtable
$mapRows  = Import-Csv -LiteralPath $ControlMapPath

# Resolved baseline (optional)
$deployedControlIds = $null
if ($ResolvedBaselinePath -and (Test-Path $ResolvedBaselinePath)) {
    $resolved = Get-Content -Raw -LiteralPath $ResolvedBaselinePath | ConvertFrom-Json -Depth 30 -AsHashtable
    $deployedControlIds = [System.Collections.Generic.HashSet[string]]::new()
    # Heuristic: a control is "deployed" if any of its referenced fields appear
    # in the resolved baseline.target tree. We keep this lightweight — full
    # tree-walk is in the diff engine, not here.
    function _Walk($obj, [System.Collections.Generic.HashSet[string]]$paths, [string]$prefix='') {
        if ($null -eq $obj) { return }
        if ($obj -is [System.Collections.IDictionary]) {
            foreach ($k in $obj.Keys) { _Walk -obj $obj[$k] -paths $paths -prefix "$prefix.$k" }
        } elseif ($obj -is [System.Collections.IList] -and $obj -isnot [string]) {
            foreach ($i in $obj) { _Walk -obj $i -paths $paths -prefix $prefix }
        } else {
            [void]$paths.Add($prefix)
        }
    }
    $allPaths = [System.Collections.Generic.HashSet[string]]::new()
    _Walk -obj $resolved.target -paths $allPaths
    # We treat presence at any depth as "deployed". Real deployment check
    # belongs to the diff engine; this is the cheap "did the baseline ever
    # mention this control" signal.
    foreach ($row in $mapRows) {
        $hit = $false
        foreach ($p in $allPaths) { if ($p -match [regex]::Escape($row.control_id.Replace('m365.','').Split('.')[0])) { $hit = $true; break } }
        if ($hit) { [void]$deployedControlIds.Add($row.control_id) }
    }
}

# Filter to requested framework
$frameworkRows = @($mapRows | Where-Object { $_.framework -eq $Framework })
if ($frameworkRows.Count -eq 0) {
    throw "No mapping rows in $ControlMapPath have framework='$Framework'"
}

# Group rows by framework_ref — that's the requirement universe
$refGroups = $frameworkRows | Group-Object framework_ref

# Filter findings to those tagged with the requested framework
$frameworkFindings = @($findings.findings | Where-Object {
    foreach ($fw in $_.frameworkRefs) {
        if ($fw.framework -eq $Framework) { return $true }
    }
    return $false
})

# Index findings by control id (for joining to map rows)
$findingsByControl = @{}
foreach ($f in $frameworkFindings) {
    if (-not $findingsByControl.ContainsKey($f.baselineControlId)) {
        $findingsByControl[$f.baselineControlId] = [System.Collections.Generic.List[hashtable]]::new()
    }
    [void]$findingsByControl[$f.baselineControlId].Add($f)
}

# Compute coverage per framework_ref
$coverage = foreach ($g in $refGroups) {
    $ref       = $g.Name
    $rows      = $g.Group
    $primary   = @($rows | Where-Object coverage_type -eq 'primary')
    $partial   = @($rows | Where-Object coverage_type -eq 'partial')
    $contrib   = @($rows | Where-Object coverage_type -eq 'contributes-to')

    $primaryDeployed = if ($null -ne $deployedControlIds) {
        @($primary | Where-Object { $deployedControlIds.Contains($_.control_id) })
    } else { $primary }
    $partialDeployed = if ($null -ne $deployedControlIds) {
        @($partial | Where-Object { $deployedControlIds.Contains($_.control_id) })
    } else { $partial }

    $failing = @()
    foreach ($r in $rows) {
        if ($findingsByControl.ContainsKey($r.control_id)) {
            $bad = @($findingsByControl[$r.control_id] | Where-Object actionTaken -ne 'unchanged')
            if ($bad.Count -gt 0) { $failing += $r.control_id }
        }
    }

    $status = 'covered'
    if ($primaryDeployed.Count -eq 0 -and $partialDeployed.Count -eq 0) { $status = 'uncovered' }
    elseif ($primaryDeployed.Count -eq 0)                                { $status = 'partial-only' }
    if ($failing.Count -gt 0)                                            { $status = 'drift' }

    [pscustomobject]@{
        ref               = $ref
        status            = $status
        primaryControls   = @($primaryDeployed.control_id)
        partialControls   = @($partialDeployed.control_id)
        contributesTo     = @($contrib.control_id)
        failingControls   = $failing
    }
}

# Build evidence index — distinct evidence artefacts mentioned by mapped findings
$evidence = @($frameworkRows | Group-Object evidence_artefact | ForEach-Object {
    [pscustomobject]@{
        artefact = $_.Name
        refs     = @($_.Group | ForEach-Object framework_ref | Select-Object -Unique)
    }
})

# ---------------------------------------------------------------------------
# Render markdown
# ---------------------------------------------------------------------------
$frameworkLabel = switch ($Framework) {
    'cis-m365' { 'CIS Microsoft 365 v6.0.1' }
    'dora'     { 'DORA — Regulation (EU) 2022/2554' }
    'nis2'     { 'NIS 2 Directive — Directive (EU) 2022/2555' }
    'hipaa'    { 'HIPAA — 45 CFR 164' }
}

$tenantDisp = if ($TenantDisplayName) { $TenantDisplayName } else { $findings.tenantId }

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# $frameworkLabel — Audit-Prep Report")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("**Tenant:** $tenantDisp")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("**Run id:** $($findings.runId)  ")
[void]$sb.AppendLine("**Generated:** $((Get-Date).ToUniversalTime().ToString('o'))  ")
[void]$sb.AppendLine("**Findings file:** $((Resolve-Path $FindingsPath).Path | Split-Path -Leaf)")
[void]$sb.AppendLine("")

# Headline numbers
$total       = $coverage.Count
$covered     = @($coverage | Where-Object status -eq 'covered').Count
$drift       = @($coverage | Where-Object status -eq 'drift').Count
$partialOnly = @($coverage | Where-Object status -eq 'partial-only').Count
$uncovered   = @($coverage | Where-Object status -eq 'uncovered').Count

[void]$sb.AppendLine("## Headline")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Status | Count |")
[void]$sb.AppendLine("|---|---|")
[void]$sb.AppendLine("| Covered (primary deployed, no drift) | $covered |")
[void]$sb.AppendLine("| Drift (control deployed but failing) | $drift |")
[void]$sb.AppendLine("| Partial-only (no primary control deployed) | $partialOnly |")
[void]$sb.AppendLine("| Uncovered (no mapped control deployed) | $uncovered |")
[void]$sb.AppendLine("| **Total mapped framework references** | **$total** |")
[void]$sb.AppendLine("")

# Coverage matrix
[void]$sb.AppendLine("## Coverage matrix")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Framework reference | Status | Primary controls | Partial controls | Failing |")
[void]$sb.AppendLine("|---|---|---|---|---|")
foreach ($c in ($coverage | Sort-Object @{Expression={ @{covered=0;drift=1;'partial-only'=2;uncovered=3}[$_.status] }}, ref)) {
    $primary = if ($c.primaryControls.Count -eq 0) { '—' } else { ($c.primaryControls -join '<br>') }
    $partial = if ($c.partialControls.Count -eq 0) { '—' } else { ($c.partialControls -join '<br>') }
    $fail    = if ($c.failingControls.Count -eq 0) { '—' } else { ($c.failingControls -join '<br>') }
    [void]$sb.AppendLine("| $($c.ref) | $($c.status) | $primary | $partial | $fail |")
}
[void]$sb.AppendLine("")

# Findings — grouped by severity
[void]$sb.AppendLine("## Findings scoped to $frameworkLabel")
[void]$sb.AppendLine("")
if ($frameworkFindings.Count -eq 0) {
    [void]$sb.AppendLine("_No findings tagged with this framework. Either the tenant matches the deployed baseline (good) or the diff-rules don't yet cover the framework's controls (gap)._")
    [void]$sb.AppendLine("")
} else {
    foreach ($severity in 'critical','high','medium','low','info') {
        $bucket = @($frameworkFindings | Where-Object severity -eq $severity)
        if ($bucket.Count -eq 0) { continue }
        [void]$sb.AppendLine("### $severity")
        [void]$sb.AppendLine("")
        foreach ($f in $bucket) {
            $thisFrameworkRef = ($f.frameworkRefs | Where-Object framework -eq $Framework | Select-Object -First 1).ref
            [void]$sb.AppendLine("- **$($f.id)** ($($f.workload))  ")
            [void]$sb.AppendLine("  Maps to: ``$thisFrameworkRef``  ")
            [void]$sb.AppendLine("  Current: ``$($f.currentValue)`` — Desired: ``$($f.desiredValue)``  ")
            [void]$sb.AppendLine("  Action: $($f.actionTaken) — Evidence: ``$($f.evidenceArtefact)``")
            [void]$sb.AppendLine("")
        }
    }
}

# Evidence index
[void]$sb.AppendLine("## Evidence index")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Evidence artefact | Backing framework references |")
[void]$sb.AppendLine("|---|---|")
foreach ($e in ($evidence | Sort-Object artefact)) {
    [void]$sb.AppendLine("| ``$($e.artefact)`` | $(($e.refs | Sort-Object) -join '<br>') |")
}
[void]$sb.AppendLine("")

# Gaps
[void]$sb.AppendLine("## Gaps")
[void]$sb.AppendLine("")
$gapRows = @($coverage | Where-Object status -in 'uncovered','partial-only','drift' | Sort-Object @{Expression={ @{drift=0;'partial-only'=1;uncovered=2}[$_.status] }}, ref)
if ($gapRows.Count -eq 0) {
    [void]$sb.AppendLine("_No gaps for the mapped scope. Note: this scope is limited to controls present in skills/mapping/control-map/map.csv. Manual review is still required for framework requirements outside this map._")
    [void]$sb.AppendLine("")
} else {
    [void]$sb.AppendLine("| Framework reference | Status | Action |")
    [void]$sb.AppendLine("|---|---|---|")
    foreach ($g in $gapRows) {
        $action = switch ($g.status) {
            'drift'        { 'Investigate failing controls; remediate to baseline' }
            'partial-only' { 'Add a primary control or accept defence-in-depth posture' }
            'uncovered'    { 'No deployed control maps to this requirement — review baseline scope' }
        }
        [void]$sb.AppendLine("| $($g.ref) | $($g.status) | $action |")
    }
    [void]$sb.AppendLine("")
}

[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("_Generated by ``scripts/report/New-FrameworkReport.ps1``. The mapped scope is limited to controls present in ``skills/mapping/control-map/map.csv``. Requirements outside the map are not assessed automatically — see the framework skill for manual review guidance._")

$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$sb.ToString() | Out-File -LiteralPath $OutputPath -Encoding utf8

[pscustomobject]@{
    framework        = $Framework
    output           = (Resolve-Path $OutputPath).Path
    refsTotal        = $total
    refsCovered      = $covered
    refsDrift        = $drift
    refsPartialOnly  = $partialOnly
    refsUncovered    = $uncovered
    findings         = $frameworkFindings.Count
}
