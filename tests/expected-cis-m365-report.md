# CIS Microsoft 365 v6.0.1 — Audit-Prep Report

**Tenant:** Synthetic Test Tenant (fixture)

**Run id:** 00000000-0000-0000-0000-cccccccccccc  
**Generated:** _deterministic-fixture_  
**Findings file:** findings.json

## Headline

| Status | Count |
|---|---|
| Covered (primary deployed, no drift) | 41 |
| Drift (control deployed but failing) | 10 |
| Partial-only (no primary control deployed) | 4 |
| Uncovered (no mapped control deployed) | 0 |
| **Total mapped framework references** | **55** |

## Coverage matrix

| Framework reference | Status | Primary controls | Partial controls | Failing |
|---|---|---|---|---|
| 1.1.1 | covered | m365.entra.admin-cloud-only | — | — |
| 1.1.2 | covered | m365.entra.break-glass.defined | — | — |
| 1.1.3 | covered | m365.entra.admin-count-2-to-4 | — | — |
| 2.1.1 | covered | m365.exchange.safe-links | — | — |
| 2.1.15 | covered | m365.exchange.outbound-spam-limits | — | — |
| 2.1.4 | covered | m365.exchange.safe-attachments | — | — |
| 2.1.7 | covered | m365.exchange.anti-phish-policy | — | — |
| 2.2.1 | covered | m365.entra.break-glass.monitored | — | — |
| 2.4.1 | covered | m365.exchange.priority-account-protect | — | — |
| 2.4.2 | covered | m365.exchange.priority-account-strict | — | — |
| 2.4.3 | covered | m365.defender.mdca | — | — |
| 2.4.4 | covered | m365.defender.zap-teams | — | — |
| 3.1.1 | covered | m365.purview.audit.unified-log-enabled | — | — |
| 3.2.1 | covered | m365.purview.dlp.enabled | — | — |
| 3.2.2 | covered | m365.purview.dlp.teams | — | — |
| 3.3.1 | covered | m365.purview.sensitivity-labels.published | — | — |
| 4.1 | covered | m365.intune.compliance.gate | — | — |
| 4.2 | covered | m365.intune.enrollment.personal-blocked | — | — |
| 5.1.2.3 | covered | m365.entra.tenant-creation-restricted | — | — |
| 5.1.5.1 | covered | m365.entra.user-consent.restricted | — | — |
| 5.1.5.2 | covered | m365.entra.admin-consent-workflow | — | — |
| 5.1.6.2 | covered | m365.entra.guest-restricted | — | — |
| 5.2.2.2 | covered | m365.entra.ca.mfa-all-users | — | — |
| 5.2.2.3 | covered | m365.entra.ca.block-legacy-auth | — | — |
| 5.2.2.5 | covered | m365.entra.ca.mfa-phishing-resistant | — | — |
| 5.2.2.6 | covered | m365.entra.ca.identity-protection-risk | — | — |
| 5.2.2.7 | covered | m365.entra.ca.identity-protection-risk | — | — |
| 5.2.2.9 | covered | m365.entra.ca.managed-device-required | — | — |
| 5.2.3.1 | covered | m365.entra.auth-methods.fatigue-protect | — | — |
| 5.2.3.2 | covered | m365.entra.password-protection.banned-list | — | — |
| 5.2.3.5 | covered | m365.entra.auth-methods.weak-disabled | — | — |
| 5.3.1 | covered | m365.entra.pim.just-in-time | — | — |
| 5.3.3 | covered | m365.entra.access-reviews.privileged | — | — |
| 6.1.2 | covered | m365.exchange.mailbox-audit-actions | — | — |
| 6.2.3 | covered | m365.exchange.external-sender-banner | — | — |
| 6.5.1 | covered | m365.exchange.modern-auth | — | — |
| 6.5.4 | covered | m365.exchange.smtp-auth-disabled | — | — |
| 7.2.7 | covered | m365.sharepoint.link-sharing | — | — |
| 8.2.1 | covered | m365.teams.federation.restricted | — | — |
| 8.4.1 | covered | m365.teams.app-permission | — | — |
| 9.1.10 | covered | m365.powerbi.service-principals-restricted | — | — |
| 2.1.9 | drift | m365.exchange.dkim | — | m365.exchange.dkim |
| 6.1.1 | drift | m365.exchange.mailbox-audit | — | m365.exchange.mailbox-audit |
| 6.2.1 | drift | m365.exchange.mail-forwarding-blocked | — | m365.exchange.mail-forwarding-blocked |
| 7.2.3 | drift | m365.sharepoint.sharing-capability | — | m365.sharepoint.sharing-capability |
| 7.2.9 | drift | m365.sharepoint.guest-expire | — | m365.sharepoint.guest-expire |
| 8.2.2 | drift | m365.teams.unmanaged-blocked | — | m365.teams.unmanaged-blocked |
| 8.5.1 | drift | m365.teams.anonymous-no-join | — | m365.teams.anonymous-no-join |
| 8.5.3 | drift | m365.teams.lobby-bypass | — | m365.teams.lobby-bypass |
| 9.1.1 | drift | m365.powerbi.guest-restricted | — | m365.powerbi.guest-restricted |
| 9.1.4 | drift | m365.powerbi.publish-to-web | — | m365.powerbi.publish-to-web |
| 2.1.10 | partial-only | — | m365.exchange.dmarc | — |
| 2.1.8 | partial-only | — | m365.exchange.spf | — |
| 5.3.4 | partial-only | — | m365.entra.pim.just-in-time | — |
| 5.3.5 | partial-only | — | m365.entra.pim.just-in-time | — |

