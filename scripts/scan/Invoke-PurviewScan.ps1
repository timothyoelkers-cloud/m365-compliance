<#
.SYNOPSIS
    Read-only scan of Microsoft Purview configuration — sensitivity labels, label policies, auto-labelling,
    DLP, retention, audit, Insider Risk (where licensed), Communication Compliance, Information Barriers.
    Covers CIS v6 Section 3.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not (Get-Command Get-Label -ErrorAction SilentlyContinue)) {
    throw "Purview (Connect-IPPSSession) session not present. Run Connect-Tenant.ps1 with -Workloads purview first."
}

function Safe { param([scriptblock]$B,[string]$L) try { & $B } catch { Write-Warning "$L failed: $($_.Exception.Message)"; $null } }

$data = [ordered]@{
    schemaVersion = '1.0.0'
    tenantId      = $TenantId
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    producedBy    = 'Invoke-PurviewScan.ps1@1.0.0'
    unifiedAuditLog     = $null
    sensitivityLabels   = @()
    labelPolicies       = @()
    autoLabelPolicies   = @()
    autoLabelRules      = @()
    dlpPolicies         = @()
    dlpRules            = @()
    retentionPolicies   = @()
    retentionRules      = @()
    retentionLabels     = @()
    supervisoryPolicies = @()
    insiderRiskPolicies = @()
    informationBarriers = @()
    organizationSegments = @()
    alertPolicies       = @()
    trainableClassifiers = @()
}

$data.unifiedAuditLog = Safe -L 'UAL' -B {
    if (Get-Command Get-AdminAuditLogConfig -ErrorAction SilentlyContinue) {
        Get-AdminAuditLogConfig | Select-Object UnifiedAuditLogIngestionEnabled, AdminAuditLogEnabled, AuditLogAgeLimit
    } else { $null }
}

$data.sensitivityLabels = Safe -L 'Labels' -B {
    Get-Label | Select-Object Name, DisplayName, Priority, ContentType, ParentLabelDisplayName, Tooltip, LabelActions, Conditions, ApplicableTo, EncryptionEnabled, Identity
}
$data.labelPolicies = Safe -L 'LabelPolicies' -B {
    Get-LabelPolicy | Select-Object Name, Mode, Labels, Settings, Enabled, DistributionStatus, RoutedLabels, ScopedLabels, ExchangeLocation, ExchangeLocationException, ModernGroupLocation, ModernGroupLocationException, SharePointLocation
}

$data.autoLabelPolicies = Safe -L 'AutoLabel' -B {
    Get-AutoSensitivityLabelPolicy | Select-Object Name, Mode, Workload, ApplySensitivityLabel, Priority, Enabled, Settings
}
$data.autoLabelRules    = Safe -L 'AutoLabelRules' -B {
    Get-AutoSensitivityLabelRule | Select-Object Name, Mode, Policy, Enabled, Priority, Workload, ContentPropertyContainsWords, ContentMatchesSensitiveInformation, SubjectContainsWords, DocumentNameMatchesPatterns
}

$data.dlpPolicies = Safe -L 'DLP' -B {
    Get-DlpCompliancePolicy | Select-Object Name, Mode, Enabled, Workload, ExchangeLocation, SharePointLocation, OneDriveLocation, TeamsLocation, EndpointDlpLocation, Priority
}
$data.dlpRules = Safe -L 'DLPRules' -B {
    Get-DlpComplianceRule | Select-Object Name, Disabled, Mode, Policy, Priority, ContentContainsSensitiveInformation, BlockAccess, BlockAccessScope, NotifyUser, NotifyEmailCustomText, GenerateIncidentReport, GenerateAlert, AccessScope
}

$data.retentionPolicies = Safe -L 'Retention' -B {
    Get-RetentionCompliancePolicy | Select-Object Name, Enabled, Mode, Workload, ExchangeLocation, SharePointLocation, OneDriveLocation, TeamsChannelLocation, TeamsChatLocation, Priority
}
$data.retentionRules = Safe -L 'RetentionRules' -B {
    Get-RetentionComplianceRule | Select-Object Name, Disabled, Policy, Priority, RetentionDuration, RetentionDurationDisplayHint, RetentionComplianceAction, PublishComplianceTag
}
$data.retentionLabels = Safe -L 'RetentionLabels' -B {
    Get-ComplianceTag | Select-Object Name, DisplayName, RetentionAction, RetentionDuration, RetentionType, IsRecordLabel, FilePlanMetadata
}

$data.supervisoryPolicies = Safe -L 'SupervisoryReview' -B { Get-SupervisoryReviewPolicyV2 -ErrorAction SilentlyContinue | Select-Object Name, Mode, Disabled }
$data.insiderRiskPolicies = Safe -L 'InsiderRisk' -B { if (Get-Command Get-InsiderRiskPolicy -ErrorAction SilentlyContinue) { Get-InsiderRiskPolicy | Select-Object Name, Status, InsiderRiskScenario, Priority } }

$data.informationBarriers = Safe -L 'IB' -B { if (Get-Command Get-InformationBarrierPolicy -ErrorAction SilentlyContinue) { Get-InformationBarrierPolicy | Select-Object Name, State, AssignedSegment, SegmentsAllowed, SegmentsBlocked } }
$data.organizationSegments = Safe -L 'OrgSegments' -B { if (Get-Command Get-OrganizationSegment -ErrorAction SilentlyContinue) { Get-OrganizationSegment | Select-Object Name, UserGroupFilter } }

$data.alertPolicies = Safe -L 'AlertPolicies' -B { Get-ProtectionAlert | Select-Object Name, Disabled, Severity, Category, ThreatType, AggregationType, Operation, Filter, NotifyUser, NotifyUserOnFilterMatch }

$data.trainableClassifiers = Safe -L 'TrainableClassifiers' -B { Get-ClassificationRuleCollection -ErrorAction SilentlyContinue }

$json = $data | ConvertTo-Json -Depth 25
$json | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
