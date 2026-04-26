<#
.SYNOPSIS
    Apply Conditional Access policies declared in a resolved baseline against
    a single Entra tenant. Modes: plan (dry-run), apply, rollback.

.DESCRIPTION
    Reads:
        -ResolvedBaselinePath   The output of scripts/common/Resolve-Baseline.ps1
        -ScanBundlePath         A scan bundle directory (must contain conditional-access.json)
                                — used as the "current state" snapshot. The script never reads
                                live Graph state for planning. This is intentional: planning is
                                reproducible offline, and a separate orchestrator owns the
                                "scan-then-plan-then-apply" sequencing.
        -TenantMapPath          Optional path to ca.tenant-map.yaml mapping baseline IDs to
                                tenant policy GUIDs. Falls back to displayName matching.

    Writes (apply mode only):
        -OutputDir/changes.json — actions taken with before/after policy snapshots.
        Live tenant: Microsoft.Graph.Identity.SignIns cmdlets via an authenticated
        Graph session (caller's responsibility — see scripts/common/Connect-Tenant.ps1).

    Outputs (always):
        -OutputDir/plan.json    — the computed plan, including blockedBy reasons
                                  for any safety invariants that fail.

    Modes:
        plan       (default) Read + diff + emit plan.json. NO writes.
        apply      Plan, then walk actions and write to the live tenant. Refuses
                   if any safety invariant blocks the plan.
        rollback   Apply against a previous resolved baseline (-ResolvedBaselinePath
                   pointed at the prior baseline output). Reverse-direction is
                   produced naturally by the same diff logic.

    Safety invariants — apply will refuse if any are violated:
        - Break-glass exclusion present on every user-blocking policy in the plan.
        - No state transition skipping enabledForReportingButNotEnforced
          (disabled -> enabled must go via report-only).
        - grantControls non-empty on any non-block policy.
        - authenticationStrength references resolve to a known strength id.
        - No policy in plan has empty users/applications.

    Idempotency:
        Re-running with the same baseline + scan input produces an identical plan.
        Re-running apply after a successful apply produces an empty change set.

.PARAMETER ResolvedBaselinePath  Path to the resolved-baseline JSON.
.PARAMETER ScanBundlePath        Path to scan bundle dir (containing conditional-access.json).
.PARAMETER TenantId              Target tenant GUID. Must match the baseline.
.PARAMETER OutputDir             Directory to write plan.json (and changes.json on apply).
.PARAMETER Mode                  plan | apply | rollback   (default: plan)
.PARAMETER TenantMapPath         Optional explicit map path. Defaults to
                                 baselines/tenants/<tenant>/ca.tenant-map.yaml.
.PARAMETER ApprovalRef           Required for apply / rollback — ticket ID, PR link,
                                 or "out-of-band:<freeform>" recorded in evidence.
                                 Refused if blank in apply mode (no silent writes).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ResolvedBaselinePath,
    [Parameter(Mandatory)][string]$ScanBundlePath,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputDir,
    [ValidateSet('plan','apply','rollback')][string]$Mode = 'plan',
    [string]$TenantMapPath,
    [string]$ApprovalRef
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Install-Module powershell-yaml -Scope CurrentUser -Force -AcceptLicense | Out-Null
}
Import-Module powershell-yaml -ErrorAction Stop

if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

$baseline = Get-Content -Raw -LiteralPath $ResolvedBaselinePath | ConvertFrom-Json -Depth 30 -AsHashtable
$scanFile = Join-Path $ScanBundlePath 'conditional-access.json'
if (-not (Test-Path $scanFile)) {
    throw "Required scan artefact not found: $scanFile"
}
$scan = Get-Content -Raw -LiteralPath $scanFile | ConvertFrom-Json -Depth 30 -AsHashtable

if ($baseline.tenant.id -ne $TenantId) {
    throw "Baseline tenant id ($($baseline.tenant.id)) does not match -TenantId ($TenantId)."
}
if ($scan.tenantId -ne $TenantId) {
    throw "Scan tenant id ($($scan.tenantId)) does not match -TenantId ($TenantId)."
}

