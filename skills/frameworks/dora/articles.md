# DORA — Article-by-Article Reference

> **Source of truth:** Regulation (EU) 2022/2554 consolidated text + the Commission Delegated / Implementing Regulations listed in [SKILL.md](SKILL.md).
>
> In practice, read each Level 1 article alongside its Level 2 RTS/ITS — the detail is almost always in Level 2.

## Chapter II — ICT Risk Management (Art 5–16)

### Art 5 — Governance and organisation

- **Obligation:** management body defines, approves, oversees, and is responsible for ICT risk management framework. Individual accountability.
- **Level 2:** no direct RTS — but RTS 2024/1774 (ICT risk management framework) presumes the governance foundation is in place.
- **M365 relevance:** none direct; evidence is board minutes, policies, role assignments.

### Art 6 — ICT risk management framework

- **Obligation:** document the framework; review at least annually and after major incidents or supervisor instructions.
- **Level 2:** RTS 2024/1774 sets out the detailed elements.
- **M365 relevance:** Purview retention on policy documents; SharePoint library for policy management.

### Art 7 — ICT systems, protocols, tools

- **Obligation:** use appropriate, up-to-date, reliable ICT systems.
- **Level 2:** RTS 2024/1774 (see specifically its provisions on ICT asset management, change management, project management).
- **M365 relevance:** service-level patching is Microsoft's; tenant-side covers modern-auth enforcement, Intune compliance, supported protocol enforcement (disable legacy auth).

### Art 8 — Identification

- **Obligation:** identify, classify, and document all ICT-supported business functions, information assets, ICT assets, dependencies.
- **Level 2:** RTS 2024/1774 on ICT asset management — requires a current ICT asset inventory maintained with clear ownership, criticality ratings, and dependencies.
- **M365 relevance:** Entra device inventory, Intune inventory, Defender device posture, Purview data classification.

### Art 9 — Protection and prevention

- **Obligation:** implement policies, procedures, protocols and tools to ensure resilience, continuity, availability; preserve data security (CIA + authenticity).
- **Level 2:** RTS 2024/1774 specifies encryption, network security, access control, physical/environmental protection, authentication, application security, vulnerability management.
- **M365 relevance:** heavy — CA, MFA (phishing-resistant), encryption at rest/in transit, Purview DLP, sensitivity labels, privileged access (PIM), network controls.

### Art 10 — Detection

- **Obligation:** detect anomalous activities; multiple layers of control; trigger response.
- **Level 2:** RTS 2024/1774 — continuous monitoring, alert thresholds.
- **M365 relevance:** Defender XDR, Entra risk detections, Identity Protection, Sentinel integration.

### Art 11 — Response and recovery

- **Obligation:** ICT business continuity policy; response and recovery plans tested.
- **Level 2:** RTS 2024/1774 on BCM.
- **M365 relevance:** Exchange/SharePoint/Teams service resilience is vendor's; tenant-side BC includes third-party backup, Purview retention, legal hold readiness.

### Art 12 — Backup, restoration, recovery

- **Obligation:** backup policies; restore testing; geographic separation; integrity.
- **Level 2:** RTS 2024/1774 on backup.
- **M365 relevance:** M365 native retention ≠ backup in the DR sense — procure third-party backup (Veeam, Rubrik, Commvault, Acronis, Keepit, etc.). Document RTO / RPO; test restores; integrity verified via hash.

### Art 13 — Learning and evolving

- **Obligation:** post-incident reviews; continuous improvement; training.
- **M365 relevance:** Defender incident timelines + UAL evidence; training via Defender attack simulation + Viva Learning.

### Art 14 — Communication

- **Obligation:** crisis communication plans; internal + external; consistent with DORA incident reporting obligations.
- **M365 relevance:** Teams/Exchange must remain usable during incident; dedicated crisis Teams with restricted external access; out-of-band comms pre-agreed (SMS gateway, independent phone bridge).

### Art 15 — Further harmonisation (RTS)

- **Level 2:** RTS 2024/1774.

### Art 16 — Simplified framework

- **Obligation:** simplified framework for micro-enterprises and specific smaller entity classes.
- **Level 2:** RTS 2024/1774 covers the simplified regime.

