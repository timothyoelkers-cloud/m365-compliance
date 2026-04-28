<#
.SYNOPSIS
    Orchestrate end-to-end baseline reconciliation against a single tenant.
    Resolves the layered baseline, runs the diff engine, dispatches each
    workload's apply primitive in plan/apply mode, aggregates everything into
    a consolidated tenant-plan + (optional) evidence bundle.

    Modes:
        audit        Read scan bundle + resolve baseline + run diff engine.
                     Emits findings.json + per-framework reports + executive
                     summary. NO writes. NO per-workload plans.
        plan         (default) Audit, plus runs each workload apply primitive
                     in plan mode. Emits a consolidated tenant-plan.json that
                     concatenates every workload's plan with a single
                     blockedBy and approval-required block. NO writes.
        apply-pilot  Plan, then apply pilot-scoped changes via each workload
                     apply primitive's apply mode. Requires -ApprovalRef.
                     Refuses if any workload plan has blockedBy entries.
        apply-broad  Same as apply-pilot but with broader assignment scope
                     (passed to workload primitives that respect rollout rings).
        rollback     Plan-then-apply against an alternate (prior) baseline.

    Pre-flight gates (audit mode performs the read-only ones; apply modes add
    the destructive-change ones):
        1. Tenant identity consistency: scan tenantId, baseline tenant.id, and
           -TenantId all match.
        2. Break-glass posture: baseline declares a non-empty break-glass
           group_id and member_count_expected.
        3. Licence sufficiency (best-effort): warn if baseline references P2
           features but tenant.licensing.tier doesn't include P2.
        4. Apply-only: every workload plan has blockedBy.Count == 0.

    Forward-compatible workload dispatch: edit $script:WorkloadApplyScripts
    when a new Set-<Workload>.ps1 is added; the orchestrator runs every entry
    that exists.

.PARAMETER TenantConfigPath
    Path to a tenant.yaml.

.PARAMETER ScanBundlePath
    Path to a scan bundle directory (manifest.json + per-workload JSON).
    The orchestrator does not run scans — that's Invoke-TenantScan.ps1's job.

.PARAMETER OutputDir
    Directory under which all outputs land. Created if missing.

.PARAMETER Mode
    audit | plan | apply-pilot | apply-broad | rollback   (default: plan)

.PARAMETER ApprovalRef
    Required for any apply-* / rollback. Recorded in evidence.

.PARAMETER BaselinesRoot
    Optional override for the baselines directory. Defaults to repo-relative.

.PARAMETER SkipReports
    Skip framework reports + executive summary generation (faster). Plan and
    findings still produced.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TenantConfigPath,
    [Parameter(Mandatory)][string]$ScanBundlePath,
    [Parameter(Mandatory)][string]$OutputDir,
    [ValidateSet('audit','plan','apply-pilot','apply-broad','rollback')][string]$Mode = 'plan',
    [string]$ApprovalRef,
    [string]$BaselinesRoot,
    [switch]$SkipReports
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

# ----- Path resolution --------------------------------------------------
$here     = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path (Join-Path $here '..\..')).Path
if (-not $BaselinesRoot) { $BaselinesRoot = Join-Path $repoRoot 'baselines' }
$Resolve   = Join-Path $repoRoot 'scripts/common/Resolve-Baseline.ps1'
$Compare   = Join-Path $repoRoot 'scripts/common/Compare-TenantState.ps1'
$Rules     = Join-Path $repoRoot 'scripts/common/diff-rules.yaml'
$ReportSc  = Join-Path $repoRoot 'scripts/report/New-FrameworkReport.ps1'
$ExecSc    = Join-Path $repoRoot 'scripts/report/New-ExecutiveSummary.ps1'

if (-not (Test-Path $TenantConfigPath))      { throw "tenant.yaml not found: $TenantConfigPath" }
if (-not (Test-Path $ScanBundlePath))        { throw "scan bundle not found: $ScanBundlePath" }
if (-not (Test-Path (Join-Path $ScanBundlePath 'manifest.json'))) {
    throw "scan bundle manifest.json missing under $ScanBundlePath"
}

