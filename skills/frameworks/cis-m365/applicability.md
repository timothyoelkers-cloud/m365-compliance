# CIS M365 Benchmark — Applicability

## Licence dependencies

CIS recommendations assume specific M365 licences. Flag unmet prerequisites during baseline selection rather than at apply time.

| Feature required by CIS | Minimum licence |
|---|---|
| Conditional Access (required for most Entra L1 recs) | Entra ID P1 (M365 Business Premium, E3, E5) |
| Risk-based CA (sign-in / user risk) | Entra ID P2 (E5 / E5 Security / Entra Suite) |
| PIM | Entra ID P2 |
| Defender for O365 Plan 1 (Safe Links / Safe Attachments) | M365 Business Premium, E3 with add-on, E5 includes P2 |
| Defender for O365 Plan 2 (attack simulation, threat explorer) | E5 |
| Intune MDM / MAM | Intune plan (included in Business Premium, E3, E5) |
| Purview DLP (SharePoint/OneDrive/Teams) | E3 and above |
| Purview DLP (Endpoint) | E5 Compliance / E5 |
| Sensitivity labels w/ auto-labelling | E5 Compliance / E5 |
| Insider Risk Management | E5 Compliance / E5 |
| Unified Audit Log (basic) | E3+ |
| Audit (Premium) — long retention, high-value events | E5 |

## Tenant classes

Suggest tenant-class tags that drive baseline selection:

| Class | Typical profile | L1 | L2 | Notes |
|---|---|---|---|---|
| `tier-0`          | Tenant with admin-access to others (MSP, Partner, IT-own) | all | most | PIM mandatory, break-glass mandatory, locked down external sharing |
| `regulated-finance` | DORA-bound entity | all | selected | Pair with DORA skill; test schedule differs |
| `regulated-health`  | HIPAA-covered entity | all | selected | Pair with HIPAA skill; BAAs in place for any third-party app |
| `regulated-critical` | NIS 2 essential/important | all | selected | Pair with NIS 2 skill; reporting obligations independent of tenant config |
| `standard-smb`      | Business Premium customer | all | opportunistic | L2 where usability impact is low |
| `dev-or-sandbox`    | Not holding real data | selected | n/a | Don't over-invest; focus on auth/account hygiene |

## Jurisdictional considerations

- **UK** — UK GDPR + DPA 2018 apply to personal data; Cyber Essentials Plus often required for government supply chain. CIS L1 largely covers Cyber Essentials technical controls.
- **EMEA (EU)** — GDPR, NIS 2, DORA (finance), eIDAS. Data residency matters: check tenant geo and Multi-Geo configuration.
- **US** — HIPAA (health), GLBA (finance), SOX (public companies), CMMC (DoD contractors), FedRAMP (federal). CIS is useful technical baseline but does not itself satisfy these; combine with the relevant framework skill.

## Version cadence

CIS publishes updates ~annually. When a new benchmark version drops:

1. Re-ingest the catalogue into `controls.md` with the new version tag.
2. Diff against previous version; generate a changelog of added / removed / changed recommendations.
3. Review baselines in `baselines/examples/` for recommendations that changed default, profile, or remediation.
4. Publish the changelog as an advisory to tenants tagged to this framework.
