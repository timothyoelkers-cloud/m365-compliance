# NIS 2 — Incident Reporting (Art 23)

> **Note the cadence difference from DORA.** DORA: 4h / 72h / 1mo. NIS 2: 24h / 72h / 1mo. Entities bound by both must satisfy the stricter timing for each obligation.

## Thresholds

A "significant incident" under Art 23(3) is one that:

(a) has caused or is capable of causing severe operational disruption of the services or financial loss for the entity concerned; **or**
(b) has affected or is capable of affecting other natural or legal persons by causing considerable material or non-material damage.

## Cadence

| Report | Deadline (from awareness of the significant incident) |
|---|---|
| Early warning | ≤ 24 hours |
| Incident notification | ≤ 72 hours |
| Intermediate report | On authority request |
| Final report | ≤ 1 month after notification |

### Early warning content (24h)
- Whether suspected to be caused by unlawful or malicious acts.
- Whether could have cross-border impact.

### Incident notification content (72h)
- Initial assessment of severity and impact.
- Indicators of compromise, where available.

### Final report content (1 month)
- Detailed description of the incident, its severity and impact.
- Type of threat / root cause.
- Mitigation measures applied and ongoing.
- Where applicable, cross-border impact.

## M365 evidence supply — per phase

### Awareness → 24h window
- Defender XDR incident detail (impacted users, devices, attack story).
- Entra risky sign-in report for affected IDs.
- Initial Unified Audit Log query over the incident window.

### 24h → 72h window
- Refined timeline.
- Data exfil assessment: Purview DLP hits, SharePoint/OneDrive access logs, Exchange transport rule hits.
- Lateral movement indicators: Defender for Identity, Entra sign-in anomalies.
- Containment actions logged: CA policy updates, user token revocations, device compliance flips.

### 72h → 1 month window
- Full forensic bundle.
- Root cause (phishing vector? credential theft? exploited vuln? misconfig?).
- Permanent remediation: CA hardening, authentication method policy changes, revised Intune baseline.
- Lessons documented in baseline repo — baseline version bumped.

## National reporting portals

Each Member State designates:
- **CSIRT** — receives the notification.
- **Competent authority** — supervisory body.

These differ by state. The skill's per-state annex ([national-transpositions.md](national-transpositions.md)) records portal URL, format, language, and any additional national reporting obligations (e.g. Germany's BSI portal, France's ANSSI, Ireland's NCSC).

## Interaction with GDPR notifications

If the NIS 2 incident also constitutes a personal data breach, **GDPR Art 33 (72h)** notification to the DPA runs in parallel. NIS 2 authorities and GDPR supervisors will coordinate. Evidence packages overlap but are not identical — the NIS 2 report focuses on operational disruption; GDPR focuses on impact to data subjects.
