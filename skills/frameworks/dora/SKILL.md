---
name: dora
description: EU Digital Operational Resilience Act — Regulation (EU) 2022/2554. Use when the user references DORA, ICT risk management for financial entities, ICT third-party risk, or operational resilience testing. In force since 17 January 2025; applies to ~20 classes of EU financial entity plus critical ICT third-party providers designated by the ESAs.
---

# DORA — Digital Operational Resilience Act

Regulation (EU) 2022/2554. In application from **17 January 2025**. Enforced by ESMA, EIOPA, and the EBA (collectively the ESAs), working with national competent authorities.

DORA is **regulation**, not a directive — it applies directly, no national transposition. That matters: your UK-based Claude interlocutor may be thinking in "directive" terms out of habit.

## When this skill applies

- User is configuring an M365 tenant for a financial entity operating in or providing services to the EU.
- User asks about ICT risk management, operational resilience, incident reporting obligations, or ICT third-party oversight.
- User needs to map a specific DORA article to M365 controls.
- User asks about Regulatory Technical Standards (RTS) or Implementing Technical Standards (ITS) — DORA's detail lives in the Level 2 texts published by the ESAs.

## Scope — who is bound

DORA applies to ~20 categories of EU financial entity, including:

- Credit institutions (banks)
- Payment institutions and e-money institutions
- Investment firms
- Crypto-asset service providers (under MiCA) and issuers of asset-referenced tokens
- Central securities depositories, central counterparties, trading venues
- Trade repositories, securitisation repositories
- Managers of alternative investment funds, UCITS management companies
- Insurance and reinsurance undertakings, insurance intermediaries (with size thresholds)
- IORPs (occupational pensions)
- Credit rating agencies, administrators of critical benchmarks
- Crowdfunding service providers
- Account information service providers

Plus: **ICT third-party service providers designated as "critical"** by the ESAs (this includes hyperscalers where a material volume of regulated EU finance runs on their platforms — Microsoft is a candidate for designation via Azure/M365).

**Proportionality principle (Art 4):** obligations scale with the entity's size, risk profile, and systemic importance. Simplified risk-management framework available for micro-enterprises (Art 16).

## Structure — the five pillars

| Pillar | Chapter | Articles | Focus |
|---|---|---|---|
| 1. ICT Risk Management | Chapter II | Art 5–16 | Governance, identification, protection, detection, response, recovery, learning, communication |
| 2. ICT-related Incident Reporting | Chapter III | Art 17–23 | Incident classification, notification to competent authorities, reporting content/timing |
| 3. Digital Operational Resilience Testing | Chapter IV | Art 24–27 | Testing programmes, including TLPT (threat-led penetration testing) for larger entities |
| 4. Managing ICT Third-Party Risk | Chapter V | Art 28–44 | Contractual requirements, register of information, critical TPP oversight by ESAs |
| 5. Information-Sharing Arrangements | Chapter VI | Art 45 | Voluntary threat intelligence sharing |

**Governance (Art 5)** sits above the pillars — the management body is ultimately accountable and cannot delegate responsibility away.

## What M365 can and cannot satisfy

DORA is an **operational resilience regulation**, not a technical security baseline. Most of its obligations are governance, documentation, testing, and third-party-management processes. M365 configuration supports compliance but does not itself deliver it.

### Where M365 materially helps

| Article | M365 surface |
|---|---|
| Art 7 — ICT systems, protocols, tools | Entra ID baseline, Intune device compliance, Defender XDR |
| Art 8 — Identification (asset inventory) | Entra registered/joined devices, Intune inventory, Defender device inventory |
| Art 9 — Protection and prevention | CA policies, MFA, encryption at rest/in transit, Purview DLP, sensitivity labels |
| Art 10 — Detection | Defender XDR, Entra risk detections, Sentinel ingestion of audit/sign-in logs |
| Art 11 — Response and recovery | Purview retention (legal hold), Exchange litigation hold, backup strategy |
| Art 12 — Backup, restoration, recovery | OneDrive/SharePoint retention, Exchange in-place archiving, third-party backup for BC |
| Art 13 — Learning (post-incident review) | Audit log evidence, Defender incident records |
| Art 14 — Communication | Teams / Exchange with controlled external sharing |

### Where M365 cannot help (process obligations)