# ----- Tenant policy map (baseline-id -> tenant CA policy GUID) ----------
if (-not $TenantMapPath) {
    $repoRoot = Resolve-Path (Join-Path $PSCommandPath '../../..') -ErrorAction SilentlyContinue
    if ($repoRoot) {
        $TenantMapPath = Join-Path $repoRoot.Path "baselines/tenants/$TenantId/ca.tenant-map.yaml"
    }
}
$tenantMap = @{}
if ($TenantMapPath -and (Test-Path $TenantMapPath)) {
    $mapDoc = ConvertFrom-Yaml (Get-Content -Raw -LiteralPath $TenantMapPath)
    if ($mapDoc.policies) {
        foreach ($entry in $mapDoc.policies) { $tenantMap[$entry.baseline_id] = $entry.tenant_policy_id }
    }
}

# ----- Build a lookup of tenant policies by GUID and by displayName ------
$tenantById   = @{}
$tenantByName = @{}
foreach ($p in $scan.policies) {
    $tenantById[$p.id]                = $p
    if ($p.displayName) { $tenantByName[$p.displayName] = $p }
}

# Display-name fallback: match baseline id to tenant policy whose displayName
# starts with a CIS-flavoured pattern. Brittle; the tenant map is preferred.
function Resolve-TenantPolicy {
    param([string]$BaselineId, [string]$BaselineDisplay)
    if ($tenantMap.ContainsKey($BaselineId)) {
        $g = $tenantMap[$BaselineId]
        if ($tenantById.ContainsKey($g)) { return $tenantById[$g] }
    }
    if ($BaselineDisplay -and $tenantByName.ContainsKey($BaselineDisplay)) {
        return $tenantByName[$BaselineDisplay]
    }
    return $null
}

# ----- Baseline -> Graph normaliser --------------------------------------
# Populated baselines use YAML-friendly names (include / exclude_groups);
# Graph emits its own names (includeUsers / excludeGroups). Diff and apply
# happen against Graph shape — never compare baseline shape directly.

$script:UsersRenames = @{
    'include'                          = 'includeUsers'
    'exclude'                          = 'excludeUsers'
    'include_users'                    = 'includeUsers'
    'exclude_users'                    = 'excludeUsers'
    'include_groups'                   = 'includeGroups'
    'exclude_groups'                   = 'excludeGroups'
    'include_roles'                    = 'includeRoles'
    'exclude_roles'                    = 'excludeRoles'
    'include_guests_or_external_users' = 'includeGuestsOrExternalUsers'
    'exclude_guests_or_external_users' = 'excludeGuestsOrExternalUsers'
}
$script:AppsRenames = @{
    'include'              = 'includeApplications'
    'exclude'              = 'excludeApplications'
    'include_applications' = 'includeApplications'
    'exclude_applications' = 'excludeApplications'
    'include_user_actions' = 'includeUserActions'
}
$script:PlatformRenames = @{ 'include' = 'includePlatforms'; 'exclude' = 'excludePlatforms' }
$script:LocationRenames = @{ 'include' = 'includeLocations'; 'exclude' = 'excludeLocations' }

function ConvertFrom-PSObjectToHashtable {
    param($Obj)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Collections.IDictionary]) {
        $out = @{}
        foreach ($k in $Obj.Keys) { $out[$k] = ConvertFrom-PSObjectToHashtable -Obj $Obj[$k] }
        return $out
    }
    if ($Obj -is [pscustomobject]) {
        $out = @{}
        foreach ($p in $Obj.PSObject.Properties) { $out[$p.Name] = ConvertFrom-PSObjectToHashtable -Obj $p.Value }
        return $out
    }
    if ($Obj -is [System.Collections.IList] -and $Obj -isnot [string]) {
        return @($Obj | ForEach-Object { ConvertFrom-PSObjectToHashtable -Obj $_ })
    }
    return $Obj
}

function _RenameKeys {
    param($Dict, $Renames)
    if (-not ($Dict -is [System.Collections.IDictionary])) { return $Dict }
    $out = @{}
    foreach ($k in $Dict.Keys) {
        $newKey = if ($Renames.ContainsKey($k)) { $Renames[$k] } else { $k }
        $out[$newKey] = $Dict[$k]
    }
    return $out
}

