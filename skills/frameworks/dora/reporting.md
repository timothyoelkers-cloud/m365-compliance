# DORA — Incident Reporting

> **Level 2 status (April 2026):**
>
> - Classification criteria: **Commission Delegated Regulation (EU) 2024/1772** (RTS), OJ 25 June 2024.
> - Content and timelines of reports: **Commission Delegated Regulation (EU) 2025/301** (RTS), OJ 20 February 2025.
> - Standard templates / XML format for reports: **Commission Implementing Regulation (EU) 2025/302** (ITS), OJ 20 February 2025.
>
> All supervisors accept the XML format defined in ITS 2025/302; the report structure is harmonised across the EU.

## Deadlines (Art 19)

From the moment a major ICT-related incident is **classified** (not detected — classified):

| Report | Deadline |
|---|---|
| Initial notification | ≤ 4 hours from classification; and ≤ 24 hours from detection |
| Intermediate report | ≤ 72 hours from initial notification |
| Final report | ≤ 1 month from initial notification |

## Classification (Art 18 + RTS 2024/1772)

An incident is "major" if it meets materiality thresholds on the following criteria, as set out in **Commission Delegated Regulation (EU) 2024/1772**:

1. **Clients, counterparties, transactions affected** (volume and proportion)
2. **Reputational impact**
3. **Duration and service downtime** (total and for critical services)
4. **Geographic spread** (number of Member States affected)
5. **Data losses** (volume and sensitivity — including personal data, confidential business data)
6. **Economic impact** (direct and indirect financial loss)
7. **Criticality of services affected** (whether the incident affects services supporting critical or important functions)

Thresholds differ per entity type (banks, investment firms, insurers, etc.) — consult the RTS annexes.

A **significant cyber threat** is classified where there is a credible risk of an incident meeting those thresholds, even if no incident has yet materialised. Voluntary reporting is encouraged under Art 19(2).

Significant **cyber threats** also have a voluntary reporting path.

## What M365 feeds into each report

### Initial notification (4 hours)

- Incident start time, detection time, classification time.
- Affected services: which M365 workloads involved (Exchange, Teams, SharePoint, Entra).
- Preliminary root cause indicator: Defender incident category; Entra risk detection type.
- Preliminary impact: user count, data categories.

### Intermediate report (72 hours)

- Refined timeline from Defender + audit logs.
- Confirmed root cause or working hypothesis.
- Actions taken: identity revocations, CA policy tightening, device wipes via Intune.
- Residual risk.

### Final report (1 month)

- Complete timeline.
- Root cause analysis.
- Systemic changes — baseline updates, new detection rules, training.
- Lessons learned.

## Evidence preservation

From detection onward:

1. Export Entra sign-in logs for affected users (Graph `/auditLogs/signIns`, filter by user IDs and time window).
2. Export Unified Audit Log for the incident window (`Search-UnifiedAuditLog` or the new Purview Audit API; for E5 tenants, use Audit Premium's high-value events).
3. Freeze Defender incident (do not auto-resolve).
4. Place affected mailboxes / OneDrive accounts on legal hold if data exfiltration suspected.
5. Snapshot CA policies and authentication methods policy at time of incident.

## Reporting templates — ITS 2025/302

The ITS defines a single XML schema used for all three phases (initial / intermediate / final). Key content blocks (indicative — verify against the ITS schema):

- **Entity identification** — LEI, entity type, Member State of competent authority.
- **Incident identification** — unique reference, detection time, classification time, incident start.
- **Affected services** — services supporting critical or important functions, service types.
- **Impact assessment** — per-criterion values matched to the RTS 2024/1772 thresholds.
- **Root cause indicator** — confirmed / suspected / unknown.
- **Mitigation actions** — current, planned.
- **Cross-border relevance** — Member States where impact materialised.
- **Reporting officer contact** — name, role, communications channel for supervisor follow-up.

Submission: the national competent authority's portal (varies per Member State and entity type). Entities with multiple supervisors (e.g. a bank with branches across jurisdictions) must report once and let the lead supervisor coordinate.

### Mapping to M365 evidence

Each content block draws from specific M365 sources:

| Content block | M365 source |
|---|---|
| Incident identification times | Defender XDR incident `createdDateTime`, `firstActivityDateTime`; UAL correlations |
| Affected services | Defender device inventory; Entra service principal logs; Purview activity alerts |
| Impact — clients affected | Exchange message trace; Entra sign-in logs for affected UPNs |
| Impact — duration | Defender incident timeline; correlated audit log continuity |
| Data categories affected | Purview sensitivity label hits; DLP policy rule match counts |
| Root cause | Defender attack chain; Entra risk detection type (for identity-origin incidents) |
| Mitigation actions | Audit log entries showing CA policy updates, token revocations, device compliance flips, Intune wipes |
| Cross-border relevance | Entra sign-in log `locationDetails`; affected tenants in Multi-Geo deployments |

## Building the tenant reporting pipeline

For tenants supporting DORA entities, the evidence pipeline should be pre-wired before the first incident:

1. UAL retention ≥ 1 year (Audit Standard default) or ≥ 10 years (Audit Premium add-on retention).
2. Defender XDR connected to Sentinel (or equivalent SIEM) with retention aligned to the 1-month final report requirement.
3. Purview sensitivity labels deployed so "data categories affected" is answerable without manual classification.
4. Documented KQL queries for each impact criterion, so the 4-hour initial notification does not depend on an individual analyst's familiarity.
5. XML generation: scripted build of the ITS 2025/302 payload from the query outputs.
