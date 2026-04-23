# CIS M365 Benchmark — M365 Implementation Translation (v6.0.1 draft)

> Draft ID references track the draft catalogue in [controls.md](controls.md). Verify against the CIS Workbench v6.0.1 PDF before operational use.

For every recommendation, this file records the canonical way to read current state and remediate.

## Block format

```markdown
### <Rec ID> — <short title>
**Profile:** L1|L2
**Workload:** Entra|Exchange|SharePoint|OneDrive|Teams|PowerBI
**Auth:** delegated|app-only|partner-center
**Graph scopes / RBAC:** <list>

**Read current state:**
```powershell
...
```

**Remediate (idempotent):**
```powershell
...
```

**Expected end state / JSON fragment:**
```json
{ ... }
```

**Notes:** licence dependencies, tenant-class caveats, known drift sources.
```

---

## Entra ID

### 1.1.1 — Disable Security Defaults (only after CA baseline is in place)

**Profile:** L1 **Workload:** Entra **Auth:** delegated (Global Admin) or app-only
**Graph scopes:** `Policy.ReadWrite.ConditionalAccess`

```powershell
# Read
Connect-MgGraph -Scopes "Policy.Read.All"
Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy | Select-Object IsEnabled

# Remediate (idempotent)
$current = Get-MgPolicyIdentitySecurityDefaultEnforcementPolicy
if ($current.IsEnabled -ne $false) {
    Update-MgPolicyIdentitySecurityDefaultEnforcementPolicy -IsEnabled:$false
}
```

```json
{ "isEnabled": false }
```

**Notes:** this is a *last step* after the CA baseline (policies 1.5.*) is deployed and piloted. Applying it without CA in place removes MFA from users.

---

### 1.1.5 — Restrict non-admin users from creating tenants

**Profile:** L1 **Workload:** Entra
**Graph scopes:** `Policy.ReadWrite.Authorization`

```powershell
$policy = Get-MgPolicyAuthorizationPolicy
if ($policy.DefaultUserRolePermissions.AllowedToCreateTenants -ne $false) {
    Update-MgPolicyAuthorizationPolicy -DefaultUserRolePermissions @{ AllowedToCreateTenants = $false }
}
```

---

### 1.2.2 — Authenticator: number match + geo context

**Profile:** L1 **Workload:** Entra
**Graph scopes:** `Policy.ReadWrite.AuthenticationMethod`

```powershell
$method = Get-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration -AuthenticationMethodConfigurationId MicrosoftAuthenticator
# Verify featureSettings.numberMatchingRequiredState.state and displayAppInformationRequiredState are 'enabled' for 'allUsers'
```

Remediation: construct the `featureSettings` PATCH body and update.

**Notes:** ensure no users are still on SMS/voice before enforcing, to avoid lockout.

---

### 1.2.3 — Enable FIDO2 authentication methods

**Profile:** L1 **Workload:** Entra

```powershell
Update-MgPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration `
  -AuthenticationMethodConfigurationId Fido2 `
  -BodyParameter @{
      state = "enabled"
      includeTargets = @(@{ id = "all_users"; targetType = "group" })
      isSoftwareKeyEnforced = $false
      isAttestationEnforced = $true
  }
```

---

### 1.3.1 — Restrict user consent to apps

**Profile:** L1 **Workload:** Entra
**Graph scopes:** `Policy.ReadWrite.Authorization`

Two accepted postures:
- `permissionGrantPoliciesAssigned = []` (no user consent)
- `permissionGrantPoliciesAssigned = ["ManagePermissionGrantsForSelf.microsoft-user-default-low"]` (low-risk verified publishers only)

```powershell
$policy = Get-MgPolicyAuthorizationPolicy
$desired = @("ManagePermissionGrantsForSelf.microsoft-user-default-low")
if (($policy.DefaultUserRolePermissions.PermissionGrantPoliciesAssigned -join ",") -ne ($desired -join ",")) {
    Update-MgPolicyAuthorizationPolicy -DefaultUserRolePermissions @{ PermissionGrantPoliciesAssigned = $desired }
}
```