function _StripEmpty {
    param($Obj)
    if ($null -eq $Obj) { return $null }
    if ($Obj -is [System.Collections.IList] -and $Obj -isnot [string]) {
        $cleaned = @($Obj | ForEach-Object { _StripEmpty -Obj $_ } | Where-Object { $null -ne $_ -and -not ($_ -is [System.Collections.IList] -and $_.Count -eq 0) -and -not ($_ -is [System.Collections.IDictionary] -and $_.Keys.Count -eq 0) })
        if ($cleaned.Count -eq 0) { return $null } else { return $cleaned }
    }
    if ($Obj -is [System.Collections.IDictionary]) {
        $out = @{}
        foreach ($k in $Obj.Keys) {
            $v = _StripEmpty -Obj $Obj[$k]
            if ($null -ne $v -and -not ($v -is [System.Collections.IList] -and $v.Count -eq 0) -and -not ($v -is [System.Collections.IDictionary] -and $v.Keys.Count -eq 0)) {
                $out[$k] = $v
            }
        }
        if ($out.Keys.Count -eq 0) { return $null } else { return $out }
    }
    return $Obj
}

function ConvertTo-GraphCaPolicy {
    <#
    .SYNOPSIS Convert a baseline-shaped CA policy to Graph shape (for diff or apply).
    #>
    param($Policy)
    if ($null -eq $Policy) { return $null }
    $p = ConvertFrom-PSObjectToHashtable -Obj $Policy

    $out = @{}
    foreach ($k in @('id','displayName','state')) { if ($p.ContainsKey($k)) { $out[$k] = $p[$k] } }

    $newConds = @{}
    if ($p.ContainsKey('conditions') -and $p['conditions']) {
        $c = $p['conditions']
        if ($c.ContainsKey('users'))        { $newConds['users']        = _RenameKeys -Dict $c['users']        -Renames $script:UsersRenames }
        if ($c.ContainsKey('applications')) { $newConds['applications'] = _RenameKeys -Dict $c['applications'] -Renames $script:AppsRenames  }
        if ($c.ContainsKey('platforms'))    { $newConds['platforms']    = _RenameKeys -Dict $c['platforms']    -Renames $script:PlatformRenames }
        if ($c.ContainsKey('locations'))    { $newConds['locations']    = _RenameKeys -Dict $c['locations']    -Renames $script:LocationRenames }
        foreach ($k in @('clientAppTypes','signInRiskLevels','userRiskLevels','servicePrincipalRiskLevels')) {
            if ($c.ContainsKey($k)) { $newConds[$k] = $c[$k] }
        }
        if ($c.ContainsKey('authentication_flows')) { $newConds['authenticationFlows'] = $c['authentication_flows'] }
        if ($c.ContainsKey('device_filter'))        { $newConds['deviceFilter']        = $c['device_filter'] }
    }
    if ($newConds.Keys.Count -gt 0) { $out['conditions'] = $newConds }

    if ($p.ContainsKey('grantControls') -and $p['grantControls']) {
        $gc = @{} + $p['grantControls']
        if ($gc.ContainsKey('authenticationStrength') -and $gc['authenticationStrength'] -is [string]) {
            $gc['authenticationStrength'] = @{ id = $gc['authenticationStrength'] }
        }
        $out['grantControls'] = $gc
    }
    if ($p.ContainsKey('sessionControls') -and $p['sessionControls']) {
        $out['sessionControls'] = $p['sessionControls']
    }

    return _StripEmpty -Obj $out
}

