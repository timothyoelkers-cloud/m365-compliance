# HIPAA Security Rule — 45 CFR 164 Subpart C

Full catalogue of Security Rule standards and implementation specifications, annotated for M365.

> **Status as of April 2026:** NPRM published 6 January 2025; comments closed 7 March 2025. Final rule is on OCR's regulatory agenda for **May 2026**, with compliance ~240 days after publication. Until that publishes, the 2013 Omnibus-era Security Rule below is the operative law — but configure tenants for the proposed strengthening, as the technical delta is small and the documentation delta needs a runway.

## §164.308 Administrative Safeguards

### §164.308(a)(1) Security Management Process

- (i) Risk Analysis — **Required**
- (ii) Risk Management — **Required**
- (iii) Sanction Policy — **Required**
- (iv) Information System Activity Review — **Required**
  - M365: Unified Audit Log review cadence; Secure Score reviews; Defender alert triage logs.

### §164.308(a)(2) Assigned Security Responsibility — **Required**

- Named security official. M365 relevance: role documented in Entra role catalogue.

### §164.308(a)(3) Workforce Security

- (i) Authorization/Supervision — Addressable
- (ii) Workforce Clearance Procedure — Addressable
- (iii) Termination Procedures — Addressable
  - M365: Entra lifecycle workflows (leaver) revoke access; automated token revocation; access review on sensitive groups.

### §164.308(a)(4) Information Access Management

- (i) Isolating Health Care Clearinghouse Functions — Required if applicable
- (ii) Access Authorization — Addressable
- (iii) Access Establishment and Modification — Addressable
  - M365: Entra role assignments, PIM, Access Reviews, admin units for segmented administration.

### §164.308(a)(5) Security Awareness and Training

- (i) Security Reminders — Addressable
- (ii) Protection from Malicious Software — Addressable
  - M365: Defender for Endpoint, Defender for O365, ASR rules.
- (iii) Log-in Monitoring — Addressable
  - M365: Entra sign-in logs, risky sign-in alerts.
- (iv) Password Management — Addressable
  - M365: Entra password protection, banned password list, no expiry (current guidance), MFA.

### §164.308(a)(6) Security Incident Procedures

- (i) Response and Reporting — Required
  - M365: Defender XDR incident workflow, documented runbook, post-mortem template.

### §164.308(a)(7) Contingency Plan

- (i) Data Backup Plan — Required
- (ii) Disaster Recovery Plan — Required
- (iii) Emergency Mode Operation Plan — Required
- (iv) Testing and Revision Procedures — Addressable
- (v) Applications and Data Criticality Analysis — Addressable
  - M365: third-party backup for ePHI, documented RTO/RPO, tested annually, out-of-band crisis comms.

### §164.308(a)(8) Evaluation — **Required**

- Periodic technical and non-technical evaluation.
- M365: Secure Score cadence, internal audits, third-party assessments.

### §164.308(b)(1) Business Associate Contracts — **Required**

- Microsoft BAA is the baseline; downstream BAs (e.g. third-party ISV vendors integrated with the tenant) need their own BAAs.

## §164.310 Physical Safeguards

Largely Microsoft's responsibility for the platform; customer responsibility for endpoints (addressed via Intune).

### §164.310(a)(1) Facility Access Controls

- (i) Contingency Operations — Addressable
- (ii) Facility Security Plan — Addressable
- (iii) Access Control and Validation Procedures — Addressable
- (iv) Maintenance Records — Addressable

### §164.310(b) Workstation Use — Required

- M365: Intune configuration profiles enforce workstation policies.

### §164.310(c) Workstation Security — Required

- M365: BitLocker via Intune, screen lock timeout, device compliance.

### §164.310(d)(1) Device and Media Controls

- (i) Disposal — Required
- (ii) Media Re-use — Required
- (iii) Accountability — Addressable
- (iv) Data Backup and Storage — Addressable
  - M365: Intune wipe on lost/retired devices; media handling procedures; device encryption.

## §164.312 Technical Safeguards

### §164.312(a)(1) Access Control

- (i) Unique User Identification — Required
- (ii) Emergency Access Procedure — Required
- (iii) Automatic Logoff — Addressable
- (iv) Encryption and Decryption — Addressable (likely to become Required under NPRM)

### §164.312(b) Audit Controls — Required

- M365: Unified Audit Log on, mailbox auditing on, Purview Audit high-value events (E5) where available.

### §164.312(c)(1) Integrity

- (ii) Mechanism to Authenticate Electronic Protected Health Information — Addressable
  - M365: versioning, checksums, retention, legal hold.

### §164.312(d) Person or Entity Authentication — **Required**

- M365: CA with phishing-resistant MFA, FIDO2, Windows Hello for Business.

### §164.312(e)(1) Transmission Security

- (i) Integrity Controls — Addressable
- (ii) Encryption — Addressable
  - M365: TLS enforcement, OME, S/MIME where relevant.

## §164.314 Organizational Requirements

- (a) Business Associate Contracts — content.
- (b) Group Health Plan requirements.

## §164.316 Policies and Procedures and Documentation Requirements

- (a) Policies and procedures.
- (b) Documentation — retain 6 years from later of creation or last effective date.
  - M365: SharePoint policy library + Purview retention label "HIPAA-6yr" set to 6 years from last-modified.

## NPRM — proposed additions (January 2025)

If finalised (check current status), notable additions include:

- Mandatory MFA across systems.
- Encryption-by-default (at rest + in transit).
- Vulnerability scanning ≥ every 6 months; penetration testing ≥ every 12 months.
- Asset inventory kept current; technology review ≥ annually.
- Patching on specified timelines (e.g. 15 days for critical CVEs).
- Incident response procedures tested; written review of procedures ≥ annually.
- Workforce configuration / device management documentation.
- Explicit MFA / access-control requirements for ePHI relevant information systems.

These align closely with a strict CIS M365 L1+L2 deployment plus Intune + Defender for Endpoint / Vulnerability Management. Organisations that have already adopted a mature M365 baseline will not face a large technical uplift; the delta is governance and documentation.