# Workload apply primitives — extend here as new Set-<Workload>.ps1 ship.
$script:WorkloadApplyScripts = @(
    [pscustomobject]@{ workload = 'conditional-access'; script = 'scripts/apply/Set-ConditionalAccess.ps1'; subdir = 'conditional-access' }
    [pscustomobject]@{ workload = 'purview';            script = 'scripts/apply/Set-PurviewBaseline.ps1';   subdir = 'purview' }
)

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ----- Read tenant + manifest -------------------------------------------
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Install-Module powershell-yaml -Scope CurrentUser -Force -AcceptLicense | Out-Null
}
Import-Module powershell-yaml -ErrorAction Stop

$tenantDoc = ConvertFrom-Yaml (Get-Content -Raw -LiteralPath $TenantConfigPath) -Ordered
$tenantId  = [string]$tenantDoc.tenant.id
$manifest  = Get-Content -Raw -LiteralPath (Join-Path $ScanBundlePath 'manifest.json') | ConvertFrom-Json -Depth 25

# ----- Gate 1: tenant identity ------------------------------------------
$gateProblems = [System.Collections.Generic.List[hashtable]]::new()
if ($manifest.tenant.tenantId -ne $tenantId) {
    [void]$gateProblems.Add(@{
        gate = 'tenant.identity'
        detail = "Scan bundle tenantId ($($manifest.tenant.tenantId)) does not match tenant.yaml id ($tenantId)"
    })
}

# ----- Resolve baseline -------------------------------------------------
$resolvedPath = Join-Path $OutputDir 'resolved-baseline.json'
& $Resolve -TenantConfigPath $TenantConfigPath -BaselinesRoot $BaselinesRoot -OutputPath $resolvedPath | Out-Null
$resolved = Get-Content -Raw -LiteralPath $resolvedPath | ConvertFrom-Json -Depth 30 -AsHashtable

# ----- Gate 2: break-glass posture --------------------------------------
$bgGroup = $null
$bgEntra = $null
if ($resolved.target -and $resolved.target.entra -and $resolved.target.entra.PSObject.Properties.Name -contains 'break_glass') {
    $bgEntra = $resolved.target.entra.break_glass
} elseif ($resolved.target.ContainsKey('entra')) {
    $entra = $resolved.target.entra
    if ($entra -and $entra.ContainsKey('break_glass')) { $bgEntra = $entra.break_glass }
}
if ($bgEntra) {
    $bgGroup = if ($bgEntra -is [System.Collections.IDictionary]) { $bgEntra.group_id } else { $bgEntra.group_id }
}
if (-not $bgGroup) {
    [void]$gateProblems.Add(@{
        gate = 'break-glass.declared'
        detail = 'baseline.entra.break_glass.group_id is empty. Refusing to proceed without a documented break-glass posture.'
    })
}

# ----- Gate 3: licence sufficiency (best-effort) -------------------------
$tenantTier = $null
if ($tenantDoc.licensing) { $tenantTier = $tenantDoc.licensing.tier }
$caPolicies = @()
if ($resolved.target.ContainsKey('entra') -and $resolved.target.entra.ContainsKey('conditional_access_policies')) {
    $caPolicies = $resolved.target.entra.conditional_access_policies
}
$p2Required = $false
foreach ($p in $caPolicies) {
    $p2 = $false
    $cond = $p.conditions
    if ($cond -and $cond.ContainsKey('signInRiskLevels'))  { $p2 = $true }
    if ($cond -and $cond.ContainsKey('userRiskLevels'))    { $p2 = $true }
    if ($p2) { $p2Required = $true; break }
}
$tenantHasP2 = $false
if ($tenantTier -in 'E5','EM_S_E5','SPE_E5') { $tenantHasP2 = $true }
elseif ($tenantDoc.licensing -and $tenantDoc.licensing.addons) {
    foreach ($a in $tenantDoc.licensing.addons) {
        if ($a -match 'P2|E5') { $tenantHasP2 = $true; break }
    }
}
if ($p2Required -and -not $tenantHasP2) {
    [void]$gateProblems.Add(@{
        gate    = 'licence.sufficiency'
        severity= 'warning'
        detail  = 'Baseline includes risk-based CA policies (sign-in or user risk) which require Entra ID P2; tenant.licensing does not declare P2/E5. Plans for those policies will likely fail at apply time.'
    })
}