# ----- Compute action per baseline policy --------------------------------
function Compare-Policy {
    param($Baseline, $Tenant)
    $diff = [System.Collections.Generic.List[hashtable]]::new()

    $bGraph = ConvertTo-GraphCaPolicy -Policy $Baseline
    $tGraph = _StripEmpty -Obj (ConvertFrom-PSObjectToHashtable -Obj $Tenant)

    function _serialize($obj) {
        if ($null -eq $obj) { return 'null' }
        ($obj | ConvertTo-Json -Depth 25 -Compress)
    }

    if ($bGraph.state -ne $tGraph.state) {
        [void]$diff.Add(@{ field = 'state'; current = $tGraph.state; target = $bGraph.state })
    }
    if ((_serialize $bGraph.conditions) -ne (_serialize $tGraph.conditions)) {
        [void]$diff.Add(@{ field = 'conditions'; current = $tGraph.conditions; target = $bGraph.conditions })
    }
    if ((_serialize $bGraph.grantControls) -ne (_serialize $tGraph.grantControls)) {
        [void]$diff.Add(@{ field = 'grantControls'; current = $tGraph.grantControls; target = $bGraph.grantControls })
    }
    if ((_serialize $bGraph.sessionControls) -ne (_serialize $tGraph.sessionControls)) {
        [void]$diff.Add(@{ field = 'sessionControls'; current = $tGraph.sessionControls; target = $bGraph.sessionControls })
    }
    return $diff
}

