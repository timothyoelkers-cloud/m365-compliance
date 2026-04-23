# DORA — M365 Translation

DORA obligations mapped to concrete M365 configuration. Process obligations (governance, reporting workflow, TPP contracts) sit outside the tenant and are marked as such.

## Format

| DORA ref | Obligation (summary) | M365 workload(s) | Setting / policy | Evidence artefact |
|---|---|---|---|---|

## Chapter II — ICT Risk Management

| DORA ref | Obligation | M365 workload(s) | Setting / policy | Evidence artefact |
|---|---|---|---|---|
| Art 5       | Governance, management body accountability | — | Out-of-scope for tenant config | Policy docs, minutes |
| Art 7       | Up-to-date, reliable ICT systems | Entra, Intune, Exchange | Block legacy auth (CA), Intune compliance baseline, disable SMTP AUTH tenant-wide | CA policy JSON; Exchange `*-TransportConfig` export |
| Art 8       | Asset identification | Entra, Intune, Defender | Devices registered/joined; Intune MDM; Defender onboarded | Device inventory exports (Graph) |
| Art 9(2)(a) | Security of networks and infrastructure | Entra, Exchange, SharePoint | CA location policies, Exchange connector TLS, SharePoint access controls | Policy JSON exports |
| Art 9(2)(b) | Minimisation of impact of ICT risk | Intune, Defender | ASR rules, AV, tamper protection, EDR in block mode | Defender config export |
| Art 9(2)(c) | Authenticity, integrity, confidentiality of data | Purview, Entra | Sensitivity labels, encryption, DLP | Purview label / policy export |
| Art 9(2)(d) | Physical/logical access control | Entra, PIM | CA (require compliant device + MFA), PIM for admin roles | CA policies, PIM assignments |
| Art 9(2)(e) | Secure networks, encrypted transmission | Exchange, Teams | TLS enforcement, S/MIME where required, Teams meeting policies | Exchange `Get-TransportConfig`, Teams policy export |
| Art 9(2)(f) | Secure remote access | Entra, Intune | CA require compliant device + MFA; block unmanaged device access to sensitive apps | CA policies |
| Art 9(4)(f) | Business function-level access control | Entra | Admin units, role-scoped assignments | Admin unit / role export |
| Art 10      | Detection of anomalous activities | Defender, Entra | Defender XDR alerts, Entra risk policies | Defender incidents, Entra risk events |
| Art 11      | Response and recovery | Purview, Exchange | Litigation hold, in-place hold, retention | Purview retention exports |
| Art 12      | Backup, restoration, recovery | Third-party backup | M365 native retention ≠ backup; document third-party backup | Backup vendor configuration |
| Art 13      | Learning from incidents | Purview Audit, Defender | Unified audit log enabled; incident post-mortem stored | Audit log KQL queries |
| Art 14      | Crisis communication | Teams, Exchange | Dedicated "crisis" Teams channel with reduced external access; out-of-band channel pre-agreed | Teams channel config, runbook |

## Chapter III — Incident Reporting

Reporting itself is an off-tenant process. M365 provides the forensic evidence.

| DORA ref | Input from M365 |
|---|---|
| Art 17 classification | Defender incident timeline, Entra sign-in logs, audit log search |
| Art 18 severity determination | User impact counts (Entra/Defender), data categories affected (Purview sensitivity label hits) |
| Art 19 notification payload | Timeline of events, affected services, mitigation actions |

## Chapter IV — Testing

| DORA ref | M365 role |
|---|---|
| Art 24 general testing | Include M365 tenant in scope: attack simulation training, phishing simulations (Defender), tabletop exercises of Entra lockout/recovery |
| Art 26 TLPT | External testers may engage the live tenant — ensure break-glass accounts, audit logging and Defender alerting are proven beforehand |

## Chapter V — Third-Party Risk

Largely off-tenant, but tenant configuration supports:

| DORA ref | M365 role |
|---|---|
| Art 30 contract terms | Microsoft's Online Services Terms / DPA / Financial Services Amendment are the baseline; verify Financial Services Amendment is accepted for regulated customers |
| Art 28(3) register | Tenant ID, regions, critical service dependencies recorded in register |
| Art 29 concentration risk | Document Azure/M365 dependency posture |

## Level 2 RTS/ITS reference map

Each Level 1 article above consumes detail from the following Level 2 texts:

| Level 1 article | Level 2 text | Purpose |
|---|---|---|
| Art 6, 7, 8, 9, 10, 11, 12, 15, 16 | **Commission Delegated Regulation (EU) 2024/1774** | RTS on ICT risk management framework (full + simplified) |
| Art 18 | **Commission Delegated Regulation (EU) 2024/1772** | RTS on classification of major incidents and significant cyber threats |
| Art 20 (reporting content/timelines) | **Commission Delegated Regulation (EU) 2025/301** | RTS on incident reporting content, timelines, voluntary threat reports |
| Art 20 (templates) | **Commission Implementing Regulation (EU) 2025/302** | ITS — XML schema accepted by all supervisors |
| Art 28(3) | **Commission Implementing Regulation (EU) 2024/2956** | ITS — register of information templates |
| Art 28(10) | **Commission Delegated Regulation (EU) 2024/1773** | RTS on policy for ICT services supporting critical / important functions by TPPs |
| Art 26(11) | RTS on TLPT (verify current Commission Delegated Regulation number) | Advanced testing / threat-led penetration testing |
| Art 30(5) | RTS on subcontracting (verify current Commission Delegated Regulation number) | Subcontracting arrangements |

## Open items

- Confirm the Commission Delegated Regulation numbers for the TLPT RTS and the subcontracting RTS — cross-reference EUR-Lex at engagement time.
- Document Financial Services Amendment acceptance procedure per tenant.
- Link to Microsoft's current DORA compliance statements on the Service Trust Portal (Microsoft has signalled DORA alignment and offers the Financial Services Amendment as an addendum; verify current posture on each engagement).
