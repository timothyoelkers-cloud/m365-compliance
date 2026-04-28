<#
.SYNOPSIS
    Multi-framework executive summary — one cover document for stakeholders
    spanning every framework the tenant is bound by. Aggregates the same
    coverage analysis New-FrameworkReport.ps1 produces but presents it as a
    single board-room ready snapshot.

.DESCRIPTION
    Output sections:
      - Status snapshot (one row per framework: covered / drift / partial /
        uncovered / total / score)
      - Combined headline (deduped across frameworks)
      - Top findings to address (sorted by severity, then by how many
        frameworks they affect)
      - Drift register (controls deployed but failing)
      - Uncovered register (no deployed primary)
      - Recommended next actions

    Score per framework = (covered + 0.5 * partial-only) / total. Reported as
    a percentage with one decimal. Drift counts hard against the score (status
    is reported separately). Drift > 0 should always be the top priority
    regardless of overall score.

.PARAMETER FindingsPath
    Findings JSON produced by Compare-TenantState.ps1.

.PARAMETER Frameworks
    Subset of frameworks to include. Defaults to all four built-in frameworks.

.PARAMETER ControlMapPath
    Path to skills/mapping/control-map/map.csv. Defaults to repo-relative.

.PARAMETER ResolvedBaselinePath
    Optional resolved baseline — sharpens the deployed-control check.

.PARAMETER OutputPath
    Markdown file path.

.PARAMETER TenantDisplayName
    Optional override for the cover header.

.PARAMETER TopFindings
    How many top findings to list in the prioritised section. Default 10.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$FindingsPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string[]]$Frameworks = @('cis-m365','dora','nis2','hipaa'),
    [string]$ControlMapPath,
    [string]$ResolvedBaselinePath,
    [string]$TenantDisplayName,
    [int]$TopFindings = 10
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not $ControlMapPath) {
    $here = Split-Path -Parent $PSCommandPath
    $repoRoot = Resolve-Path (Join-Path $here '..\..') -ErrorAction SilentlyContinue
    if ($repoRoot) {
        $ControlMapPath = Join-Path $repoRoot.Path 'skills/mapping/control-map/map.csv'
    }
}
if (-not (Test-Path $ControlMapPath)) { throw "Control map not found: $ControlMapPath" }
if (-not (Test-Path $FindingsPath))   { throw "Findings file not found: $FindingsPath" }

$findings = Get-Content -Raw -LiteralPath $FindingsPath | ConvertFrom-Json -Depth 30 -AsHashtable
$mapRows  = Import-Csv -LiteralPath $ControlMapPath

# Per-framework coverage analysis (mirrors New-FrameworkReport)
$frameworkLabel = @{
    'cis-m365' = 'CIS Microsoft 365 v6.0.1'
    'dora'     = 'DORA — Regulation (EU) 2022/2554'
    'nis2'     = 'NIS 2 Directive — Directive (EU) 2022/2555'
    'hipaa'    = 'HIPAA — 45 CFR 164'
}
$severityRank = @{ critical = 0; high = 1; medium = 2; low = 3; info = 4 }

function Get-FrameworkCoverage {
    param([string]$Framework, $MapRows, $Findings)
    $rows = @($MapRows | Where-Object framework -eq $Framework)
    if ($rows.Count -eq 0) { return $null }

    $byControl = @{}
    foreach ($f in $Findings.findings) {
        foreach ($fr in $f.frameworkRefs) {
            if ($fr.framework -eq $Framework) {
                if (-not $byControl.ContainsKey($f.baselineControlId)) {
                    $byControl[$f.baselineControlId] = [System.Collections.Generic.List[hashtable]]::new()
                }
                [void]$byControl[$f.baselineControlId].Add($f)
                break
            }
        }
    }

    $refGroups = $rows | Group-Object framework_ref
    $coverage = foreach ($g in $refGroups) {
        $primary = @($g.Group | Where-Object coverage_type -eq 'primary')
        $partial = @($g.Group | Where-Object coverage_type -eq 'partial')
        $failing = @()
        foreach ($r in $g.Group) {
            if ($byControl.ContainsKey($r.control_id)) {
                $bad = @($byControl[$r.control_id] | Where-Object actionTaken -ne 'unchanged')
                if ($bad.Count -gt 0) { $failing += $r.control_id }
            }
        }
        $status = 'covered'
        if ($primary.Count -eq 0 -and $partial.Count -eq 0) { $status = 'uncovered' }
        elseif ($primary.Count -eq 0)                       { $status = 'partial-only' }
        if ($failing.Count -gt 0)                           { $status = 'drift' }
        [pscustomobject]@{ ref = $g.Name; status = $status; failing = $failing }
    }

    $total       = $coverage.Count
    $covered     = @($coverage | Where-Object status -eq 'covered').Count
    $drift       = @($coverage | Where-Object status -eq 'drift').Count
    $partialOnly = @($coverage | Where-Object status -eq 'partial-only').Count
    $uncovered   = @($coverage | Where-Object status -eq 'uncovered').Count
    $score       = if ($total -gt 0) { [math]::Round(((100 * $covered) + (50 * $partialOnly)) / $total, 1) } else { 0 }

    [pscustomobject]@{
        framework    = $Framework
        label        = $frameworkLabel[$Framework]
        total        = $total
        covered      = $covered
        drift        = $drift
        partialOnly  = $partialOnly
        uncovered    = $uncovered
        score        = $score
        coverage     = $coverage
    }
}

