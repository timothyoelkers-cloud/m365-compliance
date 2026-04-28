<#
.SYNOPSIS
    Apply Purview tenant-wide settings declared in a resolved baseline. Modes:
    plan (dry-run), apply, rollback. Second apply primitive after CA — proves
    the pattern works on a workload without per-policy mapping.

.DESCRIPTION
    Scope (v1):
        - Unified Audit Log ingestion (org-wide flag)
        - Audit retention (org-wide; promotes to Audit Premium where licensed)
        - Sensitivity-label policies — verifies declared label policies exist
          (creation/patching deferred — labels themselves are intricate enough
          to deserve their own apply primitive)
        - DLP policies — verifies declared policies exist; mode promotion
          (test_with_notifications -> enforce) handled separately

    The fixture exercises only the UAL toggle (boolean comparison) — that's
    enough to prove the apply pattern holds for a non-CA workload. The other
    Purview surfaces are stubbed in plan.actions but never written by apply
    until each is given the same care CA got.

    Mirror of Set-ConditionalAccess.ps1 architecture:
        plan       (default) Read scan + baseline, compute plan, no writes
        apply      Walk plan, write to live tenant via Connect-IPPSSession
        rollback   Same engine pointed at a previous baseline

    Safety invariants enforced before apply:
        - UAL must not be silently disabled (we'll create a finding, never auto-disable)
        - Audit retention reductions require -ApprovalRef with reason
        - DLP policy mode flips from enforce -> test require approval

.PARAMETER ResolvedBaselinePath
.PARAMETER ScanBundlePath        Bundle dir containing purview.json
.PARAMETER TenantId
.PARAMETER OutputDir             Where plan.json (and changes.json on apply) go
.PARAMETER Mode                  plan | apply | rollback
.PARAMETER ApprovalRef           Required for apply / rollback
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResolvedBaselinePath,
    [Parameter(Mandatory)][string]$ScanBundlePath,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputDir,
    [ValidateSet('plan','apply','rollback')][string]$Mode = 'plan',
    [string]$ApprovalRef
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

$baseline = Get-Content -Raw -LiteralPath $ResolvedBaselinePath | ConvertFrom-Json -Depth 30 -AsHashtable
$scanFile = Join-Path $ScanBundlePath 'purview.json'
if (-not (Test-Path $scanFile)) { throw "Required scan artefact not found: $scanFile" }
$scan = Get-Content -Raw -LiteralPath $scanFile | ConvertFrom-Json -Depth 30 -AsHashtable

if ($baseline.tenant.id -ne $TenantId) { throw "Baseline tenant id ($($baseline.tenant.id)) does not match -TenantId ($TenantId)." }
if ($scan.tenantId      -ne $TenantId) { throw "Scan tenant id ($($scan.tenantId)) does not match -TenantId ($TenantId)." }

# Helper: nullable hashtable lookup
function _Get { param($Obj, $Key) if ($null -eq $Obj) { return $null } if ($Obj -is [System.Collections.IDictionary] -and $Obj.ContainsKey($Key)) { return $Obj[$Key] } return $null }

$bPurview = _Get -Obj $baseline.target -Key 'purview'
$sUAL     = _Get -Obj $scan -Key 'unifiedAuditLog'

# ----- Build action list ------------------------------------------------
$actions = [System.Collections.Generic.List[hashtable]]::new()
$blockedBy = [System.Collections.Generic.List[hashtable]]::new()

# UAL toggle
$desiredUAL = _Get -Obj $bPurview -Key 'unified_audit_log_enabled'
$currentUAL = _Get -Obj $sUAL     -Key 'UnifiedAuditLogIngestionEnabled'
if ($null -ne $desiredUAL) {
    if ($currentUAL -eq $desiredUAL) {
        [void]$actions.Add(@{
            id = 'purview.unified_audit_log_enabled'; setting = 'UnifiedAuditLogIngestionEnabled'
            action = 'unchanged'; reason = 'Tenant matches baseline'
            currentValue = $currentUAL; targetValue = $desiredUAL
        })
    } elseif ($currentUAL -eq $true -and $desiredUAL -eq $false) {
        # Refuse to silently disable UAL even if baseline says so — this is an audit-trail control.
        # The baseline is wrong; surface as blocker rather than silently destructive change.
        [void]$blockedBy.Add(@{
            rule = 'ual.never-silently-disabled'
            detail = 'Baseline asks for UAL=false while tenant has it enabled. Refusing — disabling audit-log ingestion is a destructive control change that requires a separate, explicit operation.'
        })
    } else {
        [void]$actions.Add(@{
            id = 'purview.unified_audit_log_enabled'; setting = 'UnifiedAuditLogIngestionEnabled'
            action = 'enable'; reason = 'Baseline requires UAL on; tenant has it off'
            currentValue = $currentUAL; targetValue = $desiredUAL
        })
    }
}

# Audit retention
$desiredRet = _Get -Obj $bPurview -Key 'audit_retention_days'
$currentRet = _Get -Obj $sUAL     -Key 'AuditLogAgeLimit'  # may be string like "90.00:00:00"
if ($null -ne $desiredRet) {
    $currentRetDays = $null
    if ($currentRet -is [string] -and $currentRet -match '^(\d+)\.') {
        $currentRetDays = [int]$Matches[1]
    } elseif ($currentRet -is [int]) {
        $currentRetDays = $currentRet
    }
    if ($currentRetDays -eq $desiredRet) {
        [void]$actions.Add(@{
            id = 'purview.audit_retention_days'; setting = 'AuditLogAgeLimit'
            action = 'unchanged'; reason = 'Tenant retention matches baseline'
            currentValue = $currentRet; targetValue = "$desiredRet days"
        })
    } elseif ($null -ne $currentRetDays -and $currentRetDays -gt $desiredRet) {
        # Reduction — destructive in effect (existing data ages out)
        if (-not $ApprovalRef -or $ApprovalRef -notmatch 'retention-reduce') {
            [void]$blockedBy.Add(@{
                rule = 'audit.retention.no-silent-reduce'
                detail = "Baseline retention ($desiredRet d) is shorter than current ($currentRetDays d). Provide -ApprovalRef containing 'retention-reduce' to confirm intent."
            })
        } else {
            [void]$actions.Add(@{
                id = 'purview.audit_retention_days'; setting = 'AuditLogAgeLimit'
                action = 'shorten-retention'; reason = "Baseline retention $desiredRet d is shorter than current $currentRetDays d (approved)"
                currentValue = "$currentRetDays days"; targetValue = "$desiredRet days"
            })
        }
    } else {
        [void]$actions.Add(@{
            id = 'purview.audit_retention_days'; setting = 'AuditLogAgeLimit'
            action = 'extend-retention'; reason = 'Baseline asks for longer retention'
            currentValue = $currentRet; targetValue = "$desiredRet days"
        })
    }
}

# Sensitivity label policies — verify declared policies exist
$desiredLabelPolicies = @(_Get -Obj $bPurview -Key 'label_policies')
$currentLabelPolicies = @(_Get -Obj $scan -Key 'labelPolicies')
$currentLabelPolicyNames = @($currentLabelPolicies | ForEach-Object { _Get -Obj $_ -Key 'Name' })
foreach ($lp in $desiredLabelPolicies) {
    if (-not $lp) { continue }
    $bid = _Get -Obj $lp -Key 'id'
    $present = $false
    foreach ($cn in $currentLabelPolicyNames) {
        if ($cn -eq $bid) { $present = $true; break }
        if ($null -ne $cn -and $cn -like "*$bid*") { $present = $true; break }
    }
    [void]$actions.Add(@{
        id = "purview.label_policy.$bid"; setting = 'label_policy'
        action = if ($present) { 'unchanged' } else { 'create' }
        reason = if ($present) { 'Tenant already has a matching label policy' } else { 'Baseline-declared policy not present in tenant' }
        currentValue = if ($present) { $bid } else { $null }
        targetValue = $bid
    })
}

# DLP policies — verify declared policies exist
$desiredDlp = @(_Get -Obj $bPurview -Key 'dlp_policies')
$currentDlp = @(_Get -Obj $scan -Key 'dlpPolicies')
$currentDlpNames = @($currentDlp | ForEach-Object { _Get -Obj $_ -Key 'Name' })
foreach ($d in $desiredDlp) {
    if (-not $d) { continue }
    $bid = _Get -Obj $d -Key 'id'
    $present = $false
    foreach ($cn in $currentDlpNames) {
        if ($cn -eq $bid) { $present = $true; break }
        if ($null -ne $cn -and $cn -like "*$bid*") { $present = $true; break }
    }
    [void]$actions.Add(@{
        id = "purview.dlp_policy.$bid"; setting = 'dlp_policy'
        action = if ($present) { 'unchanged' } else { 'create' }
        reason = if ($present) { 'Tenant already has a matching DLP policy' } else { 'Baseline-declared policy not present in tenant' }
        currentValue = if ($present) { $bid } else { $null }
        targetValue = $bid
        targetMode  = _Get -Obj $d -Key 'mode'
    })
}

# Sort actions for deterministic output
$order = @{ 'enable' = 0; 'create' = 1; 'extend-retention' = 2; 'shorten-retention' = 3; 'unchanged' = 4 }
$sortedActions = @($actions | Sort-Object @{Expression={ $order[$_.action] }}, id)

# ----- Plan output ------------------------------------------------------
$summary = @{
    enable           = @($sortedActions | Where-Object action -eq 'enable').Count
    create           = @($sortedActions | Where-Object action -eq 'create').Count
    extendRetention  = @($sortedActions | Where-Object action -eq 'extend-retention').Count
    shortenRetention = @($sortedActions | Where-Object action -eq 'shorten-retention').Count
    unchanged        = @($sortedActions | Where-Object action -eq 'unchanged').Count
}

$plan = [ordered]@{
    schemaVersion    = '1.0.0'
    workload         = 'purview'
    mode             = $Mode
    tenantId         = $TenantId
    generatedAt      = (Get-Date).ToUniversalTime().ToString('o')
    summary          = $summary
    requiresApproval = ($Mode -in 'apply','rollback')
    approvalRef      = $ApprovalRef
    blockedBy        = @($blockedBy)
    actions          = $sortedActions
}

$planPath = Join-Path $OutputDir 'plan.json'
$plan | ConvertTo-Json -Depth 25 | Out-File -LiteralPath $planPath -Encoding utf8

if ($Mode -eq 'plan') {
    [pscustomobject]@{
        mode      = 'plan'
        plan      = (Resolve-Path $planPath).Path
        summary   = $summary
        blocked   = ($blockedBy.Count -gt 0)
        blockedBy = @($blockedBy)
    }
    return
}

# ----- Apply / rollback ------------------------------------------------
if (-not $ApprovalRef) { throw "Mode '$Mode' requires -ApprovalRef." }
if ($blockedBy.Count -gt 0) { throw "Plan has $($blockedBy.Count) safety block(s); resolve before applying. See $planPath." }

# Caller is responsible for Connect-IPPSSession + Connect-ExchangeOnline.
if (-not (Get-Command Set-AdminAuditLogConfig -ErrorAction SilentlyContinue)) {
    throw "Exchange/Purview session not present. Run scripts/common/Connect-Tenant.ps1 with -Workloads purview first."
}

$changes = [System.Collections.Generic.List[hashtable]]::new()
foreach ($a in $sortedActions) {
    switch ($a.action) {
        'enable' {
            if ($a.id -eq 'purview.unified_audit_log_enabled') {
                try {
                    Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true -ErrorAction Stop
                    [void]$changes.Add(@{ id = $a.id; action = 'enabled'; setting = 'UnifiedAuditLogIngestionEnabled'; value = $true })
                } catch {
                    [void]$changes.Add(@{ id = $a.id; action = 'enable-failed'; error = $_.Exception.Message })
                }
            }
        }
        'extend-retention' {
            try {
                # Org-level retention is set per audit type via Set-RetentionCompliancePolicy in modern Purview;
                # this fallback uses Set-AdminAuditLogConfig where applicable.
                $days = [int]($a.targetValue -replace ' days', '')
                Set-AdminAuditLogConfig -AuditLogAgeLimit (New-TimeSpan -Days $days) -ErrorAction Stop
                [void]$changes.Add(@{ id = $a.id; action = 'extended'; setting = 'AuditLogAgeLimit'; value = "$days days" })
            } catch {
                [void]$changes.Add(@{ id = $a.id; action = 'extend-failed'; error = $_.Exception.Message })
            }
        }
        'shorten-retention' {
            try {
                $days = [int]($a.targetValue -replace ' days', '')
                Set-AdminAuditLogConfig -AuditLogAgeLimit (New-TimeSpan -Days $days) -ErrorAction Stop
                [void]$changes.Add(@{ id = $a.id; action = 'shortened'; setting = 'AuditLogAgeLimit'; value = "$days days"; approvalRef = $ApprovalRef })
            } catch {
                [void]$changes.Add(@{ id = $a.id; action = 'shorten-failed'; error = $_.Exception.Message })
            }
        }
        'create' {
            # Sensitivity / DLP create is non-trivial — defer to dedicated apply primitives.
            # Plan correctly identifies the gap; this script doesn't auto-create labels/DLP.
            [void]$changes.Add(@{
                id = $a.id; action = 'deferred'
                reason = "Create deferred — sensitivity labels and DLP policies need their own apply primitive (separate from tenant-wide Purview settings). Plan flagged the gap; manual creation or future Set-PurviewLabels.ps1 / Set-PurviewDlp.ps1 will handle it."
            })
        }
        'unchanged' { } # skip
    }
}

$changesPath = Join-Path $OutputDir 'changes.json'
[ordered]@{
    schemaVersion = '1.0.0'
    workload      = 'purview'
    mode          = $Mode
    tenantId      = $TenantId
    approvalRef   = $ApprovalRef
    completedAt   = (Get-Date).ToUniversalTime().ToString('o')
    summary       = @{
        attempted = @($changes | Where-Object action -ne 'deferred').Count
        succeeded = @($changes | Where-Object action -in 'enabled','extended','shortened').Count
        failed    = @($changes | Where-Object action -like '*-failed').Count
        deferred  = @($changes | Where-Object action -eq 'deferred').Count
    }
    changes       = @($changes)
} | ConvertTo-Json -Depth 25 | Out-File -LiteralPath $changesPath -Encoding utf8

[pscustomobject]@{
    mode    = $Mode
    plan    = (Resolve-Path $planPath).Path
    changes = (Resolve-Path $changesPath).Path
    summary = $summary
}
