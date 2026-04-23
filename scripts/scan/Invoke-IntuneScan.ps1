<#
.SYNOPSIS
    Read-only scan of Microsoft Intune configuration — compliance policies, configuration profiles,
    endpoint security policies, app protection, enrollment restrictions, scope tags, assignment filters,
    Windows update rings.
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

Import-Module Microsoft.Graph.DeviceManagement -ErrorAction Stop
Import-Module Microsoft.Graph.DeviceManagement.Enrolment -ErrorAction SilentlyContinue

function Safe { param([scriptblock]$B,[string]$L) try { & $B } catch { Write-Warning "$L failed: $($_.Exception.Message)"; $null } }

$data = [ordered]@{
    schemaVersion = '1.0.0'
    tenantId      = $TenantId
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    producedBy    = 'Invoke-IntuneScan.ps1@1.0.0'
    compliancePolicies   = @()
    configurationProfiles = @()
    configurationPoliciesBeta = @()
    endpointSecurity     = @()
    appProtectionPolicies = @()
    appConfigurationPolicies = @()
    enrollmentConfigurations = @()
    scopeTags            = @()
    assignmentFilters    = @()
    windowsUpdateRings   = @()
    devicesByCompliance  = @{}
    devicesByPlatform    = @{}
}

$data.compliancePolicies = Safe -L 'CompliancePolicies' -B {
    Get-MgDeviceManagementDeviceCompliancePolicy -All |
        Select-Object Id, DisplayName, Description, Version, CreatedDateTime, LastModifiedDateTime,
            @{N='type';E={ $_.AdditionalProperties.'@odata.type' }}
}

$data.configurationProfiles = Safe -L 'ConfigurationProfiles' -B {
    Get-MgDeviceManagementDeviceConfiguration -All |
        Select-Object Id, DisplayName, Description, Version, CreatedDateTime, LastModifiedDateTime,
            @{N='type';E={ $_.AdditionalProperties.'@odata.type' }}
}

# Settings Catalog (beta) — most modern profile surface
$data.configurationPoliciesBeta = Safe -L 'ConfigurationPoliciesBeta' -B {
    Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies' |
        Select-Object -ExpandProperty value |
        ForEach-Object {
            [ordered]@{
                id = $_.id
                name = $_.name
                platforms = $_.platforms
                technologies = $_.technologies
                createdDateTime = $_.createdDateTime
                lastModifiedDateTime = $_.lastModifiedDateTime
            }
        }
}

$data.endpointSecurity = Safe -L 'EndpointSecurityIntents' -B {
    Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/intents' |
        Select-Object -ExpandProperty value |
        ForEach-Object {
            [ordered]@{
                id = $_.id
                displayName = $_.displayName
                templateId = $_.templateId
                lastModifiedDateTime = $_.lastModifiedDateTime
            }
        }
}

$data.appProtectionPolicies = Safe -L 'AppProtection' -B {
    Get-MgDeviceAppManagementManagedAppPolicy -All |
        Select-Object Id, DisplayName, Description, Version, CreatedDateTime, LastModifiedDateTime,
            @{N='type';E={ $_.AdditionalProperties.'@odata.type' }}
}

$data.appConfigurationPolicies = Safe -L 'AppConfiguration' -B {
    Get-MgDeviceAppManagementTargetedManagedAppConfiguration -All |
        Select-Object Id, DisplayName, Description, AppGroupType, DeployedAppCount
}

$data.enrollmentConfigurations = Safe -L 'EnrollmentRestrictions' -B {
    Get-MgDeviceManagementDeviceEnrollmentConfiguration -All |
        Select-Object Id, DisplayName, Description, Priority, Version,
            @{N='type';E={ $_.AdditionalProperties.'@odata.type' }}
}

$data.scopeTags = Safe -L 'ScopeTags' -B {
    Get-MgDeviceManagementRoleScopeTag -All | Select-Object Id, DisplayName, Description, IsBuiltIn
}

$data.assignmentFilters = Safe -L 'AssignmentFilters' -B {
    Invoke-MgGraphRequest -Method GET -Uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters' |
        Select-Object -ExpandProperty value |
        ForEach-Object {
            [ordered]@{
                id = $_.id
                displayName = $_.displayName
                platform = $_.platform
                rule = $_.rule
            }
        }
}

$data.windowsUpdateRings = Safe -L 'WindowsUpdateRings' -B {
    Get-MgDeviceManagementDeviceConfiguration -All -Filter "isof('microsoft.graph.windowsUpdateForBusinessConfiguration')" |
        Select-Object Id, DisplayName, Description
}

$data.devicesByCompliance = Safe -L 'DevicesCompliance' -B {
    Get-MgDeviceManagementManagedDevice -All -Property Id, DeviceName, ComplianceState, OperatingSystem, OsVersion |
        Group-Object ComplianceState |
        ForEach-Object { @{ state = $_.Name; count = $_.Count } }
}

$data.devicesByPlatform = Safe -L 'DevicesPlatform' -B {
    Get-MgDeviceManagementManagedDevice -All -Property Id, OperatingSystem |
        Group-Object OperatingSystem |
        ForEach-Object { @{ platform = $_.Name; count = $_.Count } }
}

$json = $data | ConvertTo-Json -Depth 20
$json | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
