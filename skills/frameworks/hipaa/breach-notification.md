# HIPAA Breach Notification — 45 CFR 164.400–414

## What triggers notification

A "breach" is the acquisition, access, use, or disclosure of PHI in a manner not permitted under the Privacy Rule which compromises the security or privacy of the PHI, **unless** a risk assessment establishes a low probability that the PHI has been compromised based on at least these four factors (§164.402):

1. Nature and extent of the PHI involved (identifiers, types, likelihood of re-identification).
2. The unauthorised person who used the PHI or to whom the disclosure was made.
3. Whether the PHI was actually acquired or viewed.
4. Extent to which the risk to the PHI has been mitigated.

**Encryption safe harbour:** if PHI is "unusable, unreadable, or indecipherable" to unauthorised persons (per HHS guidance — meets NIST-specified encryption), its unauthorised disclosure is not a breach. This is why encryption-by-default matters so much.

## Deadlines

| Notification | Deadline |
|---|---|
| Individuals | Without unreasonable delay, **≤ 60 days** from discovery |
| HHS Secretary — breach ≥ 500 individuals | Concurrently with individual notice |
| HHS Secretary — breach < 500 | Annually, within 60 days of year-end |
| Media (breach ≥ 500 residents of a State or jurisdiction) | Without unreasonable delay, ≤ 60 days |

Business Associates must notify Covered Entities "without unreasonable delay and no later than 60 days from discovery" (§164.410); CE's 60-day clock starts from **when the BA discovered** (or reasonably should have) when the BA is an agent.

## M365 evidence flow

### Detection

- Defender XDR incidents (BEC, data-theft alerts).
- Purview DLP high-severity alerts on PHI sensitivity labels or trainable classifiers.
- Entra risky sign-ins / atypical travel.
- Third-party tenant security monitoring (e.g. Sentinel).

### Assessment (risk determination against the 4 factors)

- Scope: which mailboxes/sites accessed — Purview Content Search, Exchange audit.
- Volume/type of PHI: classifier hits from Purview; sensitivity label inventory of impacted items.
- Actor identity: Entra sign-in logs, token source, IP geolocation.
- Was data acquired/viewed: Exchange message tracking, SharePoint/OneDrive file activity, download counts.
- Mitigation: encryption status of affected items (encrypted-at-rest is table stakes; sensitivity-label encryption with rights not shared to actor can reach the safe harbour).

### Decision outcomes

1. **Not a breach** (permitted disclosure, or 4-factor low-probability conclusion). Document decision and retain evidence.
2. **Breach requiring notification.** Proceed to notification workflow.

### Notification artefacts

- Individual notice — content required by §164.404: description, types of info, steps individuals should take, what covered entity is doing, contact info. Templated, retained per tenant.
- HHS notice via the OCR breach portal.
- Media notice (prominent media outlet in the affected jurisdiction).
- BA-to-CE notice with required detail.

## Playbook

1. **T+0 (detection):** open incident in Defender; freeze the incident; tag with `HIPAA-breach-assessment`.
2. **T+0 — preserve:** legal hold on implicated mailboxes/sites; export audit logs for the window; snapshot CA + auth policies.
3. **T+≤24h — contain:** revoke tokens, force password reset, tighten CA, revoke app consent if relevant.
4. **T+≤7d — risk assessment:** formal 4-factor determination documented.
5. **T+≤60d — notify (if required):** individuals, HHS (if ≥500), media (if ≥500 in a state). BA workflow parallel.
6. **T+≤ongoing — remediate + lessons learned:** baseline updates, training, retrospective.

## Templates — to be built

- Individual notice letter (plain-language, §164.404 content).
- HHS portal submission data.
- BA-to-CE notice.
- 4-factor risk assessment template.
- Retrospective / root-cause document.
