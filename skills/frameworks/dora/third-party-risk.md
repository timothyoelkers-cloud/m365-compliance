# DORA — Third-Party ICT Risk (Chapter V)

> **Stub — expand with Microsoft-specific artefacts (Service Trust Portal, DPA, Financial Services Amendment, Azure/M365 audit reports) and a per-tenant register template.**

## Why this chapter matters for M365

Microsoft is the provider; the financial entity is the customer. Chapter V regulates that relationship. Microsoft may itself be designated a **critical ICT third-party service provider (CTPP)** under Art 31 — in which case the ESAs supervise Microsoft's services directly via the oversight framework (Art 32–44). Customer obligations under Chapter V persist regardless.

## Customer-side obligations (summary)

### Art 28 — Principles
- Proportionate risk management of TPP relationships; integrated into ICT risk framework.

### Art 28(3) — Register of information
- Maintain register of all ICT TPP contractual arrangements.
- Register format is defined by Implementing Technical Standards (ITS Art 28(9)). Report annually to competent authority.

### Art 29 — Preliminary assessment of concentration risk
- Before contracting, assess concentration risk (single-provider, geographic, intra-group).

### Art 30 — Contractual provisions (mandatory list)
- Full description of functions and services.
- Locations where functions are performed and data processed.
- Provisions on data protection, availability, authenticity, integrity, confidentiality.
- Service level descriptions with quantitative and qualitative targets.
- Assistance by the TPP during ICT incidents.
- Cooperation with competent authorities; access and audit rights.
- Termination rights and notice periods.
- Participation in the financial entity's awareness and training programmes.
- Exit strategies / transition plans.

Additional requirements for **contracts supporting critical or important functions** (Art 30(3)).

### Art 30(5) — Termination rights
- Mandatory termination rights on: material breach; significant changes; weaknesses in TPP's ICT risk management; supervisory impediments.

## Microsoft-specific artefacts

Link once audited:

- **Microsoft Online Services Terms** — baseline contract.
- **Microsoft Products and Services Data Protection Addendum (DPA)** — data protection clauses.
- **Financial Services Amendment** — adds financial regulator-specific clauses (audit rights, notification duties, sub-processor transparency, termination rights). **Accept per tenant** for DORA-bound customers; not automatic.
- **Service Trust Portal** — attestations (ISO 27001/27017/27018, SOC 1/2/3, etc.) and audit reports.
- **Microsoft's Service Level Agreements** — quantitative availability commitments.

## Register template (sketch)

| Field | Source |
|---|---|
| TPP legal entity | Contract |
| Provider's DORA contact | Contract / TPP portal |
| Service(s) provided | Business mapping |
| Is function critical / important? | Internal classification |
| Tenant ID / subscription ID | Entra tenant ID |
| Data categories processed | Purview classification + business mapping |
| Locations (processing, storage) | Tenant geography, Multi-Geo config, Azure regions |
| Sub-processors | Microsoft sub-processor list (published) |
| Contract effective date, review date, termination notice | Contract |
| Exit strategy | Internal runbook |
| SLAs (qualitative + quantitative) | Microsoft SLA + measurements |
| Audit rights exercised | Audit record |
| Last concentration risk review | Internal review log |

## Exit strategy — M365-specific

A credible DORA exit strategy for M365 addresses:

- Data extraction: Exchange PST export or Graph API bulk pull, SharePoint/OneDrive via SPO Migration API or M365 backup vendor export, Teams via export tools.
- Identity: break-glass accounts independent of Azure AD B2C where relevant; federation/migration plan.
- Runtime: where do Exchange/Teams workloads move to? There is rarely a hot-standby — exit implies degraded service during migration, document that explicitly.
- Timeline: realistic exit timelines for M365 are measured in months, not days. Disclose to authorities.

## Concentration risk

Common risk concentrations to record:

- Single-provider: Microsoft for productivity + identity + endpoint. Diversification options: separate identity provider, alternate email/chat for crisis comms, independent MFA token.
- Geographic: EU tenant geo with limited alternative regions; sanctions risk on specific regions.
- Intra-group: if multiple group entities share one tenant, a tenant-level outage cascades.
