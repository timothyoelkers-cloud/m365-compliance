# NIS 2 — National Transpositions

> **Status snapshot — April 2026.** NIS 2 is a Directive; the operative law is the national transposition in each Member State. Transposition deadline was 17 October 2024; most Member States were late. The European Commission issued reasoned opinions against 19 Member States on 7 May 2025 for failing to notify full transposition.
>
> **Always verify the current status with the competent authority before advising a specific customer.** National laws continue to evolve and enabling decrees/secondary legislation lag primary legislation.

## Status at a glance

| Member State | Status (April 2026) | National law | Effective date | Competent authority | CSIRT |
|---|---|---|---|---|---|
| **Italy** | ✅ Transposed | Legislative Decree 138/2024 | 16 October 2024 | ACN (Agenzia per la Cybersicurezza Nazionale) | CSIRT Italia |
| **Malta** | ✅ Transposed | NIS 2 Ordinance | 8 April 2025 | MDIA / Cyber Malta | Cyber Malta CSIRT |
| **Portugal** | ✅ Transposed | Decree-Law 125/2025 | 4 December 2025 | CNCS (Centro Nacional de Cibersegurança) | CERT.PT |
| **Austria** | ✅ Published (pre-effect) | NISG 2026 | In force 1 October 2026 (published 23 December 2025) | BMI / GovCERT Austria | GovCERT / CERT.at |
| **Belgium** | ✅ Transposed | Belgian NIS2 law | Effective 2024–2025 (verify) | CCB (Centre for Cybersecurity Belgium) | CERT.be |
| **Germany** | ✅ Transposed | NIS-2-Umsetzungsgesetz (amending BSIG) | **In force 6 December 2025** | BSI (Bundesamt für Sicherheit in der Informationstechnik) | CERT-Bund |
| **Netherlands** | ⏳ Not yet transposed | (draft Cyberbeveiligingswet / Cbw) | Pending adoption | Ministerie van Justitie en Veiligheid (NCSC) | NCSC-NL |
| **Ireland** | ⏳ Not yet transposed | (NIS 2 Directive Regulations — draft) | Pending adoption | NCSC Ireland | NCSC Ireland |
| **Spain** | ⏳ Not yet transposed (nearing completion) | (draft Anteproyecto de Ley de Coordinación y Gobernanza de la Ciberseguridad) | Pending | INCIBE / CCN | CCN-CERT / INCIBE-CERT |
| **France** | ⏳ Not yet transposed (legislative process ongoing) | (draft — Senate adopted 12 March 2025; National Assembly to complete in first half of 2026) | Expected 2026 | ANSSI | CERT-FR |
| **Poland** | ⏳ Not yet transposed (nearing completion) | (draft amendment to Act on National Cybersecurity System) | Pending | Ministry of Digital Affairs | CERT Polska |

Status notes:

- "✅ Transposed" means the national law has been enacted and applies (or has a published effective date in the near future).
- "⏳ Not yet transposed" means primary legislation has not been enacted as of April 2026. EC infringement proceedings are active for most of these.
- "Nearing completion" indicates a draft bill is in late-stage parliamentary process.

## Per-state detail

### Germany — NIS-2-Umsetzungsgesetz

