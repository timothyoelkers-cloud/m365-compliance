---
name: cis-m365
description: CIS Microsoft 365 Foundations Benchmark — prescriptive technical baseline for M365 tenants. Use when the user references CIS, the CIS benchmark, or asks what specific M365 settings achieve a hardened baseline. Covers Level 1 (practical) and Level 2 (defense-in-depth) profiles across Entra ID, Exchange Online, SharePoint/OneDrive, Teams, Defender, Purview, and Intune.
---

# CIS Microsoft 365 Foundations Benchmark

The CIS M365 Benchmark is the most prescriptive technical baseline available for M365. It maps almost 1:1 to specific admin-centre toggles, Graph API properties, and PowerShell cmdlets — which makes it the right starting point for any tenant hardening conversation and the natural anchor for cross-framework mapping.

## When this skill applies

- User asks "what does CIS say about [feature]"
- User wants a tenant baseline and hasn't named a different framework
- User needs to justify a setting to an auditor in CIS terms
- Deployment agents need the authoritative default for a setting

## Benchmark structure — v6.0.1 (current as of this skill's last review)

**Version:** CIS Microsoft 365 Foundations Benchmark **v6.0.1**
**Released:** v6.0.0 published 31 October 2025; v6.0.1 patch shortly after.
**Total recommendations:** 140 across six services (up from 130 in v5).

Each recommendation has:

- **ID** in dotted form (e.g. `1.1.1`, `2.1.4`)
- **Profile** — Level 1 (L1, minimum viable) or Level 2 (L2, stricter, may impact usability)
- **Scope** — per-user, per-tenant, per-workload
- **Automated / Manual** — whether the check can be scripted
- **Licence prerequisite** — E3, E5, Business Premium, P1/P2, etc.
- **Rationale, Impact, Audit, Remediation, Default value, References**

### v6 benchmark section structure (distinct from "services")

v6 covers **six M365 services** (Entra ID, Exchange Online, SharePoint Online, OneDrive, Teams, Power BI) but its sections are organised by *capability* not by service — several services appear across multiple sections:

| Section | Scope | Workloads touched |
|---|---|---|
| 1. Administrative Accounts / Groups / User Policies | Entra admin hygiene; shared mailboxes; user-owned apps; Sways; Bookings; Forms | Entra ID |
| 2. Exchange Online / Threat Protection | Safe Links/Attachments, anti-phish, anti-spam, SPF/DKIM/DMARC, Priority Account protection, ZAP, Defender for Cloud Apps | Exchange Online, Defender for O365 |
| 3. Data Protection / Governance | UAL enabled, DLP policies (general + Teams), sensitivity-label publication | Purview / Exchange / Teams |
| 4. Device Compliance | Unmanaged-device baseline, personal-device enrollment block | Intune-adjacent (tenant setting) |
| 5. Application & Access Control | **Largest section** — MFA, CA, PIM, authentication methods, guest/external, consent, app tenant policies, Entra join | Entra ID |
| 6. Mail Management | Mailbox audit, mail flow rules, Outlook add-ins, modern auth, SMTP AUTH, Direct Send | Exchange Online |
| 7. SharePoint & OneDrive | Sharing capability, link types, guest expiry, modern auth | SPO, OneDrive |
| 8. Microsoft Teams | External/federation, meetings, app mgmt, file sharing | Teams |
| 9. Power BI | Guest access, publish to web, shareable links, service principals | Power BI |

**Note on Intune and Defender:** v6 does not have dedicated Intune or Defender sections. Device compliance has 2 controls in section 4; endpoint security is assumed to be governed by the separate **CIS Intune Benchmark** and **CIS Windows / macOS benchmarks**. Defender for O365 capability is scattered across sections 2, 3, and 6. If your posture needs full endpoint hardening, pair CIS M365 with CIS Intune + CIS OS benchmarks.

### What changed in v6 vs. v5

Focus areas for additions (13 new controls, 3 retired):

- **Device management** — managed vs unmanaged device controls addressing hybrid work.
- **Collaboration** — Teams meeting policies, external participant controls (counters permissive defaults).
- **Outbound email** — exfiltration monitoring for compromised accounts.
- **Identity governance** — guest lifecycle, privilege reviews to reduce privilege creep.

Sources for this metadata:
- <https://www.cisecurity.org/benchmark/microsoft_365>
- <https://www.reco.ai/blog/cis-microsoft-365-v6-benchmark-guide>

> **Important:** exact recommendation IDs, titles, defaults, and remediation steps come from the CIS-issued PDF/Workbench for v6.0.1. Treat the catalogue in [controls.md](controls.md) as a working draft drafted from v6 structure — verify every row against the authoritative document before relying on it for customer-facing work.

## How to populate this skill

This skill ships with structure; the control catalogue is populated by ingesting the CIS Workbench export or PDF:

1. Pull the current CIS M365 Foundations Benchmark from the CIS Workbench (requires a free account).
2. For each recommendation, add a row to [controls.md](controls.md) in the format defined there.
3. For each recommendation with an automatable check, add PowerShell / Graph API calls to [m365-translation.md](m365-translation.md).
4. Note the CIS version and release date at the top of `controls.md` — benchmarks revise frequently.

## Level selection guidance

- **Level 1** — deploy by default to every managed tenant. Blast radius is low, user-visible impact is minimal, and failing L1 is genuinely negligent.
- **Level 2** — deploy to tenants where the data sensitivity or regulatory burden justifies friction. L2 recommendations frequently disable legacy protocols, enforce device compliance, require stricter Conditional Access, and restrict external sharing.
- **Custom profile** — common in practice: L1 universally + selected L2 items. Document which L2 items and why.

## Interaction with other frameworks

- **DORA** — CIS L1+L2 covers most technical control surface DORA requires (Art 9 protection/prevention, Art 8 identification). Governance/resilience testing articles need separate treatment.
- **NIS 2** — Art 21(2)(d) "supply chain security", (e) "secure development", (g) "basic cyber hygiene" and (i) "HR security" are where CIS does most of the heavy lifting. Governance (Art 20) and reporting (Art 23) are not CIS-shaped problems.
- **HIPAA** — CIS maps well onto the Technical Safeguards (§164.312) and parts of Administrative (§164.308). Physical (§164.310) and most of the Privacy Rule are out of CIS scope.

See [../../mapping/control-map/SKILL.md](../../mapping/control-map/SKILL.md) for worked mapping rows.

## Related files in this skill

- [controls.md](controls.md) — populated control catalogue (when ingested).
- [m365-translation.md](m365-translation.md) — per-recommendation Graph/PowerShell implementation.
- [evidence.md](evidence.md) — what auditors ask for and where it lives.
- [applicability.md](applicability.md) — licence dependencies (E3/E5/Business Premium), workload prerequisites.