# ----- Run diff engine --------------------------------------------------
$findingsPath = Join-Path $OutputDir 'findings.json'
& $Compare -ResolvedBaselinePath $resolvedPath -BundlePath $ScanBundlePath -RulesPath $Rules -OutputPath $findingsPath | Out-Null

# ----- Reports ----------------------------------------------------------
$reportDir = Join-Path $OutputDir 'reports'
if (-not $SkipReports) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    foreach ($fw in 'cis-m365','dora','nis2','hipaa') {
        & $ReportSc `
            -Framework $fw `
            -FindingsPath $findingsPath `
            -ResolvedBaselinePath $resolvedPath `
            -OutputPath (Join-Path $reportDir "$fw.md") `
            -TenantDisplayName $tenantDoc.tenant.display_name | Out-Null
    }
    & $ExecSc `
        -FindingsPath $findingsPath `
        -OutputPath   (Join-Path $reportDir 'executive-summary.md') `
        -TenantDisplayName $tenantDoc.tenant.display_name | Out-Null
}

# ----- Audit mode short-circuit -----------------------------------------
$findings = Get-Content -Raw -LiteralPath $findingsPath | ConvertFrom-Json -Depth 25
if ($Mode -eq 'audit') {
    [pscustomobject]@{
        mode             = 'audit'
        tenantId         = $tenantId
        outputDir        = (Resolve-Path $OutputDir).Path
        resolvedBaseline = $resolvedPath
        findings         = $findingsPath
        reports          = if ($SkipReports) { @() } else { Get-ChildItem $reportDir | ForEach-Object { $_.FullName } }
        gates            = @{ problems = @($gateProblems); blocking = @($gateProblems | Where-Object { ($_['severity'] -eq $null) -or ($_['severity'] -ne 'warning') }) }
        summary          = $findings.summary
    }
    return
}

