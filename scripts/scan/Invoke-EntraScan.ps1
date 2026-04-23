<#
.SYNOPSIS
    Read-only scan of Microsoft Entra ID configuration relevant to CIS v6 Section 1, 5.1, 5.2, 5.3.

.DESCRIPTION
    Emits a structured JSON object capturing the Entra state that the portal's diff engine compares
    against the target baseline. Does not write. Safe to run on a schedule.

    Covered:
      - Authorization policy (consent, app creation, guest role, tenant creation)
      - Authentication methods policy (FIDO2, WHfB, Authenticator, SMS/Voice, TAP, Email OTP)
      - Admin consent workflow
      - Directory role members for privileged roles
      - PIM role settings (where P2 licensed)
      - Access review definitions
      - Named locations
      - Authentication strength policies
      - Cross-tenant access defaults + partners
      - Admin account hygiene (cloud-only, shared-mailbox sign-in, dedicated admin accounts)

.PARAMETER TenantId
    Target tenant UUID. Must already be connected via Connect-Tenant.ps1 with the 'entra' workload.

.PARAMETER OutputPath
    File path for the JSON artefact. Parent directory must exist.

.OUTPUTS
    Writes JSON to OutputPath and returns the path.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$ctx = Get-MgContext -ErrorAction Stop
if ($ctx.TenantId -ne $TenantId) {
    throw "Graph context tenant ($($ctx.TenantId)) does not match -TenantId ($TenantId)."
}

Import-Module Microsoft.Graph.Identity.DirectoryManagement -ErrorAction Stop
Import-Module Microsoft.Graph.Identity.SignIns           -ErrorAction Stop
Import-Module Microsoft.Graph.Identity.Governance        -ErrorAction Stop
Import-Module Microsoft.Graph.Users                      -ErrorAction Stop

function Safe-Invoke {
    param([scriptblock]$Block,[string]$Label)
    try { & $Block }
    catch {
        Write-Warning "$Label failed: $($_.Exception.Message)"
        return $null
    }
}

$data = [ordered]@{
    schemaVersion      = '1.0.0'
    tenantId           = $TenantId
    capturedAt         = (Get-Date).ToUniversalTime().ToString('o')
    producedBy         = 'Invoke-EntraScan.ps1@1.0.0'
    authorizationPolicy = $null
    authMethodsPolicy   = $null
    adminConsentPolicy  = $null
    privilegedRoles     = @()
    pimRoleSettings     = @()
    accessReviews       = @()
    namedLocations      = @()
    authStrengths       = @()
    crossTenantAccess   = $null
    adminAccounts       = @{ count = 0; cloudOnly = 0; hybrid = 0 }
    sharedMailboxSignIn = @()
    featureLicences     = @{ entraP1 = $null; entraP2 = $null }
}

# Authorization policy
$data.authorizationPolicy = Safe-Invoke -Label "authorizationPolicy" -Block {
    $p = Get-MgPolicyAuthorizationPolicy
    [ordered]@{
        allowedToSignUpEmailBasedSubscriptions = $p.AllowedToSignUpEmailBasedSubscriptions
        allowedToUseSspr                       = $p.AllowedToUseSspr
        allowEmailVerifiedUsersToJoinOrganization = $p.AllowEmailVerifiedUsersToJoinOrganization
        allowInvitesFrom                       = $p.AllowInvitesFrom
        guestUserRoleId                        = $p.GuestUserRoleId
        defaultUserRolePermissions             = [ordered]@{
            allowedToCreateApps                = $p.DefaultUserRolePermissions.AllowedToCreateApps
            allowedToCreateSecurityGroups      = $p.DefaultUserRolePermissions.AllowedToCreateSecurityGroups
            allowedToCreateTenants             = $p.DefaultUserRolePermissions.AllowedToCreateTenants
            allowedToReadOtherUsers            = $p.DefaultUserRolePermissions.AllowedToReadOtherUsers
            permissionGrantPoliciesAssigned    = @($p.DefaultUserRolePermissions.PermissionGrantPoliciesAssigned)
        }
    }
}

# Authentication methods policy (one call per method config)
$data.authMethodsPolicy = Safe-Invoke -Label "authMethodsPolicy" -Block {
    $methods = 'Fido2','MicrosoftAuthenticator','WindowsHelloForBusiness','TemporaryAccessPass','Sms','Voice','Email','X509Certificate'
    $out = [ordered]@{}
    foreach ($m in $methods) {
        try {
            $cfg = Get-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId $m -ErrorAction Stop
            $out[$m] = [ordered]@{
                state = $cfg.State
                includeTargets = @($cfg.AdditionalProperties.includeTargets)
                excludeTargets = @($cfg.AdditionalProperties.excludeTargets)
                features = $cfg.AdditionalProperties
            }
        } catch { $out[$m] = @{ state = 'not-present-or-inaccessible' } }
    }
    $out
}

$data.adminConsentPolicy = Safe-Invoke -Label "adminConsentPolicy" -Block {
    $p = Get-MgPolicyAdminConsentRequestPolicy
    [ordered]@{
        isEnabled        = $p.IsEnabled
        notifyReviewers  = $p.NotifyReviewers
        remindersEnabled = $p.RemindersEnabled
        requestDurationInDays = $p.RequestDurationInDays
        reviewers        = @($p.Reviewers)
    }
}