- Governance arrangements (Art 5) — board-level responsibility allocation, ICT risk strategy, policies.
- Registers of ICT third-party providers (Art 28(3)) — kept in GRC tooling, not M365.
- TLPT programme (Art 26) — external providers engage, results reported to authorities.
- Major incident reporting to competent authorities (Art 19) — 4-hour initial notification after classification, intermediate report, final report. Process-heavy; M365 sign-in/audit logs supply the forensic data, but the reporting workflow is separate.
- Contractual requirements on ICT TPPs (Art 30) — legal / procurement, outside M365.

## Incident reporting — the clock

Art 19 and the underlying RTS on classification and reporting set tight deadlines for **major** ICT-related incidents:

- **Initial notification:** as early as possible and within **4 hours** of classification (and no later than 24 hours after detection).
- **Intermediate report:** within **72 hours** of the initial notification.
- **Final report:** within **1 month** of the incident.

M365 plays two roles here:

1. **Detection telemetry** — sign-in logs, audit logs, Defender alerts — feeds into the classification decision.
2. **Communications integrity** — Exchange / Teams used to notify authorities must themselves be reliable and protected against the incident.

See [reporting.md](reporting.md) for the classification criteria (severity threshold) and reporting templates.

## How to use this skill

Alongside:

- [cis-m365](../cis-m365/SKILL.md) — for the technical baseline that delivers Art 9 / 10 controls.
- [../../mapping/control-map/SKILL.md](../../mapping/control-map/SKILL.md) — to show a single M365 setting evidencing multiple frameworks.
- DORA-specific stanzas in `baselines/` — stricter CA, audit retention aligned with Art 12, outbound sharing more tightly controlled.

## Related files in this skill

- [articles.md](articles.md) — article-by-article obligations with M365 applicability notes.
- [m365-translation.md](m365-translation.md) — DORA → M365 control mapping table.
- [reporting.md](reporting.md) — incident classification and reporting workflow (stub).
- [third-party-risk.md](third-party-risk.md) — Chapter V obligations with Microsoft-as-provider context (stub).

## Level 2 — the RTS / ITS

DORA's detail lives in Level 2 texts published as Commission Delegated / Implementing Regulations. As of April 2026 the key operative ones are:

| Regulation | Type | Covers | OJ publication |
|---|---|---|---|
| **Commission Delegated Regulation (EU) 2024/1774** | RTS | ICT risk management framework (full + simplified) — Art 15 and Art 16 of DORA. Specifies tools, methods, processes, policies, ICT asset management, encryption, network/operations security, project/change management. | 25 June 2024 |
| **Commission Delegated Regulation (EU) 2024/1772** | RTS | Criteria for classification of major ICT-related incidents and significant cyber threats — Art 18(3) of DORA. 6 classification criteria: clients/counterparties affected, duration, geography, data impact, economic impact, criticality. | 25 June 2024 |
| **Commission Delegated Regulation (EU) 2024/1773** | RTS | Policy on ICT services supporting critical or important functions provided by ICT third-party service providers — Art 28(10) of DORA. | 25 June 2024 |
| **Commission Implementing Regulation (EU) 2024/2956** | ITS | Standard templates for the register of information — Art 28(9) of DORA. | Late 2024 |
| **Commission Delegated Regulation (EU) 2025/301** | RTS | Content, timelines, and reporting obligations for major ICT-related incidents and significant cyber threats — Art 20(a) of DORA. Locks in 4h / 72h / 1mo cadence. | 20 February 2025 |
| **Commission Implementing Regulation (EU) 2025/302** | ITS | Standard forms, templates and procedures for reporting incidents and significant cyber threats — Art 20(b) of DORA. XML format accepted by all supervisors. | 20 February 2025 |
| **Commission Delegated Regulation (EU) 2024/1532** | RTS | Further elements around DORA Level 2 — verify scope against the current EUR-Lex entry before citing. | 2024 |

Additional RTS on TLPT (Art 26(11)) and subcontracting (Art 30(5)) were published through 2024–2025; populate [articles.md](articles.md) with the exact regulation numbers as engagements arise.

Sources for Level 2 tracking:
- <https://ec.europa.eu/finance/docs/level-2-measures/dora-regulation-rts--2024-1532_en.pdf>
- <https://www.esma.europa.eu/press-news/esma-news/esas-publish-first-set-rules-under-dora-ict-and-third-party-risk-management>
- <https://www.regulation-dora.eu/rts>

Level 3 (guidelines) — ESAs continue to publish guidance; check EBA / ESMA / EIOPA regulatory pages before a fresh engagement.

## Critical caveat

Before advising a specific financial entity, cross-reference the consolidated Level 1 text (Regulation 2022/2554) against the currently operative RTS/ITS above and any later additions.
