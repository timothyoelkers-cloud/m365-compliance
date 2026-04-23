# Control Map — Human-Readable Mirror

Machine-readable source of truth: [map.csv](map.csv). This file documents the **shape** of the map with a subset of representative rows grouped by control so a single policy's cross-framework signature is visible at a glance.

For comprehensive lookups, query the CSV (e.g. `awk -F',' '$5=="cis-m365" {print}' map.csv`).

## Map rows by control (representative sample)

### `m365.entra.ca.mfa-phishing-resistant`

**Control:** Conditional Access — require phishing-resistant MFA (FIDO2 / WHfB / cert-based) for administrators (extend to all users for stricter posture).
**Workload:** Entra ID — CA policy with `authenticationStrength: phishing-resistant-mfa`.

| Framework | Reference | Coverage | Notes |
|---|---|---|---|
| CIS M365 v6.0.1 | 5.2.2.5 | primary | L2; admin scope. Broaden to all users for stricter posture. |
| DORA | Art 9(2)(d), RTS 2024/1774 Art 20–21 | primary | Logical access control |
| NIS 2 | Art 21(2)(j) | primary | MFA / secure authentication |
| HIPAA | §164.312(d) | primary | Posture already matches expected NPRM MFA mandate |

### `m365.entra.ca.mfa-all-users`

**Control:** Conditional Access — MFA for all users.

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 5.2.2.2 | primary |
| DORA | Art 9(2)(d) | primary |
| NIS 2 | Art 21(2)(j) | primary |
| HIPAA | §164.312(d) | primary |

### `m365.entra.ca.block-legacy-auth`

**Control:** CA blocks legacy authentication protocols.

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 5.2.2.3 | primary (L1) |
| DORA | Art 9(2)(e) | partial — pair with TLS |
| NIS 2 | Art 21(2)(e) | partial |
| HIPAA | §164.312(e) | partial |

### `m365.entra.pim.just-in-time`

**Control:** PIM JIT for privileged roles (plus approval for GA / Privileged Role Admin activation).
**Prereq:** Entra ID P2.

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 5.3.1 (L2), 5.3.4 (L1), 5.3.5 (L1) | primary / partial |
| DORA | Art 9(2)(d) | partial |
| NIS 2 | Art 21(2)(i) | partial |
| HIPAA | §164.308(a)(4) | partial |

### `m365.entra.access-reviews.privileged`

**Control:** Access Reviews for privileged roles (and guests).

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 5.3.3 | primary |
| DORA | Art 9(2)(d) | partial |
| NIS 2 | Art 21(2)(i) | primary |
| HIPAA | §164.308(a)(4)(ii)(C) | primary |

### `m365.purview.audit.unified-log-enabled`

**Control:** Microsoft 365 audit log search enabled (UAL ingestion).

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 3.1.1 | primary (L1) |
| DORA | Art 10, RTS 2024/1774 | partial — detection foundation |
| NIS 2 | Art 21(2)(b) | partial — incident handling evidentiary foundation |
| HIPAA | §164.312(b) | primary — Audit Controls |

### `m365.purview.dlp.enabled` / `m365.purview.dlp.teams`

**Control:** DLP policies enabled (general + Teams scope).

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 3.2.1 (L1), 3.2.2 (L1) | primary |
| DORA | Art 9(2)(c) | primary — confidentiality |
| NIS 2 | Art 21(2)(a) | partial |
| HIPAA | §164.308(a)(1)(ii)(D) | partial |

### `m365.purview.sensitivity-labels.published`

**Control:** Sensitivity label policies published.

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 3.3.1 | primary (L1) |
| DORA | Art 9(2)(c) | primary |
| NIS 2 | Art 21(2)(h) | primary — cryptography policy |
| HIPAA | §164.312(a)(2)(iv) | primary — encryption |

### `m365.intune.compliance.gate`

**Control:** Devices without a compliance policy are marked not-compliant (default gate).

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 4.1 (L2) | primary |
| DORA | Art 7 | partial |
| NIS 2 | Art 21(2)(e) | partial |
| HIPAA | §164.310(c) | primary — workstation security |

### `m365.exchange.mail-forwarding-blocked`

**Control:** All forms of mail forwarding blocked (remote domains, outbound spam policy, transport rules).

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 6.2.1 | primary (L1) |
| DORA | Art 9(2)(c) | partial — confidentiality |
| NIS 2 | Art 21(2)(a) | partial |
| HIPAA | §164.312(e) | primary — transmission security |

### `m365.exchange.dkim` / `m365.exchange.dmarc` / `m365.exchange.spf`

**Control:** SPF / DKIM / DMARC for all Exchange domains.

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 2.1.8, 2.1.9, 2.1.10 | primary (L1) / partial (DNS external) |
| DORA | Art 9(2)(e) | partial |
| NIS 2 | Art 21(2)(a), (e) | partial |

### `m365.teams.federation.restricted` / `m365.teams.unmanaged-blocked`

**Control:** Teams external domain allow-list; block unmanaged Teams users.

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 8.2.1 (L2), 8.2.2 (L1) | primary |
| DORA | Art 9(2)(c) | partial |
| NIS 2 | Art 21(2)(d) | partial — supply chain / partner boundary |

### `m365.powerbi.publish-to-web` / `m365.powerbi.guest-restricted`

**Control:** Power BI — restrict Publish-to-Web; restrict guest access.

| Framework | Reference | Coverage |
|---|---|---|
| CIS M365 v6.0.1 | 9.1.4, 9.1.1 | primary (L1) |
| DORA | Art 9(2)(c) | partial |
| HIPAA | §164.502 | partial — minimum necessary |

## Coverage density snapshot

As of the current [map.csv](map.csv):

- **CIS M365 v6.0.1:** ~80 rows, covering sections 1, 2, 3, 4, 5.1, 5.2, 5.3, 6.1, 6.2, 6.5, 7.2, 8.2, 8.4, 8.5, 9.1.
- **DORA:** ~25 rows, biased toward Art 9 (protection) and Art 10 (detection); Art 11–14 (response, recovery, learning, comms), Chapter III reporting, Chapter IV testing, and Chapter V TPP remain process-heavy and off-tenant.
- **NIS 2:** ~20 rows, biased toward Art 21(2)(j), (i), (b), (e); Art 20 governance and Art 23 reporting are off-tenant.
- **HIPAA:** ~15 rows, biased toward §164.312 Technical Safeguards; Privacy Rule and Breach Notification rows reference specific obligations but rely on process beyond M365.

Expand rows as deployment agents come online and expose new control IDs.
