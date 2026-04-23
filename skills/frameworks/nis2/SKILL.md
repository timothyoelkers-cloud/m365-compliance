---
name: nis2
description: EU NIS 2 Directive — Directive (EU) 2022/2555. Use when the user references NIS 2, essential or important entities, critical infrastructure cybersecurity obligations, or the 24h/72h incident reporting timeline. Transposition deadline was 17 October 2024; many Member States were late, so the applicable law is the national transposition in each Member State, not the Directive directly.
---

# NIS 2 — Directive on measures for a high common level of cybersecurity across the Union

Directive (EU) 2022/2555. Transposition deadline **17 October 2024**. Replaces the original NIS Directive (2016/1148). As a **Directive**, it applies via national transposition — the operative law in each Member State is the local NIS 2 implementation, which can diverge in detail (thresholds, sectoral scope, penalty levels).

## When this skill applies

- User asks about NIS 2, essential vs important entities, or critical infrastructure cyber obligations.
- User is configuring a tenant for an organisation in one of the 18 sectors NIS 2 covers.
- User asks about the 24h/72h/1-month incident-reporting cadence (distinct from DORA's 4h/72h/1-month).
- User asks about management body accountability / personal liability for senior managers (Art 20).

## Scope — who is bound

NIS 2 covers **18 sectors** split between "essential" (Annex I) and "important" (Annex II).

**Essential (Annex I) — 11 sectors:**
- Energy (electricity, district heating/cooling, oil, gas, hydrogen)
- Transport (air, rail, water, road)
- Banking
- Financial market infrastructures
- Health (healthcare providers, reference labs, pharma, medical devices producing critical products)
- Drinking water
- Waste water
- Digital infrastructure (IXPs, DNS service providers, TLD registries, cloud computing service providers, data centre service providers, CDN providers, trust service providers, providers of public electronic communications networks or services)
- ICT service management (B2B) (managed service providers, managed security service providers)
- Public administration (of central governments, and with Member State discretion, regional)
- Space

**Important (Annex II) — 7 sectors:**
- Postal and courier services
- Waste management
- Manufacture/production/distribution of chemicals
- Production, processing and distribution of food
- Manufacturing (medical devices, computer/electronic/optical, electrical equipment, machinery, motor vehicles, other transport equipment)
- Digital providers (online marketplaces, search engines, social networking platforms)
- Research

**Size threshold:** generally "medium or larger" (≥ 50 headcount or >€10m turnover), but with size-independent carve-outs for certain critical sectors (trust service providers, TLD, DNS, public comms, public admin, etc.).

Entities may be designated irrespective of size by national authorities where disruption would have a significant impact.

## Obligations summary

### Art 20 — Governance
- Management bodies **approve** cybersecurity risk-management measures.
- Management bodies **supervise** implementation.
- Management bodies are **personally accountable** for non-compliance; may bear personal liability.
- Management bodies must **follow training** on cyber risk.

Art 20 is a substantial shift from NIS 1. Failure is enforced at the individual manager level.

### Art 21 — Cybersecurity risk-management measures
Minimum measures (Art 21(2)) — ten broad areas:

| Ref | Measure |
|---|---|
| (a) | Policies on risk analysis and information system security |
| (b) | Incident handling |
| (c) | Business continuity (backup, DR, crisis management) |
| (d) | Supply chain security — direct suppliers and service providers |
| (e) | Security in network/information systems acquisition, development, and maintenance — including vulnerability handling and disclosure |
| (f) | Policies and procedures to assess the effectiveness of cybersecurity risk-management measures |
| (g) | Basic cyber hygiene practices and cybersecurity training |
| (h) | Policies and procedures regarding use of cryptography and, where appropriate, encryption |
| (i) | Human resources security, access control policies, asset management |
| (j) | Use of multi-factor or continuous authentication; secured voice/video/text communications; secured emergency communication systems |

"All-hazards approach" — physical and environmental considerations included (Art 21(3) covers physical protection of ICT).

### Art 23 — Reporting obligations

The reporting cadence that everyone cites:

| Report | Deadline (from awareness of the significant incident) |
|---|---|
| **Early warning** | ≤ **24 hours** — indicates if incident is suspected to be caused by unlawful or malicious acts, or could have a cross-border impact |
| **Incident notification** | ≤ **72 hours** — updates the early warning with initial assessment of severity and impact |
| **Intermediate report** | On CSIRT/authority request |
| **Final report** | ≤ **1 month** after notification — detailed description, type of threat/root cause, mitigation measures, cross-border impact |

"Significant incident" — causes severe operational disruption or financial loss to the entity, or is capable of affecting other persons by causing considerable material or non-material damage.

### Art 24 — Use of certified ICT products, services, processes
- Member States may require use of certified ICT (EUCC, EUCS once adopted, etc.).

### Art 32–35 — Supervision and enforcement
- Enforcement powers differ for essential vs important entities (proactive vs ex-post).
- Administrative fines: up to €10m or 2% of global annual turnover (essential entities) / €7m or 1.4% (important).
- Suspension of management or temporary ban on individuals in senior management roles — a live enforcement lever.

## What M365 can and cannot satisfy

| Art 21(2) measure | M365 contribution |
|---|---|
| (a) Risk analysis & IS security policy | Policy library in SharePoint with retention; Entra role assignments document responsibility |
| (b) Incident handling | Defender XDR incident queue; Entra risky sign-in alerts; audit log; KQL hunting via Defender/Sentinel |
| (c) Business continuity | Third-party backup (M365 native retention ≠ backup); documented RTO/RPO; tabletop evidence |
| (d) Supply chain security | Entra app consent restrictions, third-party app governance, conditional access for partner tenants (cross-tenant access settings) |
| (e) Secure development / vulnerability mgmt | Defender Vulnerability Management; Intune patch compliance; app registrations hardening |
| (f) Effectiveness assessment | Secure Score trend; Defender recommendation history; internal/external audit logs |
| (g) Basic hygiene + training | Attack simulation training (Defender); awareness campaigns via Viva Learning / third-party |
| (h) Cryptography | Sensitivity labels with encryption; Purview Customer Key (E5); TLS enforcement on Exchange; S/MIME |
| (i) HR security / access control / asset management | Entra joiner/mover/leaver via lifecycle workflows; PIM; Intune inventory; Access Reviews |
| (j) MFA / secure comms / emergency comms | CA-enforced MFA (phishing-resistant preferred); Teams policies; out-of-band comms for crisis |

Governance (Art 20), reporting workflow (Art 23), certified-product requirement (Art 24), and enforcement interactions are **not** M365-configurable — they are organisational/process obligations.

## National transposition caveat

NIS 2 is a directive. The **operative law** is each Member State's transposition (e.g. Germany's NIS-2-Umsetzungsgesetz, France's transposition in the Code de la sécurité intérieure, Ireland's NIS 2 Directive Regulations). Details that vary:

- Exact sector scope and size thresholds (national "top-ups" permitted).
- Competent authority and CSIRT designation.
- Reporting portal and format.
- Fine ranges (Directive sets minimum maxima, states may go higher).
- Registration deadlines for entities.

**Before advising a specific customer, confirm which Member State(s) they're bound under and consult the national act.** This skill records Directive-level obligations; national overlays go in a per-state annex (to be created).

## Related files

- [articles.md](articles.md) — article-by-article detail.
- [m365-translation.md](m365-translation.md) — NIS 2 → M365 mapping.
- [reporting.md](reporting.md) — 24/72/1-month workflow details.
- [national-transpositions.md](national-transpositions.md) — stub for per-Member-State notes.