# Privileged directory role members
$privRoles = 'Global Administrator','Privileged Role Administrator','Security Administrator','Conditional Access Administrator','Application Administrator','Authentication Administrator','Exchange Administrator','SharePoint Administrator','Teams Administrator','User Administrator'
$data.privilegedRoles = Safe-Invoke -Label "privilegedRoles" -Block {
    $allRoles = Get-MgDirectoryRole -All
    foreach ($name in $privRoles) {
        $role = $allRoles | Where-Object DisplayName -eq $name
        if (-not $role) { continue }
        $members = Get-MgDirectoryRoleMember -DirectoryRoleId $role.Id -All
        [pscustomobject]@{
            role     = $name
            roleId   = $role.Id
            memberCount = $members.Count
            memberIds = @($members | ForEach-Object { $_.Id })
        }
    }
}

# PIM role settings (P2 only — will fail gracefully without P2)
$data.pimRoleSettings = Safe-Invoke -Label "pimRoleSettings" -Block {
    Get-MgPolicyRoleManagementPolicyAssignment -Filter "scopeId eq '/' and scopeType eq 'DirectoryRole'" -All | ForEach-Object {
        $policy = Get-MgPolicyRoleManagementPolicy -UnifiedRoleManagementPolicyId $_.PolicyId
        $rules  = Get-MgPolicyRoleManagementPolicyRule -UnifiedRoleManagementPolicyId $_.PolicyId
        [pscustomobject]@{
            roleDefinitionId = $_.RoleDefinitionId
            policyId         = $_.PolicyId
            displayName      = $policy.DisplayName
            rules            = @($rules | Select-Object Id, @{ N='type';E={ $_.AdditionalProperties.'@odata.type' } }, AdditionalProperties)
        }
    }
}

$data.accessReviews = Safe-Invoke -Label "accessReviews" -Block {
    Get-MgIdentityGovernanceAccessReviewDefinition -All | Select-Object Id, DisplayName, Status, @{ N='scope'; E = { $_.Scope.AdditionalProperties } }
}

$data.namedLocations = Safe-Invoke -Label "namedLocations" -Block {
    Get-MgIdentityConditionalAccessNamedLocation -All | Select-Object Id, DisplayName, @{ N='type'; E={ $_.AdditionalProperties.'@odata.type' } }, AdditionalProperties
}

$data.authStrengths = Safe-Invoke -Label "authStrengths" -Block {
    Get-MgPolicyAuthenticationStrengthPolicy -All | Select-Object Id, DisplayName, PolicyType, RequirementsSatisfied, AllowedCombinations
}

$data.crossTenantAccess = Safe-Invoke -Label "crossTenantAccess" -Block {
    $default = Get-MgPolicyCrossTenantAccessPolicyDefault
    $partners = Get-MgPolicyCrossTenantAccessPolicyPartner -All
    [ordered]@{
        default  = $default
        partners = @($partners)
    }
}

# Admin account hygiene
$data.adminAccounts = Safe-Invoke -Label "adminAccounts" -Block {
    $gaRole = (Get-MgDirectoryRole -All | Where-Object DisplayName -eq 'Global Administrator')
    if (-not $gaRole) { return @{ count = 0 } }
    $members = Get-MgDirectoryRoleMember -DirectoryRoleId $gaRole.Id -All
    $userMembers = foreach ($m in $members) {
        try { Get-MgUser -UserId $m.Id -Property Id,UserPrincipalName,OnPremisesSyncEnabled,AccountEnabled,UserType,AssignedLicenses -ErrorAction Stop }
        catch { $null }
    } | Where-Object { $_ }
    [ordered]@{
        count     = $userMembers.Count
        cloudOnly = @($userMembers | Where-Object { -not $_.OnPremisesSyncEnabled }).Count
        hybrid    = @($userMembers | Where-Object { $_.OnPremisesSyncEnabled }).Count
        upns      = @($userMembers | ForEach-Object { $_.UserPrincipalName })
    }
}

$data.sharedMailboxSignIn = Safe-Invoke -Label "sharedMailboxSignIn" -Block {
    # Shared mailboxes where sign-in is not blocked (best-effort — requires ExchangeOnline session; if absent, skip)
    if (Get-Command Get-Mailbox -ErrorAction SilentlyContinue) {
        Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -ErrorAction SilentlyContinue |
            ForEach-Object {
                $u = Get-MgUser -UserId $_.ExternalDirectoryObjectId -Property AccountEnabled -ErrorAction SilentlyContinue
                if ($u -and $u.AccountEnabled) {
                    [pscustomobject]@{ upn = $_.UserPrincipalName; accountEnabled = $true }
                }
            }
    }
}

# Licence snapshot (helps downstream diff understand feature availability)
$data.featureLicences = Safe-Invoke -Label "featureLicences" -Block {
    $skus = Get-MgSubscribedSku -All
    [ordered]@{
        entraP1 = [bool]($skus | Where-Object { $_.ServicePlans.ServicePlanName -contains 'AAD_PREMIUM' })
        entraP2 = [bool]($skus | Where-Object { $_.ServicePlans.ServicePlanName -contains 'AAD_PREMIUM_P2' })
        hasE5   = [bool]($skus | Where-Object { $_.SkuPartNumber -match 'ENTERPRISEPREMIUM' -or $_.SkuPartNumber -match 'SPE_E5' })
    }
}

$json = $data | ConvertTo-Json -Depth 20
$json | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