- **Name:** *Gesetz zur Umsetzung der NIS-2-Richtlinie und zur Stärkung der Cybersicherheit* (amending the BSI Act, *BSIG*).
- **Status:** in force **6 December 2025**.
- **Competent authority:** BSI (Federal Office for Information Security).
- **CSIRT:** CERT-Bund (operated by BSI).
- **Registration portal:** [https://www.bsi.bund.de](https://www.bsi.bund.de) — opened **6 January 2026** for in-scope entities.
- **Registration deadline:** within **3 months** of the law's effective date — i.e., by early April 2026. Entities not yet registered should do so immediately.
- **Reporting portal:** same BSI portal — incident notifications submitted there.
- **Scope expansion:** from ~4,500 regulated organisations under the prior law to approximately **29,500** under NIS 2.
- **Fine ceilings:**
  - "Particularly important" entities (*besonders wichtige Einrichtungen*): up to **€10m or 2%** of global annual turnover.
  - "Important" entities (*wichtige Einrichtungen*): up to **€7m or 1.4%** of global turnover.
- **Notable national top-ups:**
  - Broader sector scope than the Directive in some areas.
  - Detailed technical implementation expectations via BSI-Grundschutz / IT-Grundschutz and BSI technical guidance.
  - Strong alignment with existing sector regulators (BaFin for financial services, BNetzA for telecoms/energy).
- **Source:** <https://www.privacyworld.blog/2025/12/germany-implements-nis2-registration-portal-will-open-on-january-6-2026/>
- **Source:** <https://www.globalpolicywatch.com/2026/01/germany-transposes-nis-2-directive-increased-cybersecurity-requirements-for-businesses/>

### France — draft law (not yet enacted)

- **Name:** bill on critical infrastructure resilience and strengthened cybersecurity (transposing NIS 2, CER Directive, and DORA alongside).
- **Status:** Senate adopted draft **12 March 2025**; National Assembly committee review through 2025; final adoption expected first half of **2026**.
- **Competent authority:** ANSSI (Agence nationale de la sécurité des systèmes d'information).
- **CSIRT:** CERT-FR (operated by ANSSI).
- **Reporting portal:** MonEspaceNIS2 — <https://monespacenis2.cyber.gouv.fr/>.
- **Fine ceilings:** aligned to Directive minima.
- **Notes:** France's transposition is notable for simultaneously transposing NIS 2 + CER Directive + interlocking with DORA; secondary decrees will specify sectoral details. Expect staged implementation.
- **Source:** <https://cyber.gouv.fr/reglementation/cybersecurite-systemes-dinformation/directives-nis-nis2-et-dispositif-saiv/directive-nis-2/>
- **Source:** <https://www.nis-2-directive.com/Transposition/France.html>

### Italy — Legislative Decree 138/2024

- **Name:** *Decreto legislativo 4 settembre 2024, n. 138* ("D.lgs. 138/2024").
- **Status:** in force **16 October 2024** (first Member State to transpose in the region).
- **Competent authority:** ACN (Agenzia per la Cybersicurezza Nazionale).
- **CSIRT:** CSIRT Italia.
- **Notes:** broad sectoral scope; transposition closely mirrors the Directive with limited national top-ups.

### Netherlands — Cyberbeveiligingswet (draft)

- **Name:** *Cyberbeveiligingswet* (Cbw) — draft.
- **Status:** not yet enacted as of April 2026. Consultation and parliamentary review ongoing.
- **Competent authority (planned):** Ministerie van Justitie en Veiligheid; NCSC-NL for some sectors; sector-specific supervisors for others.
- **CSIRT:** NCSC-NL.
- **Notes:** the Netherlands has sector-specific competent authorities (e.g. AFM/DNB for finance overlapping with DORA).

### Ireland — S.I. NIS 2 Directive Regulations (draft)

- **Name:** Statutory Instrument transposing NIS 2 (draft).
- **Status:** not yet enacted as of April 2026.
- **Competent authority (planned):** NCSC Ireland.
- **CSIRT:** NCSC Ireland.
- **Notes:** parliamentary timetable slipped. Industry expects adoption during 2026.

### Spain — draft law of coordination and governance of cybersecurity

- **Name:** *Anteproyecto de Ley de Coordinación y Gobernanza de la Ciberseguridad*.
- **Status:** draft in late-stage review as of early 2026.
- **Competent authority (planned):** INCIBE, CCN, sector-specific supervisors.
- **CSIRT:** CCN-CERT, INCIBE-CERT.

### Poland — amendment to the Act on National Cybersecurity System

- **Name:** draft amendment to *Ustawa o krajowym systemie cyberbezpieczeństwa*.
- **Status:** late-stage parliamentary process.
- **Competent authority (planned):** Ministry of Digital Affairs; CSIRT NASK / CSIRT MON / CSIRT GOV.

### Belgium — transposed

- **Name:** Belgian NIS2 Act (verify final title at point of customer engagement).
- **Competent authority:** CCB (Centre for Cybersecurity Belgium).
- **CSIRT:** CERT.be.

### Austria — NISG 2026

- **Name:** *Netz- und Informationssystemsicherheitsgesetz 2026* (NISG 2026).
- **Published:** 23 December 2025. **In force:** 1 October 2026.
- **Competent authority:** BMI (Bundesministerium für Inneres); sector-specific supervisors for banking/health/etc.
- **CSIRT:** GovCERT Austria; CERT.at.
- **Notes:** late entry into force gives in-scope entities an unusual amount of on-ramp time.

### Portugal — Decree-Law 125/2025

- **Name:** *Decreto-Lei n.º 125/2025*.
- **Published:** 4 December 2025.
- **Competent authority:** CNCS (Centro Nacional de Cibersegurança).
- **CSIRT:** CERT.PT.

### Malta — NIS 2 Ordinance

- **Published:** 8 April 2025.
- **Competent authority:** Malta Digital Innovation Authority (MDIA) / Cyber Malta.
- **CSIRT:** Cyber Malta CSIRT.

## Cross-border / multi-state tenants

Where a customer operates across multiple Member States:

1. **Identify the Member State(s) of establishment.** NIS 2 applies to the Member State where the entity is established; for certain sectors (e.g. DNS, TLD, cloud providers, data centres, content delivery networks, online marketplaces, search engines, social networks), Art 26 establishes *main establishment* rules so a single lead authority applies.
2. **Subsidiaries vs. branches.** Check whether local subsidiaries are independently in-scope.
3. **Reporting channels.** Incidents typically reported to the CSIRT of the lead authority, with information-sharing to other affected Member States via the CSIRTs Network.
4. **Double reporting (NIS 2 + DORA + GDPR).** Financial entities bound by DORA also report per DORA (to the ESA/national supervisor); NIS 2 reporting may still apply for non-ICT incidents. Personal data breaches continue to require GDPR Art 33 notification. Harmonise the incident response playbook to generate each required submission from a single evidence base.

## Sources

- ECSO NIS2 Transposition Tracker: <https://ecs-org.eu/activities/nis2-directive-transposition-tracker/>
- European Commission — NIS2 transposition page: <https://digital-strategy.ec.europa.eu/en/policies/nis-transposition>
- OpenKRITIS NIS 2 implementation tracker: <https://www.openkritis.de/eu/eu-nis-2-member-states.html>
- NIS 2 Directive portal: <https://www.nis-2-directive.com/>
- Wavestone NIS 2 transposition status overview: <https://www.wavestone.com/en/insight/nis-2-european-countries-transposing-directive/>
- Bird & Bird — European Cybersecurity Regulatory Update: <https://www.twobirds.com/en/insights/2025/european-cybersecurity-regulatory-update-nis2-and-beyond>

## Update cadence

Review this file at minimum:

- Quarterly — check for new transpositions among the "⏳ Not yet transposed" list.
- On customer engagement into a new Member State.
- On EC infringement developments (Court of Justice referrals, financial sanctions).
