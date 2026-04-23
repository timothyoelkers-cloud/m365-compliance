# NIS 2 — M365 Translation

NIS 2 Art 21(2) measures mapped to concrete M365 configuration.

| Art 21(2) ref | Measure | M365 workload(s) | Setting / policy | Evidence artefact |
|---|---|---|---|---|
| (a) | Risk analysis & IS security policy | SharePoint, Purview | Policy repository; sensitivity labels on policy docs; retention | Policy library export |
| (b) | Incident handling | Defender XDR, Sentinel (if used), Purview Audit | Automated investigation enabled; incident queue monitored; audit log ingested | Defender incident exports, Sentinel workbooks |
| (c) | Business continuity | Third-party backup | M365 native retention ≠ backup (see DORA note too); document BC plan, tested | Backup config, DR test reports |
| (d) | Supply chain security | Entra (app consent, cross-tenant access) | Restrict user app consent to verified publishers; admin-consent workflow; cross-tenant access settings | App consent policy; cross-tenant access settings JSON |
| (e) | Secure development / vulnerability handling | Defender Vulnerability Management, Intune | Patch SLAs per device ring; vuln tickets tracked; Defender recommendations monitored | Defender vuln export; Intune compliance |
| (f) | Effectiveness assessment | Secure Score, Defender, Purview | Periodic Secure Score review; internal audit schedule | Secure Score history API |
| (g) | Basic hygiene + training | Defender attack sim, Viva Learning | Phishing sims on a cadence; mandatory training; completion tracked | Attack sim reports |
| (h) | Cryptography / encryption | Purview, Exchange, Teams | Sensitivity labels with encryption; DKE for highly sensitive; TLS enforcement; at-rest encryption (service-managed or Customer Key) | Label definitions; Customer Key config |
| (i) | HR security / access control / asset management | Entra lifecycle workflows, PIM, Intune | JML automation (joiner/mover/leaver); PIM for all privileged roles; Intune inventory; Access Reviews on sensitive groups | Lifecycle workflow export; PIM assignments; Access Review history |
| (j) | MFA / secure comms | Entra CA, Teams, Exchange | CA enforcing phishing-resistant MFA for privileged users; Teams meeting lobby/recording policies; encrypted email for sensitive | CA policies; Teams policies; Exchange S/MIME config |

## Cross-cutting notes

- **Phishing-resistant MFA (Art 21(2)(j))** — NIS 2 references MFA; the regulatory trajectory favours phishing-resistant methods (FIDO2, Windows Hello for Business, certificate-based auth). Configure Entra authentication methods policy to prefer these and use CA authentication strengths.
- **Supply chain security (Art 21(2)(d))** — cross-tenant access settings, guest user governance, and application governance are the M365 surfaces that meaningfully move the needle.
- **Audit log retention** — default audit retention is 180 days (or longer with E5 / add-on). NIS 2 does not set a specific retention, but forensic investigation supporting 1-month reporting requires sufficient historical data; 1 year minimum recommended.

## Measurement

Measure is less about individual settings passing and more about **programme maturity**. Evidence NIS 2 looks for:

- Risk register with M365-specific risks recorded and owned.
- Baseline drift within tolerance thresholds.
- Incident drills executed to schedule (with M365 in scope).
- Training completion > agreed threshold.
- Vulnerability SLA adherence per device ring.