# ----- Per-workload plan dispatch ---------------------------------------
$workloadPlans = [System.Collections.Generic.List[hashtable]]::new()
foreach ($w in $script:WorkloadApplyScripts) {
    $scriptPath = Join-Path $repoRoot $w.script
    if (-not (Test-Path $scriptPath)) {
        [void]$workloadPlans.Add(@{ workload = $w.workload; status = 'skipped-no-script' })
        continue
    }
    $wDir = Join-Path $OutputDir $w.subdir
    New-Item -ItemType Directory -Path $wDir -Force | Out-Null
    try {
        $result = & $scriptPath `
            -ResolvedBaselinePath $resolvedPath `
            -ScanBundlePath       $ScanBundlePath `
            -TenantId             $tenantId `
            -OutputDir            $wDir `
            -Mode                 plan
        $planFile = Join-Path $wDir 'plan.json'
        $plan     = Get-Content -Raw -LiteralPath $planFile | ConvertFrom-Json -Depth 25 -AsHashtable
        [void]$workloadPlans.Add(@{
            workload   = $w.workload
            status     = 'planned'
            planFile   = $planFile
            summary    = $plan.summary
            blockedBy  = @($plan.blockedBy)
            actionCount= @($plan.actions).Count
        })
    } catch {
        [void]$workloadPlans.Add(@{ workload = $w.workload; status = 'plan-failed'; error = $_.Exception.Message })
    }
}

# ----- Aggregate tenant plan --------------------------------------------
$blockedTotal = 0
foreach ($wp in $workloadPlans) { if ($wp.blockedBy) { $blockedTotal += $wp.blockedBy.Count } }

$aggregate = [ordered]@{
    schemaVersion    = '1.0.0'
    tenantId         = $tenantId
    displayName      = $tenantDoc.tenant.display_name
    mode             = $Mode
    generatedAt      = (Get-Date).ToUniversalTime().ToString('o')
    baselineProfiles = @($tenantDoc.profiles)
    overallSummary   = @{
        findings        = $findings.summary
        workloadsPlanned= @($workloadPlans | Where-Object status -eq 'planned').Count
        workloadsSkipped= @($workloadPlans | Where-Object status -ne 'planned').Count
        blockedBy       = $blockedTotal
    }
    gates            = @{
        problems        = @($gateProblems)
        blockingCount   = @($gateProblems | Where-Object { -not $_.severity -or $_.severity -ne 'warning' }).Count
    }
    workloads        = @($workloadPlans)
    requiresApproval = ($Mode -in 'apply-pilot','apply-broad','rollback')
    approvalRef      = $ApprovalRef
}

$aggregatePath = Join-Path $OutputDir 'tenant-plan.json'
$aggregate | ConvertTo-Json -Depth 25 | Out-File -LiteralPath $aggregatePath -Encoding utf8

if ($Mode -eq 'plan') {
    [pscustomobject]@{
        mode      = 'plan'
        tenantId  = $tenantId
        plan      = (Resolve-Path $aggregatePath).Path
        findings  = (Resolve-Path $findingsPath).Path
        reports   = if ($SkipReports) { @() } else { Get-ChildItem $reportDir | ForEach-Object { $_.FullName } }
        summary   = $aggregate.overallSummary
        gates     = $aggregate.gates
    }
    return
}

# ----- Apply / rollback -------------------------------------------------
if (-not $ApprovalRef) {
    throw "Mode '$Mode' requires -ApprovalRef (a ticket / PR / out-of-band:<reason>). No silent writes."
}
if ($aggregate.gates.blockingCount -gt 0) {
    throw "Tenant gates blocked: $($aggregate.gates.blockingCount). See $aggregatePath."
}
if ($blockedTotal -gt 0) {
    throw "Workload plans report $blockedTotal safety block(s) total. Resolve before applying. See per-workload plan.json files."
}

$changesAggregate = [System.Collections.Generic.List[hashtable]]::new()
foreach ($w in $script:WorkloadApplyScripts) {
    $scriptPath = Join-Path $repoRoot $w.script
    if (-not (Test-Path $scriptPath)) { continue }
    $wDir = Join-Path $OutputDir $w.subdir
    try {
        $result = & $scriptPath `
            -ResolvedBaselinePath $resolvedPath `
            -ScanBundlePath       $ScanBundlePath `
            -TenantId             $tenantId `
            -OutputDir            $wDir `
            -Mode                 apply `
            -ApprovalRef          $ApprovalRef
        $changesPath = Join-Path $wDir 'changes.json'
        if (Test-Path $changesPath) {
            $changes = Get-Content -Raw -LiteralPath $changesPath | ConvertFrom-Json -Depth 25 -AsHashtable
            [void]$changesAggregate.Add(@{
                workload     = $w.workload
                summary      = $changes.summary
                changesFile  = $changesPath
            })
        } else {
            [void]$changesAggregate.Add(@{ workload = $w.workload; status = 'no-changes-file' })
        }
    } catch {
        [void]$changesAggregate.Add(@{ workload = $w.workload; status = 'apply-failed'; error = $_.Exception.Message })
    }
}

$applyAgg = [ordered]@{
    schemaVersion = '1.0.0'
    tenantId      = $tenantId
    mode          = $Mode
    approvalRef   = $ApprovalRef
    completedAt   = (Get-Date).ToUniversalTime().ToString('o')
    workloads     = @($changesAggregate)
}
$applyAggPath = Join-Path $OutputDir 'tenant-changes.json'
$applyAgg | ConvertTo-Json -Depth 25 | Out-File -LiteralPath $applyAggPath -Encoding utf8

[pscustomobject]@{
    mode          = $Mode
    tenantId      = $tenantId
    plan          = (Resolve-Path $aggregatePath).Path
    changes       = (Resolve-Path $applyAggPath).Path
    workloads     = $changesAggregate
}