## Chapter III — ICT-related Incident Reporting (Art 17–23)

### Art 17 — ICT-related incident management process

- Detect, manage, notify, report.

### Art 18 — Classification of incidents and significant cyber threats

- **Level 2:** **RTS 2024/1772** sets the 6 classification criteria: clients/counterparties/transactions affected, reputational impact, duration and service downtime, geographic spread, data losses (volume + sensitivity), economic impact, plus criticality of services affected. Materiality thresholds per criterion.
- Significant cyber threats (Art 18(2)) classification also in 2024/1772.

### Art 19 — Reporting of major ICT-related incidents

- Initial notification ≤ 4h from classification (and ≤ 24h from detection).
- Intermediate report ≤ 72h.
- Final report ≤ 1 month.

### Art 20 — Further harmonisation (RTS on content and timing, ITS on templates)

- **Level 2 (content/timelines):** **RTS 2025/301** — content of initial notification, intermediate report, final report; timelines; voluntary notification of significant cyber threats.
- **Level 2 (templates):** **ITS 2025/302** — standard forms, templates, procedures. XML format accepted by supervisors.

### Art 21 — Centralisation of reporting

- Single EU reporting hub (planned; staged implementation).

### Art 22 — Supervisory feedback

### Art 23 — Operational or security payment-related incidents

- Interaction with PSD2 reporting obligations — avoid double reporting.

## Chapter IV — Digital Operational Resilience Testing (Art 24–27)

### Art 24 — General testing requirements

- At minimum annually; scope includes vulnerability assessments and scans, OSS analyses, network security assessments, gap analyses, physical security reviews, questionnaires, scripts, scenario-based tests, compatibility testing, performance/end-to-end testing, penetration testing.

### Art 25 — Testing of ICT tools and systems

- Risk-based, proportionate.

### Art 26 — Advanced testing based on TLPT

- **Threat-led penetration testing** every **3 years** for significant entities. Independent testers. TIBER-EU framework alignment.
- **Level 2:** RTS on TLPT (verify current Commission Delegated Regulation number against EUR-Lex before citing).

### Art 27 — Requirements for testers

- Independence, reputation, technical capability, fit-and-proper checks.

## Chapter V — Managing ICT Third-Party Risk (Art 28–44)

### Art 28 — General principles

- Proportionality, risk-based management of TPP risk. Register of information (Art 28(3)).
- **Level 2:** **ITS 2024/2956** — register-of-information templates.
- **Level 2:** **RTS 2024/1773** — policy on ICT services supporting critical or important functions.

### Art 29 — Preliminary assessment of ICT concentration risk

### Art 30 — Key contractual provisions

- Extensive list of mandatory clauses — location of service, access rights, exit strategy, subcontracting, audit rights, termination rights, incident support.
- **Level 2:** RTS on subcontracting under Art 30(5) — verify current Commission Delegated Regulation number.

### Art 31 — Designation of critical ICT third-party service providers

- ESAs designate critical TPPs based on systemic importance; 2025–2026 rounds ongoing.

### Art 32–44 — Oversight framework for critical TPPs

- Lead overseer designates, investigates, inspects, recommends. First designations happened in late 2024 / through 2025.

## Chapter VI — Information Sharing (Art 45)

### Art 45 — Information-sharing arrangements

- Voluntary exchange of cyber threat information within trusted communities (similar to NIS 2 Art 29–30).

## Sources

- Regulation (EU) 2022/2554 consolidated: <https://eur-lex.europa.eu/eli/reg/2022/2554>
- ESAs joint statement on DORA Level 2: <https://www.esma.europa.eu/press-news/esma-news/esas-publish-first-set-rules-under-dora-ict-and-third-party-risk-management>
- Commission Delegated Regulation (EU) 2024/1774: <https://eur-lex.europa.eu/eli/reg_del/2024/1774>
- Commission Delegated Regulation (EU) 2024/1772: <https://eur-lex.europa.eu/eli/reg_del/2024/1772>
- DORA RTS overview: <https://www.regulation-dora.eu/rts>
