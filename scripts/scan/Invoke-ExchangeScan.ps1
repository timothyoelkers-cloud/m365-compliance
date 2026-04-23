<#
.SYNOPSIS
    Read-only scan of Exchange Online and Defender-for-Office-365 policies relevant to CIS v6
    sections 2.x (email/threat protection) and 6.x (mail management).

.DESCRIPTION
    Captures: organisation config, transport config, accepted/remote domains, connectors, transport rules,
    DKIM signing, mailbox auditing defaults, CAS mailbox plan, outbound spam policy, anti-phish/spam/
    malware/safelinks/safeattachments policies and rules, preset protection rules.

.PARAMETER TenantId
.PARAMETER OutputPath
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not (Get-Command Get-OrganizationConfig -ErrorAction SilentlyContinue)) {
    throw "Exchange Online session not present. Run Connect-Tenant.ps1 with -Workloads exchange first."
}

function Safe { param([scriptblock]$B,[string]$L) try { & $B } catch { Write-Warning "$L failed: $($_.Exception.Message)"; $null } }

$data = [ordered]@{
    schemaVersion  = '1.0.0'
    tenantId       = $TenantId
    capturedAt     = (Get-Date).ToUniversalTime().ToString('o')
    producedBy     = 'Invoke-ExchangeScan.ps1@1.0.0'
    organizationConfig = $null
    transportConfig    = $null
    acceptedDomains    = @()
    remoteDomains      = @()
    inboundConnectors  = @()
    outboundConnectors = @()
    transportRules     = @()
    dkimSigningConfig  = @()
    mailboxAudit       = $null
    casMailboxPlans    = @()
    outboundSpamPolicies = @()
    antiPhishPolicies    = @()
    antiPhishRules       = @()
    antiSpamInbound      = @()
    antiSpamRules        = @()
    malwareFilterPolicies = @()
    malwareFilterRules   = @()
    safeLinksPolicies    = @()
    safeLinksRules       = @()
    safeAttachmentsPolicies = @()
    safeAttachmentsRules = @()
    atpPolicyForO365     = $null
    presetEopRules       = @()
    presetAtpRules       = @()
    mailboxSampling      = $null
}

$data.organizationConfig = Safe -L 'OrganizationConfig' -B {
    Get-OrganizationConfig | Select-Object AuditDisabled, CustomerLockBoxEnabled, OAuth2ClientProfileEnabled,
        EwsApplicationAccessPolicy, EwsEnabled, MapiHttpEnabled, ActivityBasedAuthenticationTimeoutEnabled,
        ActivityBasedAuthenticationTimeoutInterval, PreferredInternetCodePageForShiftJis,
        DirectReportsGroupAutoCreationEnabled
}

$data.transportConfig = Safe -L 'TransportConfig' -B {
    Get-TransportConfig | Select-Object SmtpClientAuthenticationDisabled, ExternalDelayDsnEnabled,
        ExternalDsnReportingAuthority, InternalSMTPServers, Rfc2231EncodingEnabled, TLSReceiveDomainSecureList,
        TLSSendDomainSecureList, AuditDisabled
}

$data.acceptedDomains   = Safe -L 'AcceptedDomains'   -B { Get-AcceptedDomain | Select-Object Name, DomainName, DomainType, Default, AuthenticationType, MatchSubDomains }
$data.remoteDomains     = Safe -L 'RemoteDomains'     -B { Get-RemoteDomain  | Select-Object Name, DomainName, AutoForwardEnabled, AutoReplyEnabled, TrustedMailInboundEnabled, TrustedMailOutboundEnabled, AllowedOOFType }
$data.inboundConnectors = Safe -L 'InboundConnectors' -B { Get-InboundConnector  | Select-Object Name, Enabled, ConnectorType, SenderDomains, TlsSenderCertificateName, RequireTls }
$data.outboundConnectors = Safe -L 'OutboundConnectors' -B { Get-OutboundConnector | Select-Object Name, Enabled, ConnectorType, RecipientDomains, SmartHosts, TlsSettings, UseMXRecord }

$data.transportRules    = Safe -L 'TransportRules' -B {
    Get-TransportRule | Select-Object Name, State, Priority, Mode, ApplyRightsProtectionTemplate,
        FromScope, SentToScope, SubjectOrBodyMatchesPatterns, ExceptIfFromScope, SetHeaderName,
        SetHeaderValue, RedirectMessageTo, BlindCopyTo, ApplyClassification, Identity, Description
}

$data.dkimSigningConfig = Safe -L 'DkimSigningConfig' -B {
    Get-DkimSigningConfig | Select-Object Domain, Enabled, Status, KeySize, Selector1CNAME, Selector2CNAME, LastChecked
}

$data.mailboxAudit = Safe -L 'MailboxAuditDefault' -B {
    $org = Get-OrganizationConfig
    [ordered]@{
        tenantAuditDisabled = $org.AuditDisabled
        adminAuditLog       = (Get-AdminAuditLogConfig | Select-Object UnifiedAuditLogIngestionEnabled, AdminAuditLogEnabled, LogLevel, AuditLogAgeLimit)
    }
}

