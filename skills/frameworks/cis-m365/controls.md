# CIS M365 Benchmark — Control Catalogue (v6.0.1)

> **Benchmark version:** v6.0.1 (CIS released v6.0.0 on 31 October 2025; v6.0.1 patched shortly after).
> **Control IDs / titles source:** the open-source [Maester](https://maester.dev/docs/tests/cis/) project's CIS test library, which tracks the current CIS M365 PDF. Cross-check against the authoritative CIS Workbench PDF before customer-facing audit work.
> **Last reviewed:** 2026-04-22.

The catalogue follows the benchmark's native section structure (which is by capability, not by service — see [SKILL.md](SKILL.md)).

## Section 1 — Administrative Accounts, Groups, User Policies

### 1.1 Administrative Accounts

| ID | Profile | Title |
|---|---|---|
| 1.1.1 | L1 | Ensure Administrative accounts are cloud-only |
| 1.1.2 | L1 | Ensure two emergency access accounts have been defined |
| 1.1.3 | L1 | Ensure that between two and four global admins are designated |
| 1.1.4 | L1 | Ensure administrative accounts use licenses with a reduced application footprint |

### 1.2 Groups & Shared Resources

| ID | Profile | Title |
|---|---|---|
| 1.2.1 | L2 | Ensure that only organizationally managed/approved public groups exist |
| 1.2.2 | L1 | Ensure sign-in to shared mailboxes is blocked |

### 1.3 User & Service Policies

| ID | Profile | Title |
|---|---|---|
| 1.3.1 | L1 | Ensure the 'Password expiration policy' is set to 'Set passwords to never expire' |
| 1.3.2 | L1 | Ensure 'Idle session timeout' is set to '3 hours (or less)' for unmanaged devices |
| 1.3.3 | L2 | Ensure 'External sharing' of calendars is not available |
| 1.3.4 | L1 | Ensure 'User owned apps and services' is restricted |
| 1.3.5 | L1 | Ensure internal phishing protection for Forms is enabled |
| 1.3.6 | L2 | Ensure the customer lockbox feature is enabled |
| 1.3.7 | L2 | Ensure 'third-party storage services' are restricted in 'Microsoft 365 on the web' |
| 1.3.8 | L2 | Ensure that Sways cannot be shared with people outside of your organization |
| 1.3.9 | L1 | Ensure shared bookings pages are restricted to select users |

## Section 2 — Exchange Online & Threat Protection

### 2.1 Email Security

| ID | Profile | Title |
|---|---|---|
| 2.1.1  | L2 | Ensure Safe Links for Office Applications is Enabled |
| 2.1.2  | L1 | Ensure the Common Attachment Types Filter is enabled |
| 2.1.3  | L1 | Ensure notifications for internal users sending malware is Enabled |
| 2.1.4  | L2 | Ensure Safe Attachments policy is enabled |
| 2.1.5  | L2 | Ensure Safe Attachments for SharePoint, OneDrive, and Teams is Enabled |
| 2.1.6  | L1 | Ensure Exchange Online Spam Policies are set to notify administrators |
| 2.1.7  | L1 | Ensure that an anti-phishing policy has been created |
| 2.1.8  | L1 | Ensure that SPF records are published for all Exchange Domains |
| 2.1.9  | L1 | Ensure that DKIM is enabled for all Exchange Online Domains |
| 2.1.10 | L1 | Ensure DMARC Records for all Exchange Online domains are published |
| 2.1.11 | L2 | Ensure comprehensive attachment filtering is applied |
| 2.1.12 | L1 | Ensure the connection filter IP allow list is not used |
| 2.1.13 | L1 | Ensure the connection filter safe list is off |
| 2.1.14 | L1 | Ensure inbound anti-spam policies do not contain allowed domains |
| 2.1.15 | L1 | Ensure outbound anti-spam message limits are in place |

### 2.2 Monitoring

| ID | Profile | Title |
|---|---|---|
| 2.2.1 | L1 | Ensure emergency access account activity is monitored |

### 2.4 Advanced Protection

| ID | Profile | Title |
|---|---|---|
| 2.4.1 | L1 | Ensure Priority account protection is enabled and configured |
| 2.4.2 | L1 | Ensure Priority accounts have 'Strict protection' presets applied |
| 2.4.3 | L2 | Ensure Microsoft Defender for Cloud Apps is enabled and configured |
| 2.4.4 | L1 | Ensure Zero-hour auto purge for Microsoft Teams is on |

## Section 3 — Data Protection & Governance

### 3.1 Audit & Logging

| ID | Profile | Title |
|---|---|---|
| 3.1.1 | L1 | Ensure Microsoft 365 audit log search is Enabled |

### 3.2 Data Loss Prevention

| ID | Profile | Title |
|---|---|---|
| 3.2.1 | L1 | Ensure DLP policies are enabled |
| 3.2.2 | L1 | Ensure DLP policies are enabled for Microsoft Teams |

### 3.3 Information Protection

| ID | Profile | Title |
|---|---|---|
| 3.3.1 | L1 | Ensure Information Protection sensitivity label policies are published |

## Section 4 — Device Compliance

| ID | Profile | Title |
|---|---|---|
| 4.1 | L2 | Ensure devices without a compliance policy are marked 'not compliant' |
| 4.2 | L2 | Ensure device enrollment for personally owned devices is blocked by default |

## Section 5 — Application & Access Control

### 5.1 Application Policies

#### 5.1.2 Tenant Policies

| ID | Profile | Title |
|---|---|---|
| 5.1.2.1 | L1 | Ensure 'Per-user MFA' is disabled (replaced by CA-based MFA) |
| 5.1.2.2 | L2 | Ensure third party integrated applications are not allowed |
| 5.1.2.3 | L1 | Ensure 'Restrict non-admin users from creating tenants' is set to 'Yes' |
| 5.1.2.4 | L1 | Ensure access to the Entra admin center is restricted |
| 5.1.2.5 | L2 | Ensure the option to remain signed in is hidden |
| 5.1.2.6 | L2 | Ensure 'LinkedIn account connections' is disabled |

#### 5.1.3 Group Management

| ID | Profile | Title |
|---|---|---|
| 5.1.3.1 | L1 | Ensure a dynamic group for guest users is created |
| 5.1.3.2 | L1 | Ensure users cannot create security groups |

#### 5.1.4 Device Join & Management

| ID | Profile | Title |
|---|---|---|
| 5.1.4.1 | L2 | Ensure the ability to join devices to Entra is restricted |
| 5.1.4.2 | L1 | Ensure the maximum number of devices per user is limited |
| 5.1.4.3 | L1 | Ensure the GA role is not added as a local administrator during Entra join |
| 5.1.4.4 | L1 | Ensure local administrator assignment is limited during Entra join |
| 5.1.4.5 | L1 | Ensure Local Administrator Password Solution is enabled |
| 5.1.4.6 | L2 | Ensure users are restricted from recovering BitLocker keys |

#### 5.1.5 Application Consent

| ID | Profile | Title |
|---|---|---|
| 5.1.5.1 | L2 | Ensure user consent to apps accessing company data on their behalf is not allowed |
| 5.1.5.2 | L1 | Ensure the admin consent workflow is enabled |

#### 5.1.6 Guest & External Access

| ID | Profile | Title |
|---|---|---|
| 5.1.6.1 | L2 | Ensure that collaboration invitations are sent to allowed domains only |
| 5.1.6.2 | L1 | Ensure that guest user access is restricted |
| 5.1.6.3 | L2 | Ensure guest user invitations are limited to the Guest Inviter role |

#### 5.1.8 Hybrid Deployment

| ID | Profile | Title |
|---|---|---|
| 5.1.8.1 | L1 | Ensure that password hash sync is enabled for hybrid deployments |

### 5.2 Authentication & Authorization

#### 5.2.2 Conditional Access & Identity Protection

| ID | Profile | Title |
|---|---|---|
| 5.2.2.1  | L1 | Ensure multifactor authentication is enabled for all users in administrative roles |
| 5.2.2.2  | L1 | Ensure multifactor authentication is enabled for all users |
| 5.2.2.3  | L1 | Enable Conditional Access policies to block legacy authentication |
| 5.2.2.4  | L1 | Ensure Sign-in frequency is enabled and browser sessions are not persistent for Administrative users |
| 5.2.2.5  | L2 | Ensure 'Phishing-resistant MFA strength' is required for Administrators |
| 5.2.2.6  | L1 | Enable Identity Protection user risk policies |
| 5.2.2.7  | L1 | Enable Identity Protection sign-in risk policies |
| 5.2.2.8  | L2 | Ensure 'sign-in risk' is blocked for medium and high risk |
| 5.2.2.9  | L1 | Ensure a managed device is required for authentication |
| 5.2.2.10 | L1 | Ensure a managed device is required for MFA registration |
| 5.2.2.11 | L1 | Ensure sign-in frequency for Intune Enrollment is set to 'Every time' |
| 5.2.2.12 | L1 | Ensure the device code sign-in flow is blocked |

#### 5.2.3 Authentication Methods

| ID | Profile | Title |
|---|---|---|
| 5.2.3.1 | L1 | Ensure Microsoft Authenticator is configured to protect against MFA fatigue |
| 5.2.3.2 | L1 | Ensure custom banned passwords lists are used |
| 5.2.3.3 | L1 | Ensure password protection is enabled for on-prem Active Directory |
| 5.2.3.4 | L1 | Ensure all member users are 'MFA capable' |
| 5.2.3.5 | L1 | Ensure weak authentication methods are disabled |
| 5.2.3.6 | L1 | Ensure system-preferred multifactor authentication is enabled |
| 5.2.3.7 | L2 | Ensure the email OTP authentication method is disabled |

#### 5.2.4 Self-Service Password Reset

| ID | Profile | Title |
|---|---|---|
| 5.2.4.1 | L1 | Ensure 'Self service password reset enabled' is set to 'All' |

### 5.3 Privileged Identity Management

| ID | Profile | Title |
|---|---|---|
| 5.3.1 | L2 | Ensure 'Privileged Identity Management' is used to manage roles |
| 5.3.2 | L1 | Ensure 'Access reviews' for Guest Users are configured |
| 5.3.3 | L1 | Ensure 'Access reviews' for privileged roles are configured |
| 5.3.4 | L1 | Ensure approval is required for Global Administrator role activation |
| 5.3.5 | L1 | Ensure approval is required for Privileged Role Administrator activation |

## Section 6 — Mail Management

### 6.1 Mailbox Auditing

| ID | Profile | Title |
|---|---|---|
| 6.1.1 | L1 | Ensure 'AuditDisabled' organizationally is set to 'False' |
| 6.1.2 | L1 | Ensure mailbox audit actions are configured |
| 6.1.3 | L1 | Ensure 'AuditBypassEnabled' is not enabled on mailboxes |

### 6.2 Mail Flow Rules

| ID | Profile | Title |
|---|---|---|
| 6.2.1 | L1 | Ensure all forms of mail forwarding are blocked and/or disabled |
| 6.2.2 | L1 | Ensure mail transport rules do not whitelist specific domains |
| 6.2.3 | L1 | Ensure email from external senders is identified |

### 6.3 Outlook Add-ins

| ID | Profile | Title |
|---|---|---|
| 6.3.1 | L2 | Ensure users installing Outlook add-ins is not allowed |

### 6.5 Modern Authentication & Client Settings

| ID | Profile | Title |
|---|---|---|
| 6.5.1 | L1 | Ensure modern authentication for Exchange Online is enabled |
| 6.5.2 | L1 | Ensure MailTips are enabled for end users |
| 6.5.3 | L2 | Ensure additional storage providers are restricted in Outlook on the web |
| 6.5.4 | L1 | Ensure SMTP AUTH is disabled |
| 6.5.5 | L2 | Ensure Direct Send submissions are rejected |

## Section 7 — SharePoint & OneDrive

### 7.2 Sharing & Access

| ID | Profile | Title |
|---|---|---|
| 7.2.1  | L1 | Ensure modern authentication for SharePoint applications is required |
| 7.2.2  | L1 | Ensure SharePoint and OneDrive integration with Azure AD B2B is enabled |
| 7.2.3  | L1 | Ensure external content sharing is restricted |
| 7.2.4  | L2 | Ensure OneDrive content sharing is restricted |
| 7.2.5  | L2 | Ensure that SharePoint guest users cannot share items they don't own |
| 7.2.6  | L2 | Ensure SharePoint external sharing is restricted |
| 7.2.7  | L1 | Ensure link sharing is restricted in SharePoint and OneDrive |
| 7.2.8  | L2 | Ensure external sharing is restricted by security group |
| 7.2.9  | L1 | Ensure guest access to a site or OneDrive will expire automatically |
| 7.2.10 | L1 | Ensure reauthentication with verification code is restricted |
| 7.2.11 | L1 | Ensure the SharePoint default sharing link permission is set |

### 7.3 Malware & Script Execution

| ID | Profile | Title |
|---|---|---|
| 7.3.1 | L2 | Ensure Office 365 SharePoint infected files are disallowed for download |
| 7.3.2 | L2 | Ensure OneDrive sync is restricted for unmanaged devices *(obsolete)* |
| 7.3.3 | L1 | Ensure custom script execution is restricted on personal sites *(obsolete)* |
| 7.3.4 | L1 | Ensure custom script execution is restricted on site collections *(obsolete)* |

## Section 8 — Microsoft Teams

### 8.1 File Sharing

| ID | Profile | Title |
|---|---|---|
| 8.1.1 | L2 | Ensure external file sharing in Teams is enabled for only approved services |
| 8.1.2 | L1 | Ensure users can't send emails to a channel email address |

### 8.2 External Access

| ID | Profile | Title |
|---|---|---|
| 8.2.1 | L2 | Ensure external domains are restricted in the Teams admin center |
| 8.2.2 | L1 | Ensure communication with unmanaged Teams users is disabled |
| 8.2.3 | L1 | Ensure external Teams users cannot initiate conversations |
| 8.2.4 | L1 | Ensure the organization cannot communicate with accounts in trial Teams tenants |

### 8.4 App Management

| ID | Profile | Title |
|---|---|---|
| 8.4.1 | L1 | Ensure app permission policies are configured |

### 8.5 Meeting Security

| ID | Profile | Title |
|---|---|---|
| 8.5.1 | L2 | Ensure anonymous users can't join a meeting |
| 8.5.2 | L1 | Ensure anonymous users and dial-in callers can't start a meeting |
| 8.5.3 | L1 | Ensure only people in my org can bypass the lobby |
| 8.5.4 | L1 | Ensure users dialing in can't bypass the lobby |
| 8.5.5 | L2 | Ensure meeting chat does not allow anonymous users |
| 8.5.6 | L2 | Ensure only organizers and co-organizers can present |
| 8.5.7 | L1 | Ensure external participants can't give or request control |
| 8.5.8 | L2 | Ensure external meeting chat is off |
| 8.5.9 | L2 | Ensure meeting recording is off by default |

### 8.6 User Safety

| ID | Profile | Title |
|---|---|---|
| 8.6.1 | L1 | Ensure users can report security concerns in Teams |

## Section 9 — Power BI

| ID | Profile | Title |
|---|---|---|
| 9.1.1  | L1 | Ensure guest user access is restricted |
| 9.1.2  | L1 | Ensure external user invitations are restricted |
| 9.1.3  | L1 | Ensure guest access to content is restricted |
| 9.1.4  | L1 | Ensure 'Publish to web' is restricted |
| 9.1.5  | L2 | Ensure 'Interact with and share R and Python' visuals is 'Disabled' |
| 9.1.6  | L1 | Ensure 'Allow users to apply sensitivity labels for content' is 'Enabled' |
| 9.1.7  | L1 | Ensure shareable links are restricted |
| 9.1.8  | L1 | Ensure enabling of external data sharing is restricted |
| 9.1.9  | L1 | Ensure 'Block ResourceKey Authentication' is 'Enabled' |
| 9.1.10 | L1 | Ensure access to APIs by Service Principals is restricted |
| 9.1.11 | L1 | Ensure Service Principals cannot create and use profiles |
| 9.1.12 | L1 | Ensure service principals ability to create workspaces and pipelines is restricted |

## Totals (approximate, by section, from Maester v6 list)

| Section | Count |
|---|---|
| 1. Administrative Accounts, Groups, User Policies | 15 |
| 2. Exchange Online & Threat Protection | 20 |
| 3. Data Protection & Governance | 4 |
| 4. Device Compliance | 2 |
| 5. Application & Access Control | 40 |
| 6. Mail Management | 12 |
| 7. SharePoint & OneDrive | 15 (incl. 3 obsolete) |
| 8. Teams | 16 |
| 9. Power BI | 12 |
| **Total** | **~136** |

Expected headline number is ~140. Small delta vs. Maester's count can be attributed to: (a) the three marked obsolete are still listed; (b) occasional renumbering between v6.0.0 and v6.0.1; (c) Maester may not yet test one or two manual checks. Treat this as a high-fidelity working copy — verify against the CIS PDF for any audit-critical reliance.

## Deviations from default CIS

Record any tenant-class exceptions here. One row per deviation, with owner and expiry.

| Rec ID | Tenant class | Deviation | Justification | Owner | Expiry |
|---|---|---|---|---|---|

## Sources

- Maester — CIS Microsoft 365 Foundations Benchmark Tests: <https://maester.dev/docs/tests/cis/>
- CIS Microsoft 365 Benchmarks (landing): <https://www.cisecurity.org/benchmark/microsoft_365>
- Reco.ai CIS v6 guide: <https://www.reco.ai/blog/cis-microsoft-365-v6-benchmark-guide>

## Version history of this draft

| Version | Date | Change |
|---|---|---|
| 0.2 | 2026-04-22 | Replaced speculative v6 draft with control IDs / titles sourced from Maester's v6 CIS test library. |
| 0.1-draft | 2026-04-22 | Initial speculative draft. |
