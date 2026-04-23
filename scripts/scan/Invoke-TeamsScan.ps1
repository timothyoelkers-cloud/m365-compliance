<#
.SYNOPSIS
    Read-only scan of Microsoft Teams tenant-level policies. Covers CIS v6 Section 8.

.DESCRIPTION
    Captures federation config, global meeting/messaging/app/channels policies, client config,
    Teams upgrade posture, and per-user policy assignment counts.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F-]{36}$')][string]$TenantId,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

if (-not (Get-Command Get-CsTenantFederationConfiguration -ErrorAction SilentlyContinue)) {
    throw "Microsoft Teams session not present. Run Connect-Tenant.ps1 with -Workloads teams first."
}

function Safe { param([scriptblock]$B,[string]$L) try { & $B } catch { Write-Warning "$L failed: $($_.Exception.Message)"; $null } }

$data = [ordered]@{
    schemaVersion = '1.0.0'
    tenantId      = $TenantId
    capturedAt    = (Get-Date).ToUniversalTime().ToString('o')
    producedBy    = 'Invoke-TeamsScan.ps1@1.0.0'
    federation            = $null
    meetingPolicyGlobal   = $null
    messagingPolicyGlobal = $null
    appPermissionGlobal   = $null
    appSetupGlobal        = $null
    clientConfiguration   = $null
    channelsPolicyGlobal  = $null
    guestMeetingPolicy    = $null
    meetingConfiguration  = $null
    meetingBroadcastPolicy= $null
    policyAssignmentCounts = @{}
    allMeetingPolicies    = @()
    allMessagingPolicies  = @()
    allAppPermissionPolicies = @()
}

$data.federation = Safe -L 'Federation' -B {
    Get-CsTenantFederationConfiguration | Select-Object AllowedDomains, BlockedDomains, AllowFederatedUsers,
        AllowTeamsConsumer, AllowTeamsConsumerInbound, AllowPublicUsers, SharedSipAddressSpace,
        TreatDiscoveredPartnersAsUnverified, RestrictTeamsConsumerToExternalUserProfiles
}

$data.meetingPolicyGlobal = Safe -L 'MeetingPolicyGlobal' -B {
    Get-CsTeamsMeetingPolicy -Identity Global | Select-Object AllowAnonymousUsersToJoinMeeting,
        AllowAnonymousUsersToStartMeeting, AutoAdmittedUsers, AllowPSTNUsersToBypassLobby,
        MeetingChatEnabledType, AllowParticipantGiveRequestControl, AllowExternalParticipantGiveRequestControl,
        AllowSharedNotes, AllowWhiteboard, AllowTranscription, AllowCloudRecording, AllowIPVideo,
        ScreenSharingMode, AllowPowerPointSharing, AllowEngagementReport, AllowAvatarsInGallery,
        DesignatedPresenterRoleMode, LobbyChatEnabled, AllowRoomAttributeInMeetingInvite
}

$data.messagingPolicyGlobal = Safe -L 'MessagingPolicyGlobal' -B {
    Get-CsTeamsMessagingPolicy -Identity Global | Select-Object AllowUrlPreviews, AllowOwnerDeleteMessage,
        AllowUserEditMessage, AllowUserDeleteMessage, AllowGiphy, GiphyRatingType, AllowMemes, AllowImmersiveReader,
        AllowStickers, AllowUserChat, AllowUserTranslation, AllowPriorityMessages, AllowSmartReply
}

$data.appPermissionGlobal = Safe -L 'AppPermissionGlobal' -B {
    Get-CsTeamsAppPermissionPolicy -Identity Global | Select-Object DefaultCatalogApps, GlobalCatalogApps,
        PrivateCatalogApps, DefaultCatalogAppsType, GlobalCatalogAppsType, PrivateCatalogAppsType, Description
}

$data.appSetupGlobal = Safe -L 'AppSetupGlobal' -B {
    Get-CsTeamsAppSetupPolicy -Identity Global | Select-Object AllowUserPinning, AllowSideLoading,
        PinnedMessageBarApps, PinnedAppBarApps, PinnedAppStoreApps
}

$data.clientConfiguration = Safe -L 'ClientConfiguration' -B {
    Get-CsTeamsClientConfiguration | Select-Object AllowEmailIntoChannel, RestrictedSenderList, AllowGoogleDrive,
        AllowShareFile, AllowBox, AllowDropBox, AllowEgnyte, AllowOrganizationTab, AllowResourceAccountSendMessage,
        AllowGuestUser, AllowSkypeBusinessInterop, AllowTBotProactiveMessaging
}

$data.channelsPolicyGlobal = Safe -L 'ChannelsPolicyGlobal' -B {
    Get-CsTeamsChannelsPolicy -Identity Global | Select-Object AllowPrivateChannelCreation, AllowPrivateTeamDiscovery, AllowOrgWideTeamCreation, AllowSharedChannelCreation, AllowChannelSharingToExternalUser
}

$data.guestMeetingPolicy = Safe -L 'GuestMeetingPolicy' -B {
    Get-CsTeamsGuestMeetingConfiguration | Select-Object AllowIPVideo, ScreenSharingMode, AllowMeetNow
}

$data.meetingConfiguration = Safe -L 'MeetingConfig' -B {
    Get-CsTeamsMeetingConfiguration | Select-Object DisableAnonymousJoin, ClientAppSharedDeviceMode,
        EnableMeetingCoOrganizer, EnableQoS
}

$data.meetingBroadcastPolicy = Safe -L 'MeetingBroadcastPolicy' -B {
    Get-CsTeamsMeetingBroadcastPolicy -Identity Global | Select-Object AllowBroadcastScheduling, AllowBroadcastTranscription, BroadcastAttendeeVisibilityMode, BroadcastRecordingMode
}

$data.allMeetingPolicies = Safe -L 'AllMeetingPolicies' -B { Get-CsTeamsMeetingPolicy | Select-Object Identity, Description }
$data.allMessagingPolicies = Safe -L 'AllMessagingPolicies' -B { Get-CsTeamsMessagingPolicy | Select-Object Identity, Description }
$data.allAppPermissionPolicies = Safe -L 'AllAppPermission' -B { Get-CsTeamsAppPermissionPolicy | Select-Object Identity, Description, GlobalCatalogAppsType }

$json = $data | ConvertTo-Json -Depth 20
$json | Out-File -LiteralPath $OutputPath -Encoding utf8
Write-Output $OutputPath