## Findings scoped to CIS Microsoft 365 v6.0.1

### high

- **entra.weak-auth-voice-disabled** (entra)  
  Maps to: `5.2.3.5`  
  Current: `enabled` — Desired: `disabled`  
  Action: reported — Evidence: `entra.json`

- **exchange.auto-forwarding-off** (exchange)  
  Maps to: `6.2.1`  
  Current: `Automatic` — Desired: `Off`  
  Action: reported — Evidence: `exchange.json`

- **exchange.mailbox-audit-on** (exchange)  
  Maps to: `6.1.1`  
  Current: `True` — Desired: `True`  
  Action: reported — Evidence: `exchange.json`

- **sharepoint.sharing-capability** (sharepoint)  
  Maps to: `7.2.3`  
  Current: `ExternalUserAndGuestSharing` — Desired: `ExistingExternalUserSharingOnly`  
  Action: reported — Evidence: `sharepoint.json`

### medium

- **exchange.dkim-enabled-for-all** (exchange)  
  Maps to: `2.1.9`  
  Current: `[True, False]` — Desired: `True`  
  Action: reported — Evidence: `exchange.json`

- **sharepoint.guest-expire-required** (sharepoint)  
  Maps to: `7.2.9`  
  Current: `False` — Desired: `True`  
  Action: reported — Evidence: `sharepoint.json`

- **sharepoint.prevent-external-resharing** (sharepoint)  
  Maps to: `7.2.5`  
  Current: `False` — Desired: `True`  
  Action: reported — Evidence: `sharepoint.json`

- **teams.anonymous-cannot-join** (teams)  
  Maps to: `8.5.1`  
  Current: `True` — Desired: `False`  
  Action: reported — Evidence: `teams.json`

- **teams.federation-consumer-blocked** (teams)  
  Maps to: `8.2.2`  
  Current: `True` — Desired: `False`  
  Action: reported — Evidence: `teams.json`

- **teams.lobby-bypass-restricted** (teams)  
  Maps to: `8.5.3`  
  Current: `Everyone` — Desired: `EveryoneInCompanyExcludingGuests`  
  Action: reported — Evidence: `teams.json`

### info

- **powerbi.guest-access-restricted** (powerbi)  
  Maps to: `9.1.1`  
  Current: `None` — Desired: `False`  
  Action: deferred — Evidence: `(no powerbi artefact in bundle)`

- **powerbi.publish-to-web-restricted** (powerbi)  
  Maps to: `9.1.4`  
  Current: `None` — Desired: `disabled`  
  Action: deferred — Evidence: `(no powerbi artefact in bundle)`

## Evidence index

