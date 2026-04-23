# HIPAA — M365 Translation

| HIPAA ref | Obligation | M365 workload | Setting / policy | Evidence artefact |
|---|---|---|---|---|
| §164.308(a)(1)(ii)(D) | Info system activity review | Purview Audit | Unified Audit Log enabled; log review cadence documented | KQL review schedule, saved queries |
| §164.308(a)(3)(ii)(C) | Termination procedures | Entra | Lifecycle workflow (leaver): disable, revoke tokens, remove from groups, wipe device | Workflow JSON, run history |
| §164.308(a)(4) | Access authorization / establishment / modification | Entra, PIM | PIM for privileged roles; Access Reviews quarterly; role scoping via admin units | PIM config, review reports |
| §164.308(a)(5)(ii)(B) | Protection from malware | Defender for Endpoint, Defender for O365 | AV + tamper protection + ASR + Safe Links/Attachments | Defender config, alert history |
| §164.308(a)(6) | Security incident procedures | Defender XDR | Incident workflow runbook; automated investigation; post-mortem | Incident records |
| §164.308(a)(7)(i) | Data backup | Third-party backup | ePHI backed up outside M365 native retention; tested restores | Backup vendor config, restore tests |
| §164.308(a)(7)(ii) | DR plan | Third-party DR | RTO/RPO documented; tested | DR test reports |
| §164.310(c) | Workstation security | Intune | Device compliance (disk encryption, screen lock, patch status); CA requires compliant device | Compliance policy export |
| §164.310(d)(1)(i)–(ii) | Device disposal / media re-use | Intune | Wipe on retirement; remove company data | Wipe command history |
| §164.312(a)(2)(i) | Unique user ID | Entra | No shared accounts; lifecycle enforces unique UPN/ObjectID | Entra user export |
| §164.312(a)(2)(ii) | Emergency access | Entra | Documented break-glass accounts; FIDO2 tokens; monitored; excluded from user-risk CA but covered by separate CA | Break-glass runbook + monitoring queries |
| §164.312(a)(2)(iii) | Automatic logoff | CA + Intune | CA sign-in frequency; Intune inactivity lock | CA policy, Intune profile |
| §164.312(a)(2)(iv) | Encryption / decryption | Purview, Intune | Sensitivity labels with encryption on PHI; BitLocker via Intune; Customer Key (E5) where required | Label config, BitLocker keys escrowed |
| §164.312(b) | Audit controls | Purview Audit, Exchange | Unified Audit Log on; mailbox audit default on; Audit Premium high-value events (E5) | Audit config, sample query outputs |
| §164.312(c)(2) | Integrity / authentication of ePHI | SharePoint, Purview | Versioning on libraries; retention + litigation hold; S/MIME or IRM for signed messages | Library settings, retention policies |
| §164.312(d) | Person/entity authentication | Entra CA | Phishing-resistant MFA required for all ePHI access; FIDO2 / WHfB preferred | CA policies, authentication methods policy |
| §164.312(e)(1)(ii) | Transmission encryption | Exchange, Teams | TLS enforced; OME on rules (e.g., contains PHI → encrypt); Teams data in transit | Exchange connector config, OME rules |
| §164.314(a) | BAA content | Microsoft Online Services Terms | BAA accepted for in-scope services | BAA record |
| §164.316(b)(2) | Documentation retention (6 years) | Purview | Retention label "HIPAA-6yr" applied to policy docs and evidence | Retention policy export |
| Privacy §164.502 | Minimum necessary | Purview, SharePoint | Sensitivity labels; Information Barriers; SharePoint permissions | Label & IB policies |
| Privacy §164.524 | Right of access | Purview eDiscovery | Content Search across workloads; produce within 30 days | Search/export records |
| Breach §164.400–414 | Breach notification | Defender, Purview, DLP | Detection → assessment → notification workflow; evidence bundle | Incident timelines, notification logs |

## Design patterns for HIPAA tenants

- **Encryption-by-default everywhere PHI may land.** Configure Purview auto-labelling conservatively (audit mode first), then promote to enforce. Accept false-positive friction over false-negative leakage.
- **Phishing-resistant MFA is table stakes.** Target: all users on WHfB or FIDO2; no SMS/voice; Authenticator number-match only as transitional.
- **Tightly scoped external sharing.** Default OneDrive/SharePoint to "people in your org"; individual sites can lift to "new and existing guests" via business justification; block "anyone" links at tenant level.
- **Conditional Access minimums:** block legacy auth; require MFA + compliant device for PHI apps; require session control (App Enforced Restrictions or session token lifetime) on web access from unmanaged devices.
- **Audit retention:** 1 year minimum, 6 years for docs subject to §164.316. Audit Premium (E5) preferred for forensic depth.