$perFramework = foreach ($f in $Frameworks) {
    $r = Get-FrameworkCoverage -Framework $f -MapRows $mapRows -Findings $findings
    if ($r) { $r }
}

# Combined headline (sum across frameworks; double-counts shared refs which is
# fine for a snapshot — the per-framework rows are the precise view)
$totalAll      = ($perFramework | Measure-Object total       -Sum).Sum
$coveredAll    = ($perFramework | Measure-Object covered     -Sum).Sum
$driftAll      = ($perFramework | Measure-Object drift       -Sum).Sum
$partialAll    = ($perFramework | Measure-Object partialOnly -Sum).Sum
$uncoveredAll  = ($perFramework | Measure-Object uncovered   -Sum).Sum
$scoreAll      = if ($totalAll -gt 0) { [math]::Round(((100 * $coveredAll) + (50 * $partialAll)) / $totalAll, 1) } else { 0 }

# Top findings — sorted by severity, then by frameworks affected count
$topFindings = $findings.findings | ForEach-Object {
    $matchingFrameworks = @($_.frameworkRefs | Where-Object { $Frameworks -contains $_.framework })
    [pscustomobject]@{
        finding   = $_
        rank      = $severityRank[$_.severity]
        framRefs  = $matchingFrameworks
        framCount = $matchingFrameworks.Count
    }
} | Where-Object framCount -gt 0 | Sort-Object rank, @{ Expression = { -$_.framCount } }, @{ Expression = { $_.finding.id } } | Select-Object -First $TopFindings

# Drift register — distinct (framework, ref) pairs with at least one failing control
$driftReg = foreach ($f in $perFramework) {
    foreach ($c in ($f.coverage | Where-Object status -eq 'drift')) {
        [pscustomobject]@{
            framework = $f.framework
            label     = $f.label
            ref       = $c.ref
            failing   = $c.failing
        }
    }
}

# Uncovered register
$uncoveredReg = foreach ($f in $perFramework) {
    foreach ($c in ($f.coverage | Where-Object status -eq 'uncovered')) {
        [pscustomobject]@{
            framework = $f.framework
            label     = $f.label
            ref       = $c.ref
        }
    }
}

# ---------------------------------------------------------------------------
# Render
# ---------------------------------------------------------------------------
$tenantDisp = if ($TenantDisplayName) { $TenantDisplayName } else { $findings.tenantId }
$sb = [System.Text.StringBuilder]::new()

[void]$sb.AppendLine("# Compliance Executive Summary")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("**Tenant:** $tenantDisp")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("**Run id:** $($findings.runId)  ")
[void]$sb.AppendLine("**Generated:** _deterministic-fixture_  ")
[void]$sb.AppendLine("**Findings file:** $((Resolve-Path $FindingsPath).Path | Split-Path -Leaf)")
[void]$sb.AppendLine("")

[void]$sb.AppendLine("## Status snapshot")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("Score = (covered + 0.5 × partial-only) / total. Drift status is reported separately — drift > 0 is always priority-1 regardless of score.")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("| Framework | Covered | Drift | Partial-only | Uncovered | Total | Score |")
[void]$sb.AppendLine("|---|---|---|---|---|---|---|")
foreach ($f in $perFramework) {
    [void]$sb.AppendLine("| $($f.label) | $($f.covered) | $($f.drift) | $($f.partialOnly) | $($f.uncovered) | $($f.total) | $($f.score)% |")
}
[void]$sb.AppendLine("| **All frameworks** | **$coveredAll** | **$driftAll** | **$partialAll** | **$uncoveredAll** | **$totalAll** | **$scoreAll%** |")
[void]$sb.AppendLine("")

