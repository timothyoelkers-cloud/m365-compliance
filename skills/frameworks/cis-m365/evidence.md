# CIS M365 Benchmark — Evidence

Auditors and internal reviewers accept CIS compliance evidence in different forms. This file records what they ask for and where in M365 it actually lives.

## Evidence types

| Evidence type | Source | Collection method |
|---|---|---|
| Current policy JSON | Graph API | `GET` the resource; save to evidence store with timestamp + tenant ID |
| Tenant config export | Microsoft 365 DSC / IdPowerToys / custom | Scheduled export, stored with hash |
| Unified Audit Log search | Purview Audit | KQL query against `AuditLog` workload |
| Sign-in logs | Entra ID → Monitoring → Sign-in logs | Graph `auditLogs/signIns`, retain 30d free / 1–2y P2 |
| Conditional Access gap analysis | CA → What If / Insights & Reporting | Screenshot + JSON of policies |
| Defender secure score history | Defender portal → Secure Score | API: `/security/secureScores` with history |

## Evidence per workload

### Entra ID

- Identity security defaults policy: `GET /policies/identitySecurityDefaultsEnforcementPolicy`
- Authorization policy (user consent): `GET /policies/authorizationPolicy`
- Authentication methods policy: `GET /policies/authenticationMethodsPolicy`
- All CA policies: `GET /identity/conditionalAccess/policies`
- Sign-in logs (for proving policies enforce): `GET /auditLogs/signIns`

### Exchange Online

- Anti-phish, anti-malware, anti-spam, safe-links, safe-attachments policies: `Get-EOPProtectionPolicyRule`, `Get-AntiPhishPolicy`, etc.
- Mailbox audit config: `Get-Mailbox | Select AuditEnabled, AuditLogAgeLimit, AuditOwner, AuditDelegate, AuditAdmin`
- Accepted domains / remote domains for external handling.

### SharePoint / OneDrive

- Tenant sharing capability: `Get-SPOTenant | Select SharingCapability, DefaultSharingLinkType, RequireAnonymousLinksExpireInDays`
- Sensitivity label policies: `Get-Label`, `Get-LabelPolicy`
- Site-level overrides: enumerate via `Get-SPOSite` for sensitive sites.

### Teams

- Meeting, messaging, app permission policies: `Get-CsTeamsMeetingPolicy`, `Get-CsTeamsMessagingPolicy`, `Get-CsTeamsAppPermissionPolicy`.
- Federation config: `Get-CsTenantFederationConfiguration`.

### Defender

- Secure Score: `/security/secureScores` with history.
- ASR rules (requires Intune/Defender): Intune endpoint security → ASR reporting.
- Alert policies: `Get-ProtectionAlert`.

### Purview

- Unified Audit Log state: `Get-AdminAuditLogConfig | Select UnifiedAuditLogIngestionEnabled`
- DLP policies: `Get-DlpCompliancePolicy`, `Get-DlpComplianceRule`.
- Retention policies: `Get-RetentionCompliancePolicy`, `Get-RetentionComplianceRule`.

### Intune

- Device compliance policies: Graph `/deviceManagement/deviceCompliancePolicies`.
- Configuration profiles: Graph `/deviceManagement/deviceConfigurations`.
- App protection policies: Graph `/deviceAppManagement/managedAppPolicies`.

## Evidence cadence

| Cadence | What |
|---|---|
| On change | Policy JSON snapshots (via CI on baseline repo, diff against live) |
| Daily | Drift check report — current vs. baseline |
| Weekly | Secure Score trend, top regressions |
| Monthly | Full evidence bundle per tenant (zipped JSON exports + audit log extract) |
| On audit | Package tailored to the asking framework — see [../../mapping/control-map/SKILL.md](../../mapping/control-map/SKILL.md) for cross-framework packaging. |

## Evidence store layout suggestion

```
evidence/
  <tenant-id>/
    <yyyy-mm-dd>/
      entra/
        policies.authorizationPolicy.json
        policies.identitySecurityDefaults.json
        conditionalAccess.policies.json
      exchange/
        ...
      bundle.sha256
```

One tenant, one date, hashes at bundle level for tamper evidence. Retain minimum 7 years for regulated tenants.
