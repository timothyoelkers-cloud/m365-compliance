# HIPAA Privacy Rule — 45 CFR 164 Subpart E

## Key sections (high-level)

- §164.500 — Applicability.
- §164.502 — Uses and disclosures of PHI; general rules; minimum necessary.
- §164.504 — Organizational requirements; hybrid entities; affiliated covered entities.
- §164.506 — Treatment, payment, healthcare operations.
- §164.508 — Authorizations.
- §164.510 — Uses/disclosures requiring opportunity to agree or object.
- §164.512 — Uses/disclosures not requiring authorization (public health, law enforcement, research, etc.).
- §164.514 — De-identification, limited data sets.
- §164.520 — Notice of Privacy Practices.
- §164.522 — Right to request restrictions / confidential communications.
- §164.524 — Individual right of access to PHI.
- §164.526 — Right to amend PHI.
- §164.528 — Accounting of disclosures.
- §164.530 — Administrative requirements (workforce training, complaints, sanctions).

## M365 touch points

The Privacy Rule is primarily operational. M365 supports it via:

| Privacy Rule area | M365 support |
|---|---|
| Minimum necessary | Purview sensitivity labels driving access; Information Barriers for divisional segregation; SharePoint/OneDrive permissions model |
| Right of access (§164.524) | Purview eDiscovery / Content Search to locate PHI across Exchange/SharePoint/OneDrive/Teams and produce within 30 days |
| Right to amend / restrict | Document management in SharePoint with versioning; retention and disposition labels |
| Accounting of disclosures | Unified Audit Log retained sufficient to construct disclosure records |
| Workforce training evidence | Viva Learning completion records or third-party LMS integration |
| Complaints tracking | SharePoint list + Power Automate workflow or third-party case management |

## De-identification
- §164.514(b) "Safe Harbor" requires removal of 18 identifier categories.
- M365 does not provide automated de-identification; Purview can help **identify** PII/PHI via trainable classifiers or out-of-the-box types, but removal is a downstream process (SQL, scripts, or specialised tooling).

## Minimum Necessary with sensitivity labels

Suggested label set for ePHI-bearing environments (tune per customer):

| Label | Visual marking | Encryption | Description |
|---|---|---|---|
| Public | none | no | Non-PHI public information |
| Internal | "Internal" footer | no | Non-PHI internal |
| Confidential — PHI | "CONFIDENTIAL / PHI" | yes, org-wide | Default for anything containing PHI |
| Highly Confidential — PHI Restricted | "RESTRICTED / PHI" | yes, named groups only | Sensitive subsets (e.g. mental health, HIV/AIDS, substance use) with extra legal protections |

Auto-labelling based on trainable classifiers for PHI (HHS-aligned identifier types) can assist but must be reviewed for false positives/negatives before enforcement.