# Sample CASMailbox state for drift indicators (SmtpClientAuth, POP/IMAP still on per-mailbox)
$data.casMailboxPlans = Safe -L 'CASMailboxPlans' -B {
    Get-CASMailboxPlan | Select-Object Identity, PopEnabled, ImapEnabled, ActiveSyncEnabled, OWAEnabled
}

$data.mailboxSampling = Safe -L 'MailboxSampling' -B {
    Get-CASMailbox -ResultSize 200 |
        Group-Object PopEnabled, ImapEnabled, SmtpClientAuthenticationDisabled |
        ForEach-Object {
            [pscustomobject]@{
                pattern = $_.Name
                count   = $_.Count
            }
        }
}

$data.outboundSpamPolicies = Safe -L 'OutboundSpam' -B {
    Get-HostedOutboundSpamFilterPolicy | Select-Object Name, AutoForwardingMode, RecipientLimitExternalPerHour,
        RecipientLimitInternalPerHour, RecipientLimitPerDay, ActionWhenThresholdReached, NotifyOutboundSpam,
        NotifyOutboundSpamRecipients, BccSuspiciousOutboundMail
}

$data.antiPhishPolicies = Safe -L 'AntiPhish' -B {
    Get-AntiPhishPolicy | Select-Object Name, Enabled, EnableMailboxIntelligence, EnableMailboxIntelligenceProtection,
        EnableSpoofIntelligence, EnableTargetedUserProtection, TargetedUsersToProtect, EnableTargetedDomainsProtection,
        TargetedDomainsToProtect, EnableOrganizationDomainsProtection, AuthenticationFailAction, PhishThresholdLevel,
        TargetedUserProtectionAction, TargetedDomainProtectionAction
}
$data.antiPhishRules = Safe -L 'AntiPhishRules' -B { Get-AntiPhishRule | Select-Object Name, State, Priority, SentTo, RecipientDomainIs, AntiPhishPolicy }

$data.antiSpamInbound = Safe -L 'AntiSpamInbound' -B { Get-HostedContentFilterPolicy | Select-Object Name, SpamAction, HighConfidenceSpamAction, BulkSpamAction, BulkThreshold, PhishSpamAction, HighConfidencePhishAction, QuarantineRetentionPeriod, InlineSafetyTipsEnabled, AllowedSenderDomains, BlockedSenderDomains }
$data.antiSpamRules   = Safe -L 'AntiSpamRules'   -B { Get-HostedContentFilterRule | Select-Object Name, State, Priority, HostedContentFilterPolicy, SentTo, RecipientDomainIs }

$data.malwareFilterPolicies = Safe -L 'MalwareFilter' -B { Get-MalwareFilterPolicy | Select-Object Name, EnableFileFilter, FileTypes, EnableInternalSenderAdminNotifications, InternalSenderAdminAddress, ZapEnabled }
$data.malwareFilterRules    = Safe -L 'MalwareFilterRules' -B { Get-MalwareFilterRule | Select-Object Name, State, Priority, MalwareFilterPolicy }

$data.safeLinksPolicies = Safe -L 'SafeLinks' -B { Get-SafeLinksPolicy | Select-Object Name, EnableSafeLinksForEmail, EnableSafeLinksForTeams, EnableSafeLinksForOffice, ScanUrls, DeliverMessageAfterScan, DoNotAllowClickThrough, EnableForInternalSenders }
$data.safeLinksRules    = Safe -L 'SafeLinksRules' -B { Get-SafeLinksRule | Select-Object Name, State, Priority, SafeLinksPolicy, SentTo, RecipientDomainIs }

$data.safeAttachmentsPolicies = Safe -L 'SafeAttachments' -B { Get-SafeAttachmentPolicy | Select-Object Name, Enable, Action, Redirect, RedirectAddress, QuarantineTag, ActionOnError }
$data.safeAttachmentsRules    = Safe -L 'SafeAttachmentsRules' -B { Get-SafeAttachmentRule | Select-Object Name, State, Priority, SafeAttachmentPolicy, SentTo, RecipientDomainIs }

$data.atpPolicyForO365 = Safe -L 'AtpPolicyForO365' -B {
    Get-AtpPolicyForO365 | Select-Object EnableATPForSPOTeamsODB, EnableSafeDocs, AllowSafeDocsOpen
}

$data.presetEopRules = Safe -L 'EOPPresetRules' -B { Get-EOPProtectionPolicyRule | Select-Object Name, State, Priority, SentTo, RecipientDomainIs, ExceptIfSentTo, ExceptIfRecipientDomainIs, Identity }
$data.presetAtpRules = Safe -L 'ATPPresetRules' -B { Get-ATPProtectionPolicyRule | Select-Object Name, State, Priority, SentTo, RecipientDomainIs, ExceptIfSentTo, ExceptIfRecipientDomainIs, Identity }

$json = $data | ConvertTo-Json -Depth 25
$json | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