---

### 1.3.2 — Enable admin consent workflow

**Profile:** L1 **Workload:** Entra

```powershell
Update-MgPolicyAdminConsentRequestPolicy -BodyParameter @{
    isEnabled = $true
    notifyReviewers = $true
    remindersEnabled = $true
    requestDurationInDays = 30
    reviewers = @(@{ query = "/groups/<approvers-group-id>/members"; queryType = "MicrosoftGraph"; queryRoot = $null })
}
```

---

### 1.3.4 — Users cannot register applications

```powershell
$policy = Get-MgPolicyAuthorizationPolicy
if ($policy.DefaultUserRolePermissions.AllowedToCreateApps -ne $false) {
    Update-MgPolicyAuthorizationPolicy -DefaultUserRolePermissions @{ AllowedToCreateApps = $false }
}
```

---

### 1.4.1 — Global Admin count between 2 and 4

**Profile:** L1 — informational check (not a setting to write)

```powershell
$ga = Get-MgDirectoryRole | Where-Object DisplayName -eq "Global Administrator"
$members = Get-MgDirectoryRoleMember -DirectoryRoleId $ga.Id
$count = $members.Count
# Emit warning if <2 or >4
```

---

### 1.4.3–1.4.7 — PIM for privileged roles

**Profile:** L1 (baseline) / L2 (stricter activation)
**Prereq:** Entra ID P2

Read via Graph `/roleManagement/directory/roleAssignmentSchedulePolicies`.

Each privileged role should have:
- Max activation duration ≤ 2h (1.4.6)
- MFA on activation (1.4.4)
- Justification required (1.4.4)
- Approval required (1.4.5, L2)

Remediation uses `New-MgRoleManagementDirectoryRoleAssignmentSchedulePolicy` to set `rules` covering the above.

---

### 1.5.1 — Block legacy authentication (CA)

Handled by the `m365-conditional-access` agent. Baseline stanza:

```yaml
- id: cis-l1-ca-001-block-legacy-auth
  state: enabled
  conditions:
    users: { include: ["All"], exclude_groups: ["grp-ca-break-glass"] }
    applications: { include: ["All"] }
    clientAppTypes: ["exchangeActiveSync", "other"]
  grantControls: { operator: OR, builtInControls: ["block"] }
```

---

### 1.5.2 — Require MFA for all users (CA)

```yaml
- id: cis-l1-ca-002-mfa-all-users
  state: enabled
  conditions:
    users: { include: ["All"], exclude_groups: ["grp-ca-break-glass"] }
    applications: { include: ["All"] }
    clientAppTypes: ["all"]
  grantControls:
    operator: AND
    authenticationStrength: phishing-resistant-mfa
```

---

### 1.5.3 — Phishing-resistant MFA for admins

```yaml
- id: cis-l1-ca-003-admin-mfa-phishing-resistant
  state: enabled
  conditions:
    users:
      include_roles: [Global Administrator, Privileged Role Administrator, User Administrator, SharePoint Administrator, Exchange Administrator, Conditional Access Administrator, Security Administrator, Helpdesk Administrator, Billing Administrator, Application Administrator, Authentication Administrator]
      exclude_groups: [grp-ca-break-glass]
    applications: { include: ["All"] }
  grantControls:
    operator: AND
    authenticationStrength: phishing-resistant-mfa
```

---

### 1.5.5 / 1.5.6 — Identity Protection risk-based CA

