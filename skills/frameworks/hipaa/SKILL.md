---
name: hipaa
description: US HIPAA — Health Insurance Portability and Accountability Act. Use when the user references HIPAA, PHI/ePHI, covered entities, business associates, the Security Rule (§164.308/310/312/314/316), the Privacy Rule (Subpart E), or the Breach Notification Rule. Focused on how M365 tenant configuration supports compliance; does not substitute for legal advice or a signed Business Associate Agreement.
---

# HIPAA — M365 Compliance

HIPAA's operative components for M365 tenants:

- **Privacy Rule** — 45 CFR 164 Subpart E. Governs use and disclosure of PHI.
- **Security Rule** — 45 CFR 164 Subpart C. Administrative, Physical, and Technical Safeguards for ePHI.
- **Breach Notification Rule** — 45 CFR 164.400–414. Individuals, HHS, sometimes media.
- **Omnibus Rule (2013)** — extended direct liability to Business Associates and subcontractors.

> **Rule status as of April 2026:** HHS/OCR published a Notice of Proposed Rulemaking in the Federal Register on **6 January 2025**; the comment period closed 7 March 2025 with ~5,000 comments. Final rule finalisation is on OCR's regulatory agenda for **May 2026** (per HHS public agenda, confirmed late 2025 / early 2026). Compliance deadline following publication is expected at ~240 days, putting full compliance around late 2026 or early 2027.
>
> **Political uncertainty:** the incoming administration may publish a final rule that differs meaningfully from the NPRM — some proposed requirements may be softened or dropped. Treat the NPRM as indicative of direction, not as settled law, until the final rule is published.
>
> The proposed changes include: removing the "Required/Addressable" distinction, mandating MFA, encryption-by-default at rest and in transit, vulnerability scanning (≥ every 6 months), penetration testing (≥ annually), current asset inventory, patching SLAs for critical CVEs, written testing of incident response procedures annually.
>
> **Practical posture:** configure tenants now as though the NPRM is law (strict L1+L2 CIS baseline + Intune compliance + Defender Vulnerability Management). The technical delta is small; the governance/documentation delta is larger and should be staged now so that the compliance clock (~240 days from final rule publication) is not a scramble.

## When this skill applies

- User is configuring an M365 tenant for a **covered entity** (health plan, healthcare clearinghouse, or healthcare provider conducting covered transactions) or a **business associate**.
- User asks about ePHI handling, encryption, access controls, audit logging, or breach notification within M365.
- User needs to show the HIPAA BAA is in place for Microsoft services being used.

## Prerequisite — the Microsoft BAA

Before any HIPAA-bearing workload runs in M365:

1. Confirm the tenant is a **commercial (not free trial) tenant** covered by Microsoft's BAA. Microsoft offers a BAA covering most in-scope M365 services, included in the Online Services Terms for eligible subscriptions.
2. Verify **which specific services are in-scope** under the BAA — not all M365 features qualify. Microsoft publishes the list; re-check per engagement, as it evolves.
3. Record BAA acceptance date and scope in the compliance register.

A tenant without a signed BAA cannot lawfully process ePHI using Microsoft services.

## Security Rule structure

### §164.308 — Administrative Safeguards
- Security Management Process (risk analysis, risk management, sanction policy, information system activity review)
- Assigned Security Responsibility
- Workforce Security (authorisation, workforce clearance, termination procedures)
- Information Access Management (authorisation, access establishment, access modification)
- Security Awareness and Training
- Security Incident Procedures
- Contingency Plan (data backup, disaster recovery, emergency mode, testing, applications/data criticality)
- Evaluation
- Business Associate Contracts

### §164.310 — Physical Safeguards
- Facility Access Controls (contingency operations, security plan, access control/validation, maintenance records)
- Workstation Use
- Workstation Security
- Device and Media Controls (disposal, media re-use, accountability, backup/storage)

### §164.312 — Technical Safeguards (the most M365-relevant section)
- **§164.312(a)(1) Access Control:**
  - Unique User Identification (required)
  - Emergency Access Procedure (required)
  - Automatic Logoff (addressable)
  - Encryption and Decryption (addressable, but see NPRM — likely to become required)