# Top findings
[void]$sb.AppendLine("## Top $TopFindings findings")
[void]$sb.AppendLine("")
if ($topFindings.Count -eq 0) {
    [void]$sb.AppendLine("_No findings tagged with the requested frameworks._")
} else {
    [void]$sb.AppendLine("| # | Severity | Finding | Workload | Affects | Current → Desired |")
    [void]$sb.AppendLine("|---|---|---|---|---|---|")
    $i = 1
    foreach ($t in $topFindings) {
        $f = $t.finding
        $affects = ($t.framRefs | ForEach-Object { "$($_.framework):$($_.ref)" }) -join '<br>'
        $delta   = "``$($f.currentValue)`` → ``$($f.desiredValue)``"
        [void]$sb.AppendLine("| $i | $($f.severity) | $($f.id) | $($f.workload) | $affects | $delta |")
        $i++
    }
}
[void]$sb.AppendLine("")

# Drift register
[void]$sb.AppendLine("## Drift register — controls deployed but failing")
[void]$sb.AppendLine("")
if ($driftReg.Count -eq 0) {
    [void]$sb.AppendLine("_No drift detected. Tenant configuration matches the deployed baseline for every mapped framework reference._")
} else {
    [void]$sb.AppendLine("| Framework | Reference | Failing controls |")
    [void]$sb.AppendLine("|---|---|---|")
    foreach ($d in ($driftReg | Sort-Object framework, ref)) {
        $fc = ($d.failing -join '<br>')
        [void]$sb.AppendLine("| $($d.label) | $($d.ref) | $fc |")
    }
}
[void]$sb.AppendLine("")

# Uncovered register
[void]$sb.AppendLine("## Uncovered register — no deployed control maps to this requirement")
[void]$sb.AppendLine("")
if ($uncoveredReg.Count -eq 0) {
    [void]$sb.AppendLine("_Every mapped framework reference has at least one control in scope (primary or partial)._")
} else {
    [void]$sb.AppendLine("| Framework | Reference |")
    [void]$sb.AppendLine("|---|---|")
    foreach ($u in ($uncoveredReg | Sort-Object framework, ref)) {
        [void]$sb.AppendLine("| $($u.label) | $($u.ref) |")
    }
}
[void]$sb.AppendLine("")

# Recommended next actions
[void]$sb.AppendLine("## Recommended next actions")
[void]$sb.AppendLine("")
$actions = @()
if ($driftAll -gt 0) {
    $actions += "**Address drift first.** $driftAll framework reference$(if ($driftAll -gt 1) {'s'} else {''}) currently fail their deployed controls — the tenant has the right intent but the wrong reality. Drift is the cheapest gap to close."
}
if ($uncoveredAll -gt 0) {
    $actions += "**Close uncovered gaps.** $uncoveredAll reference$(if ($uncoveredAll -gt 1) {'s'} else {''}) have no mapped control in scope. Either extend the baseline or accept the deviation in writing."
}
if ($partialAll -gt 0) {
    $actions += "**Promote partial coverage to primary** where a stronger control exists. $partialAll reference$(if ($partialAll -gt 1) {'s'} else {''}) currently rely on partial controls only."
}
if ($actions.Count -eq 0) {
    $actions += "**Maintain posture.** No drift, no uncovered, no partial-only — the deployed baseline is meeting every mapped framework requirement. Schedule the next review and re-run quarterly."
}
foreach ($a in $actions) { [void]$sb.AppendLine("- $a") }
[void]$sb.AppendLine("")

[void]$sb.AppendLine("---")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("_Generated by ``scripts/report/New-ExecutiveSummary.ps1``. Per-framework detail in the framework-scoped reports. The mapped scope is limited to controls in ``skills/mapping/control-map/map.csv`` — manual review still required for requirements outside the map._")

$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$sb.ToString() | Out-File -LiteralPath $OutputPath -Encoding utf8

[pscustomobject]@{
    output            = (Resolve-Path $OutputPath).Path
    frameworks        = @($perFramework.framework)
    overallScore      = $scoreAll
    totalRefs         = $totalAll
    drift             = $driftAll
    uncovered         = $uncoveredAll
    topFindingsCount  = $topFindings.Count
}