```yaml
- id: cis-l1-ca-005-block-high-signin-risk
  state: enabled
  conditions:
    users: { include: ["All"], exclude_groups: [grp-ca-break-glass] }
    applications: { include: ["All"] }
    signInRiskLevels: ["high"]
  grantControls: { operator: OR, builtInControls: ["block"] }
- id: cis-l1-ca-006-password-change-high-user-risk
  state: enabled
  conditions:
    users: { include: ["All"], exclude_groups: [grp-ca-break-glass] }
    applications: { include: ["All"] }
    userRiskLevels: ["high"]
  grantControls:
    operator: AND
    builtInControls: ["passwordChange", "mfa"]
```

Licence: P2 required.

---

### 1.6.1 — Break-glass exclusion in every user-blocking CA policy

Enforced as an invariant by the `m365-conditional-access` agent — it refuses to apply a user-blocking policy that does not exclude `grp-ca-break-glass`.

---

## Exchange Online

### 2.1.1 — Disable SMTP AUTH tenant-wide

```powershell
Connect-ExchangeOnline -Organization <tenant>
$c = Get-TransportConfig | Select SmtpClientAuthenticationDisabled
if (-not $c.SmtpClientAuthenticationDisabled) {
    Set-TransportConfig -SmtpClientAuthenticationDisabled $true
}
```

Per-mailbox overrides: `Get-CASMailbox -Filter 'SmtpClientAuthenticationDisabled -eq $null'` — enumerate and set explicitly where overridden.

---

### 2.1.4 — Disable POP3 and IMAP4

```powershell
# Tenant default mailbox plans
Get-CASMailboxPlan | ForEach-Object { Set-CASMailboxPlan -Identity $_.Identity -PopEnabled $false -ImapEnabled $false }
# Existing mailboxes
Get-CASMailbox -ResultSize Unlimited -Filter { PopEnabled -eq $true -or ImapEnabled -eq $true } | ForEach-Object {
    Set-CASMailbox -Identity $_.Identity -PopEnabled $false -ImapEnabled $false
}
```

---

### 2.2.1–2.2.4 — Preset Strict protection policies

Defender for O365 Preset Security Policies are the cleanest path. Apply to "All users" using Preset Strict.

```powershell
# Preset Strict rule state
Get-EOPProtectionPolicyRule -State Enabled
Get-ATPProtectionPolicyRule -State Enabled
# If the preset is not applied to all users, update the rule's SentTo / RecipientDomainIs to include everyone
```

Notes: preset policies hide the underlying anti-phish/safe-links/safe-attachments/anti-spam policies, making drift detection simpler.

---

### 2.3.2 — DKIM enabled per domain

```powershell
Get-AcceptedDomain | ForEach-Object {
    $dkim = Get-DkimSigningConfig -Identity $_.DomainName -ErrorAction SilentlyContinue
    if (-not $dkim) { New-DkimSigningConfig -DomainName $_.DomainName -Enabled $true }
    elseif (-not $dkim.Enabled) { Set-DkimSigningConfig -Identity $_.DomainName -Enabled $true }
}
```

Verify DKIM selectors exist in external DNS.

---

### 2.4.2 — Forwarding to external recipients blocked by default

```powershell
Get-HostedOutboundSpamFilterPolicy -Identity Default | Select AutoForwardingMode
if ((Get-HostedOutboundSpamFilterPolicy -Identity Default).AutoForwardingMode -ne "Off") {
    Set-HostedOutboundSpamFilterPolicy -Identity Default -AutoForwardingMode Off
}
```

Carve-outs handled via a *specific* outbound spam policy scoped to a documented group.

---

### 2.6.1 — Mailbox auditing on tenant-wide

```powershell
$c = Get-OrganizationConfig | Select AuditDisabled
if ($c.AuditDisabled) { Set-OrganizationConfig -AuditDisabled $false }
```

---

## SharePoint Online

### 3.1.1 — SharingCapability

```powershell
Connect-SPOService -Url https://<tenant>-admin.sharepoint.com
$t = Get-SPOTenant
# Desired: ExternalUserSharingOnly (guests allowed, no anonymous)
if ($t.SharingCapability -ne "ExternalUserSharingOnly") {
    Set-SPOTenant -SharingCapability ExternalUserSharingOnly
}
```