| Evidence artefact | Backing framework references |
|---|---|
| `accessReviews.privileged.json` | 5.3.3 |
| `admin.accounts.cloud-only.json` | 1.1.1 |
| `adminConsentWorkflow.json` | 5.1.5.2 |
| `auth-methods.microsoftauthenticator.json` | 5.2.3.1 |
| `auth-methods.weak-disabled.json` | 5.2.3.5 |
| `authorizationPolicy.json` | 5.1.2.3 |
| `break-glass.group.json` | 1.1.2 |
| `break-glass.monitoring.json` | 2.2.1 |
| `ca.policies.block-legacy-auth.json` | 5.2.2.3 |
| `ca.policies.identity-protection.json` | 5.2.2.6<br>5.2.2.7 |
| `ca.policies.managed-device.json` | 5.2.2.9 |
| `ca.policies.mfa-all-users.json` | 5.2.2.2 |
| `ca.policies.mfa-phishing-resistant.json` | 5.2.2.5 |
| `consent.policy.json` | 5.1.5.1 |
| `defender.anti-phish.json` | 2.1.7 |
| `defender.mdca.json` | 2.4.3 |
| `defender.presets.strict.priority.json` | 2.4.2 |
| `defender.priority-accounts.json` | 2.4.1 |
| `defender.safe-attachments.json` | 2.1.4 |
| `defender.safe-links.json` | 2.1.1 |
| `defender.zap.teams.json` | 2.4.4 |
| `exchange.auditDisabled.json` | 6.1.1 |
| `exchange.dkim.json` | 2.1.9 |
| `exchange.dmarc.json` | 2.1.10 |
| `exchange.forwarding.json` | 6.2.1 |
| `exchange.mailbox.auditActions.json` | 6.1.2 |
| `exchange.organizationConfig.json` | 6.5.1 |
| `exchange.outboundSpam.json` | 2.1.15 |
| `exchange.rule.externalSender.json` | 6.2.3 |
| `exchange.spf.json` | 2.1.8 |
| `exchange.transportConfig.json` | 6.5.4 |
| `globalAdmins.count.json` | 1.1.3 |
| `guest.access.json` | 5.1.6.2 |
| `intune.enrollment.restrictions.json` | 4.2 |
| `intune.nocompliance.default.json` | 4.1 |
| `password-protection.json` | 5.2.3.2 |
| `pim.roleSchedulePolicies.json` | 5.3.1<br>5.3.4<br>5.3.5 |
| `powerbi.guest.json` | 9.1.1 |
| `powerbi.publishToWeb.json` | 9.1.4 |
| `powerbi.sp.apis.json` | 9.1.10 |
| `purview.audit.config.json` | 3.1.1 |
| `purview.dlp.json` | 3.2.1 |
| `purview.dlp.teams.json` | 3.2.2 |
| `purview.label.policies.json` | 3.3.1 |
| `sharepoint.guestExpiry.json` | 7.2.9 |
| `sharepoint.linkSharing.json` | 7.2.7 |
| `sharepoint.sharing.json` | 7.2.3 |
| `teams.app.permission.json` | 8.4.1 |
| `teams.federation.json` | 8.2.1 |
| `teams.meeting.anonymous.json` | 8.5.1 |
| `teams.meeting.lobby.json` | 8.5.3 |
| `teams.unmanaged.json` | 8.2.2 |

## Gaps

| Framework reference | Status | Action |
|---|---|---|
| 2.1.9 | drift | Investigate failing controls; remediate to baseline |
| 6.1.1 | drift | Investigate failing controls; remediate to baseline |
| 6.2.1 | drift | Investigate failing controls; remediate to baseline |
| 7.2.3 | drift | Investigate failing controls; remediate to baseline |
| 7.2.9 | drift | Investigate failing controls; remediate to baseline |
| 8.2.2 | drift | Investigate failing controls; remediate to baseline |
| 8.5.1 | drift | Investigate failing controls; remediate to baseline |
| 8.5.3 | drift | Investigate failing controls; remediate to baseline |
| 9.1.1 | drift | Investigate failing controls; remediate to baseline |
| 9.1.4 | drift | Investigate failing controls; remediate to baseline |
| 2.1.10 | partial-only | Add a primary control or accept defence-in-depth posture |
| 2.1.8 | partial-only | Add a primary control or accept defence-in-depth posture |
| 5.3.4 | partial-only | Add a primary control or accept defence-in-depth posture |
| 5.3.5 | partial-only | Add a primary control or accept defence-in-depth posture |

---

_Generated by `scripts/report/New-FrameworkReport.ps1`. The mapped scope is limited to controls present in `skills/mapping/control-map/map.csv`. Requirements outside the map are not assessed automatically — see the framework skill for manual review guidance._