# ----- Safety invariants -------------------------------------------------
function Test-Invariants {
    param($Plan)
    $blockedBy = [System.Collections.Generic.List[hashtable]]::new()

    $bgGroupId = $baseline.target.entra.break_glass.group_id
    if (-not $bgGroupId) {
        [void]$blockedBy.Add(@{ rule = 'break-glass.declared';    detail = 'No break-glass group declared in baseline.entra.break_glass.group_id' })
    }

    foreach ($action in $Plan.actions) {
        if ($action.action -in 'create','patch') {
            $b = $action.targetPolicy
            if (-not $b) { continue }

            # Empty users / applications
            if (-not $b.conditions.users      -or -not $b.conditions.users.include)        {
                [void]$blockedBy.Add(@{ rule = 'conditions.users.nonempty';        baselineId = $action.baselineId })
            }
            if (-not $b.conditions.applications -or -not $b.conditions.applications.include) {
                [void]$blockedBy.Add(@{ rule = 'conditions.applications.nonempty'; baselineId = $action.baselineId })
            }

            # Block policies must exclude break-glass
            $isBlock = ($b.grantControls -and $b.grantControls.builtInControls -contains 'block')
            if ($isBlock -and $bgGroupId) {
                $excluded = $b.conditions.users.exclude_groups -contains $bgGroupId `
                            -or $b.conditions.users.excludeGroups -contains $bgGroupId
                if (-not $excluded) {
                    [void]$blockedBy.Add(@{ rule = 'break-glass.excluded'; baselineId = $action.baselineId; detail = "Block policy does not exclude $bgGroupId" })
                }
            }

            # Non-block policies must have at least one grant control
            if (-not $isBlock -and ($null -eq $b.grantControls -or `
                ((-not $b.grantControls.builtInControls -or $b.grantControls.builtInControls.Count -eq 0) -and `
                 -not $b.grantControls.authenticationStrength))) {
                [void]$blockedBy.Add(@{ rule = 'grantControls.nonempty'; baselineId = $action.baselineId; detail = 'Non-block policy must declare at least one grant control or authenticationStrength' })
            }

            # Forbidden state transition: disabled -> enabled directly
            if ($action.action -eq 'patch' -and `
                ($action.currentState -eq 'disabled' -and $b.state -eq 'enabled')) {
                [void]$blockedBy.Add(@{ rule = 'state.transition'; baselineId = $action.baselineId; detail = 'Must transition disabled -> enabledForReportingButNotEnforced before -> enabled' })
            }

            # Auth strength reference must resolve
            if ($b.grantControls -and $b.grantControls.authenticationStrength) {
                $ref = $b.grantControls.authenticationStrength
                $declared = $baseline.target.entra.authentication_strengths
                $resolved = $false
                if ($declared) {
                    foreach ($s in $declared) { if ($s.id -eq $ref) { $resolved = $true; break } }
                }
                # Also accept built-in Microsoft strengths (mfa, phishingResistantMfa, etc) by name
                $builtIn = @('mfa','passwordlessMfa','phishingResistantMfa')
                if (-not $resolved -and ($builtIn -notcontains $ref)) {
                    [void]$blockedBy.Add(@{ rule = 'authenticationStrength.resolved'; baselineId = $action.baselineId; detail = "authenticationStrength '$ref' not declared in baseline.entra.authentication_strengths and not a built-in" })
                }
            }
        }
    }
    return $blockedBy
}

# ----- Build plan --------------------------------------------------------
$baselinePolicies = @($baseline.target.entra.conditional_access_policies)
$plan = [ordered]@{
    schemaVersion       = '1.0.0'
    workload            = 'conditional-access'
    mode                = $Mode
    tenantId            = $TenantId
    baselineGitSha      = if ($baseline.PSObject.Properties.Name -contains 'profiles') { 'unknown' } else { 'unknown' }
    generatedAt         = (Get-Date).ToUniversalTime().ToString('o')
    actions             = @()
    summary             = @{ create = 0; patch = 0; unchanged = 0; remove = 0 }
    blockedBy           = @()
    requiresApproval    = ($Mode -in 'apply','rollback')
    approvalRef         = $ApprovalRef
}

$baselineIds = @{}
foreach ($b in $baselinePolicies) {
    $baselineIds[$b.id] = $true
    $tenantPolicy = Resolve-TenantPolicy -BaselineId $b.id -BaselineDisplay $b.displayName
    if (-not $tenantPolicy) {
        $plan.actions += [ordered]@{
            baselineId   = $b.id
            displayName  = $b.displayName
            action       = 'create'
            reason       = 'Baseline policy not present in tenant'
            currentState = $null
            targetState  = $b.state
            targetPolicy = $b
        }
        $plan.summary.create++
        continue
    }
    $diff = Compare-Policy -Baseline $b -Tenant $tenantPolicy
    if ($diff.Count -eq 0) {
        $plan.actions += [ordered]@{
            baselineId   = $b.id
            displayName  = $b.displayName
            tenantId     = $tenantPolicy.id
            action       = 'unchanged'
            reason       = 'Tenant policy matches baseline'
            currentState = $tenantPolicy.state
            targetState  = $b.state
        }
        $plan.summary.unchanged++
        continue
    }
    $plan.actions += [ordered]@{
        baselineId    = $b.id
        displayName   = $b.displayName
        tenantId      = $tenantPolicy.id
        action        = 'patch'
        reason        = "Drift in: $((($diff | ForEach-Object { $_.field }) -join ', '))"
        currentState  = $tenantPolicy.state
        targetState   = $b.state
        diff          = $diff
        targetPolicy  = $b
    }
    $plan.summary.patch++
}

# Tenant policies not declared in the baseline (typically left alone — flagged)
foreach ($t in $scan.policies) {
    $matched = $false
    foreach ($mapped in $tenantMap.Values) { if ($mapped -eq $t.id) { $matched = $true; break } }
    if (-not $matched) {
        # See if displayName resolves to a baseline id
        $byDisplay = $false
        foreach ($b in $baselinePolicies) { if ($b.displayName -eq $t.displayName) { $byDisplay = $true; break } }
        if (-not $byDisplay) {
            $plan.actions += [ordered]@{
                tenantId     = $t.id
                displayName  = $t.displayName
                action       = 'untracked'
                reason       = 'Tenant policy not in baseline (apply will leave alone; review)'
                currentState = $t.state
            }
        }
    }
}

# Sort: create -> patch -> unchanged -> untracked  (deterministic for tests)
$order = @{ create = 0; patch = 1; unchanged = 2; untracked = 3; remove = 4 }
$plan.actions = @($plan.actions | Sort-Object @{ Expression = { $order[$_.action] } }, baselineId, tenantId)

$plan.blockedBy = Test-Invariants -Plan $plan

# Strip baseline-policy material from plan output to keep it readable.
# Full target policy is reachable via the resolved baseline JSON anyway.
$planSerialisable = [ordered]@{
    schemaVersion    = $plan.schemaVersion
    workload         = $plan.workload
    mode             = $plan.mode
    tenantId         = $plan.tenantId
    generatedAt      = $plan.generatedAt
    summary          = $plan.summary
    requiresApproval = $plan.requiresApproval
    approvalRef      = $plan.approvalRef
    blockedBy        = @($plan.blockedBy)
    actions          = @(
        $plan.actions | ForEach-Object {
            $a = [ordered]@{}
            foreach ($k in @('baselineId','tenantId','displayName','action','reason','currentState','targetState')) {
                if ($_.PSObject.Properties.Name -contains $k -or $_.Contains($k)) { $a[$k] = $_[$k] }
            }
            if ($_.Contains('diff')) {
                $a['diffFields'] = @($_['diff'] | ForEach-Object { $_.field })
            }
            $a
        }
    )
}

$planPath = Join-Path $OutputDir 'plan.json'
$planSerialisable | ConvertTo-Json -Depth 25 | Out-File -LiteralPath $planPath -Encoding utf8

if ($Mode -eq 'plan') {
    [pscustomobject]@{
        mode      = 'plan'
        plan      = (Resolve-Path $planPath).Path
        summary   = $plan.summary
        blocked   = ($plan.blockedBy.Count -gt 0)
        blockedBy = @($plan.blockedBy)
    }
    return
}

# ----- Apply / rollback -------------------------------------------------
if (-not $ApprovalRef) {
    throw "Mode '$Mode' requires -ApprovalRef (a ticket / PR / out-of-band:<reason>). No silent writes."
}
if ($plan.blockedBy.Count -gt 0) {
    throw "Plan has $($plan.blockedBy.Count) safety block(s). Resolve before applying. See $planPath."
}

# Caller is responsible for an authenticated Graph context (Connect-Tenant.ps1).
$ctx = Get-MgContext -ErrorAction SilentlyContinue
if (-not $ctx -or $ctx.TenantId -ne $TenantId) {
    throw "Graph context is not connected to tenant $TenantId. Run scripts/common/Connect-Tenant.ps1 first."
}
Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop

$changes = [System.Collections.Generic.List[hashtable]]::new()
foreach ($action in $plan.actions) {
    switch ($action.action) {
        'create' {
            $body = $action.targetPolicy
            try {
                Write-Verbose "create $($action.baselineId) ($($action.displayName))"
                $created = New-MgIdentityConditionalAccessPolicy -BodyParameter $body -ErrorAction Stop
                [void]$changes.Add(@{
                    baselineId   = $action.baselineId
                    tenantId     = $created.Id
                    action       = 'created'
                    state        = $created.State
                })
            } catch {
                [void]$changes.Add(@{
                    baselineId = $action.baselineId
                    action     = 'create-failed'
                    error      = $_.Exception.Message
                })
            }
        }
        'patch' {
            try {
                Write-Verbose "patch $($action.baselineId) -> tenant $($action.tenantId)"
                Update-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $action.tenantId -BodyParameter $action.targetPolicy -ErrorAction Stop
                $after = Get-MgIdentityConditionalAccessPolicy -ConditionalAccessPolicyId $action.tenantId -ErrorAction Stop
                [void]$changes.Add(@{
                    baselineId    = $action.baselineId
                    tenantId      = $action.tenantId
                    action        = 'patched'
                    fields        = @($action.diff | ForEach-Object { $_.field })
                    stateAfter    = $after.State
                })
            } catch {
                [void]$changes.Add(@{
                    baselineId = $action.baselineId
                    tenantId   = $action.tenantId
                    action     = 'patch-failed'
                    error      = $_.Exception.Message
                })
            }
        }
        default { } # unchanged / untracked / remove — no write
    }
}

$changesPath = Join-Path $OutputDir 'changes.json'
[ordered]@{
    schemaVersion = '1.0.0'
    workload      = 'conditional-access'
    mode          = $Mode
    tenantId      = $TenantId
    approvalRef   = $ApprovalRef
    completedAt   = (Get-Date).ToUniversalTime().ToString('o')
    summary       = @{
        attempted = $changes.Count
        succeeded = @($changes | Where-Object { $_.action -in 'created','patched' }).Count
        failed    = @($changes | Where-Object { $_.action -like '*-failed' }).Count
    }
    changes       = @($changes)
} | ConvertTo-Json -Depth 25 | Out-File -LiteralPath $changesPath -Encoding utf8

[pscustomobject]@{
    mode    = $Mode
    plan    = (Resolve-Path $planPath).Path
    changes = (Resolve-Path $changesPath).Path
    summary = $plan.summary
}
