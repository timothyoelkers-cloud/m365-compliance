<#
.SYNOPSIS
    Read-only scan of Conditional Access policies, named locations, and authentication strength policies.
    Implements the read surface of m365-conditional-access agent.

.DESCRIPTION
    Emits normalised JSON of all CA policies with enough detail to diff against baseline. Also captures
    sign-in telemetry for the trailing 30 days so the portal can run what-if analysis downstream.

.PARAMETER TenantId
    Target tenant UUID. Graph session must be present via Connect-Tenant.ps1.

.PARAMETER OutputPath
    JSON artefact destination.

.PARAMETER SignInHistoryDays
    How many days of sign-in logs to include (default 30). 0 to skip.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputPath,
    [int]$SignInHistoryDays = 30
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$ctx = Get-MgContext -ErrorAction Stop
if ($ctx.TenantId -ne $TenantId) {
    throw "Graph context tenant ($($ctx.TenantId)) does not match -TenantId ($TenantId)."
}

Import-Module Microsoft.Graph.Identity.SignIns -ErrorAction Stop
Import-Module Microsoft.Graph.Reports          -ErrorAction Stop

function Normalise-CaPolicy {
    param($p)
    [ordered]@{
        id           = $p.Id
        displayName  = $p.DisplayName
        state        = $p.State
        createdDateTime = $p.CreatedDateTime
        modifiedDateTime = $p.ModifiedDateTime
        conditions   = [ordered]@{
            users = [ordered]@{
                includeUsers  = @($p.Conditions.Users.IncludeUsers)
                excludeUsers  = @($p.Conditions.Users.ExcludeUsers)
                includeGroups = @($p.Conditions.Users.IncludeGroups)
                excludeGroups = @($p.Conditions.Users.ExcludeGroups)
                includeRoles  = @($p.Conditions.Users.IncludeRoles)
                excludeRoles  = @($p.Conditions.Users.ExcludeRoles)
                includeGuestsOrExternalUsers = $p.Conditions.Users.IncludeGuestsOrExternalUsers
                excludeGuestsOrExternalUsers = $p.Conditions.Users.ExcludeGuestsOrExternalUsers
            }
            applications = [ordered]@{
                includeApplications = @($p.Conditions.Applications.IncludeApplications)
                excludeApplications = @($p.Conditions.Applications.ExcludeApplications)
                includeUserActions  = @($p.Conditions.Applications.IncludeUserActions)
            }
            clientAppTypes   = @($p.Conditions.ClientAppTypes)
            platforms        = [ordered]@{
                includePlatforms = @($p.Conditions.Platforms.IncludePlatforms)
                excludePlatforms = @($p.Conditions.Platforms.ExcludePlatforms)
            }
            locations        = [ordered]@{
                includeLocations = @($p.Conditions.Locations.IncludeLocations)
                excludeLocations = @($p.Conditions.Locations.ExcludeLocations)
            }
            signInRiskLevels = @($p.Conditions.SignInRiskLevels)
            userRiskLevels   = @($p.Conditions.UserRiskLevels)
            servicePrincipalRiskLevels = @($p.Conditions.ServicePrincipalRiskLevels)
        }
        grantControls    = [ordered]@{
            operator          = $p.GrantControls.Operator
            builtInControls   = @($p.GrantControls.BuiltInControls)
            customAuthenticationFactors = @($p.GrantControls.CustomAuthenticationFactors)
            termsOfUse        = @($p.GrantControls.TermsOfUse)
            authenticationStrengthId = $p.GrantControls.AuthenticationStrength.Id
        }
        sessionControls  = [ordered]@{
            applicationEnforcedRestrictions = $p.SessionControls.ApplicationEnforcedRestrictions
            cloudAppSecurity                = $p.SessionControls.CloudAppSecurity
            signInFrequency                 = $p.SessionControls.SignInFrequency
            persistentBrowser               = $p.SessionControls.PersistentBrowser
            continuousAccessEvaluation      = $p.SessionControls.ContinuousAccessEvaluation
        }
    }
}

$data = [ordered]@{
    schemaVersion = '1.0.0'
    tenantId      = $TenantId
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    producedBy    = 'Invoke-ConditionalAccessScan.ps1@1.0.0'
    policies      = @()
    namedLocations = @()
    authStrengthPolicies = @()
    signInSummary = $null
    invariants    = [ordered]@{
        breakGlassExcludedFromAllUserBlocking = $null
        noAllUsersBlockWithoutRisk            = $null
        anyInReportOnly                       = $null
    }
}

$data.policies = Get-MgIdentityConditionalAccessPolicy -All | ForEach-Object { Normalise-CaPolicy $_ }

$data.namedLocations = Get-MgIdentityConditionalAccessNamedLocation -All |
    Select-Object Id, DisplayName, CreatedDateTime, @{ N='type'; E={ $_.AdditionalProperties.'@odata.type' } }, AdditionalProperties

$data.authStrengthPolicies = Get-MgPolicyAuthenticationStrengthPolicy -All |
    Select-Object Id, DisplayName, Description, PolicyType, RequirementsSatisfied, AllowedCombinations

# Invariant: break-glass exclusion. Heuristic — looks for a group named like 'break-glass' or 'bg-ca'
$bg = Get-MgGroup -Filter "startswith(displayName,'grp-ca-break-glass') or startswith(displayName,'break-glass') or startswith(displayName,'bg-ca')" -ConsistencyLevel eventual -CountVariable bgcount -All
if ($bg) {
    $bgId = $bg[0].Id
    $blockingPolicies = $data.policies | Where-Object { $_.state -eq 'enabled' -and $_.grantControls.builtInControls -contains 'block' }
    $data.invariants.breakGlassExcludedFromAllUserBlocking = @(
        $blockingPolicies | ForEach-Object {
            [ordered]@{ policyId = $_.id; excluded = ($_.conditions.users.excludeGroups -contains $bgId) }
        }
    )
}

$data.invariants.anyInReportOnly = @(
    $data.policies | Where-Object { $_.state -eq 'enabledForReportingButNotEnforced' } | ForEach-Object { $_.id }
)

# Sign-in summary — last N days, for what-if downstream
if ($SignInHistoryDays -gt 0) {
    $since = (Get-Date).ToUniversalTime().AddDays(-$SignInHistoryDays).ToString('o')
    try {
        $signIns = Get-MgAuditLogSignIn -Filter "createdDateTime ge $since" -Top 1000 -ErrorAction Stop
        $data.signInSummary = [ordered]@{
            windowDays = $SignInHistoryDays
            sampleSize = $signIns.Count
            topFailureReasons = @($signIns | Where-Object { $_.Status.ErrorCode -ne 0 } |
                Group-Object { $_.Status.FailureReason } | Sort-Object Count -Descending | Select-Object -First 10 Name, Count)
            byClientApp  = @($signIns | Group-Object ClientAppUsed | ForEach-Object { @{ clientApp = $_.Name; count = $_.Count } })
            byConditionalAccessStatus = @($signIns | Group-Object ConditionalAccessStatus | ForEach-Object { @{ status = $_.Name; count = $_.Count } })
        }
    } catch {
        $data.signInSummary = @{ error = $_.Exception.Message }
    }
}

$json = $data | ConvertTo-Json -Depth 25
$json | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