- **§164.312(b) Audit Controls:** implement hardware, software, and procedural mechanisms that record and examine activity.
- **§164.312(c)(1) Integrity:** protect ePHI from improper alteration or destruction.
  - Mechanism to Authenticate ePHI (addressable)
- **§164.312(d) Person or Entity Authentication:** verify identity of persons/entities accessing ePHI.
- **§164.312(e)(1) Transmission Security:**
  - Integrity Controls (addressable)
  - Encryption (addressable)

### §164.314 — Organizational Requirements
- Business Associate Contracts content
- Group Health Plan requirements

### §164.316 — Policies, Procedures, and Documentation Requirements
- Policies / procedures documented; retain 6 years from later of creation or last effective date.

## "Required" vs "Addressable"

A long-standing Security Rule quirk: safeguards are tagged "Required" or "Addressable". Addressable does **not** mean optional. It means: implement if reasonable and appropriate; if not, document why and implement an equivalent alternative.

The 2025 NPRM proposes removing the distinction — making all safeguards required. If finalised, that elevates encryption, automatic logoff, and integrity mechanisms from addressable to mandatory. Configure tenants now as if these were required; the direction of travel is clear.

## What M365 can and cannot satisfy

### Technical Safeguards (§164.312) — M365 is directly relevant

| Safeguard | M365 workload / control |
|---|---|
| (a)(2)(i) Unique User ID | Entra user lifecycle; no shared accounts; PIM for privileged |
| (a)(2)(ii) Emergency Access | Break-glass accounts documented, MFA-excluded (physical token only), monitored |
| (a)(2)(iii) Automatic Logoff | CA session controls (sign-in frequency); Windows inactivity policy via Intune |
| (a)(2)(iv) Encryption / Decryption | Purview sensitivity labels with encryption; BitLocker via Intune; Customer Key (E5) for keys-you-hold scenarios |
| (b) Audit Controls | Unified Audit Log enabled; Exchange mailbox auditing; Defender logging; retained to policy |
| (c)(1) Integrity | Purview retention + litigation hold; versioning in SharePoint/OneDrive |
| (c)(2) Authentication of ePHI | Digital signatures via S/MIME where required; rights management |
| (d) Authentication | CA requiring phishing-resistant MFA; authentication methods policy restricts weak methods |
| (e)(1) Transmission Security | TLS enforcement; Office Message Encryption; S/MIME |

### Administrative (§164.308) — M365 partial support
- Information system activity review → Purview Audit KQL dashboards, Secure Score trend.
- Workforce security / access management → Entra lifecycle workflows, Access Reviews, PIM.
- Security incident procedures → Defender XDR workflow, documented response plan.
- Contingency plan (backup, DR) → third-party M365 backup, documented BC/DR, tested.

### Physical (§164.310) — largely out of tenant scope
- Facility controls are the hosting provider's (Microsoft attests through ISO 27001, SOC, HITRUST on the Service Trust Portal).
- Device controls (workstation security, disposal) are handled via Intune: compliance, encryption, remote wipe, conditional access based on compliance.

### Privacy Rule — process-heavy, M365 configurable where relevant
- Minimum necessary: sensitivity-label-driven access; Purview Information Barriers for divisional segregation.
- Right of access (§164.524) / amendment (§164.526) / accounting of disclosures (§164.528) → operational processes; M365 provides audit trails that evidence compliance.

### Breach Notification — M365 supplies evidence, organisation runs the process
- Detection: Defender, Purview DLP, Entra risk detections.
- Forensics: Unified Audit Log, mailbox audit, SharePoint audit.
- 60-day deadline from discovery to individual notification; contemporaneous HHS notification for breaches affecting 500+ individuals.

## Related files

- [security-rule.md](security-rule.md) — expanded Security Rule reference.
- [privacy-rule.md](privacy-rule.md) — Privacy Rule reference.
- [m365-translation.md](m365-translation.md) — HIPAA → M365 mapping table.
- [breach-notification.md](breach-notification.md) — notification workflow and M365 evidence flow.
- [baa-scope.md](baa-scope.md) — BAA scope tracking per tenant (template).