L2 tenants may tighten to `ExistingExternalUserSharingOnly` (requires existing guest relationship).

---

### 3.1.2 — Anonymous link expiry ≤ 30 days

```powershell
if ((Get-SPOTenant).RequireAnonymousLinksExpireInDays -gt 30 -or (Get-SPOTenant).RequireAnonymousLinksExpireInDays -eq 0) {
    Set-SPOTenant -RequireAnonymousLinksExpireInDays 30
}
```

---

### 3.1.3 / 3.1.4 — Default link type and permission

```powershell
Set-SPOTenant -DefaultSharingLinkType Direct
Set-SPOTenant -DefaultLinkPermission View
```

---

## OneDrive for Business

### 4.1.3 — OneDrive sync restricted to managed/compliant devices

```powershell
# Tenant restriction for Entra-joined devices
Set-SPOTenantSyncClientRestriction -Enable -DomainGuids "<tenant-domain-guid>" -BlockMacSync:$false
```

---

### 4.2.1 — OneDrive retention after user removal

```powershell
if ((Get-SPOTenant).OrphanedPersonalSitesRetentionPeriod -lt 30) {
    Set-SPOTenant -OrphanedPersonalSitesRetentionPeriod 30
}
```

---

## Microsoft Teams

### 5.1.1 — Federation allow-list

```powershell
Connect-MicrosoftTeams
$cfg = Get-CsTenantFederationConfiguration
$allow = New-CsEdgeAllowList -AllowedDomain @("partner1.com","partner2.com")
Set-CsTenantFederationConfiguration -AllowedDomains $allow -AllowFederatedUsers $true
```

---

### 5.2.1 / 5.2.2 — Anonymous & lobby

```powershell
Set-CsTeamsMeetingPolicy -Identity Global `
    -AllowAnonymousUsersToJoinMeeting $false `
    -AutoAdmittedUsers "EveryoneInCompanyExcludingGuests" `
    -AllowPSTNUsersToBypassLobby $false
```

---

### 5.4.1 — App permission allow-list

```powershell
# Global = strictest; use per-policy-assignment for teams that need broader apps
Set-CsTeamsAppPermissionPolicy -Identity Global `
    -DefaultCatalogApps @() `
    -GlobalCatalogApps @() `
    -PrivateCatalogApps @() `
    -DefaultCatalogAppsType BlockedAppList `
    -GlobalCatalogAppsType BlockedAppList
```

---

## Power BI

### 6.1.1 — Workspace creation restricted

Power BI tenant settings are configured through the admin portal or via the Power BI REST Admin APIs:

```http
POST https://api.powerbi.com/v1.0/myorg/admin/tenantsettings/{settingName}
```

Key settings to target:
- `CreateWorkspaces` → restricted to specific group
- `PublishToWeb` → disabled
- `ExportDataToExcel` → restricted on sensitive workspace groups
- `ShareContentWithExternalUsers` → disabled or restricted
- `AuditLogs` → enabled
- `ServicePrincipalAccess` → specific group

Evidence: snapshot tenant settings JSON via Admin API `GET /admin/tenantsettings`.

---

## Unified Audit Log (cross-cutting)

### 0.1 — UAL ingestion enabled

```powershell
Connect-ExchangeOnline
$c = Get-AdminAuditLogConfig
if (-not $c.UnifiedAuditLogIngestionEnabled) {
    Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true
}
```

Wait time for logs to start flowing: up to 24 hours after enabling.

---

## Open items

- Populate remaining Entra rows (1.7.*, 1.8.*, 1.9.*) with PowerShell once verified against v6.0.1.
- Add Power BI Admin API bearer-token issuance pattern (service principal with Power BI admin).
- Add evidence-artefact filenames so the `m365-tenant-baseline` orchestrator can write them consistently.
