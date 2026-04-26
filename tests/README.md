# tests/

End-to-end fixture tests for the baseline merger + diff engine. Two parallel implementations both run against the same synthetic fixture; agreement = the diff logic is sound. Drift = a real bug.

## What's here

```text
tests/
├── README.md                    (this file)
├── build_fixture.py             Regenerate manifest.json with correct SHA-256 chain
├── verify_fixture.py            Python port of merger + diff engine — runs locally without pwsh
├── end-to-end.Tests.ps1         Pester test — runs the canonical PowerShell engines
├── expected-findings.json       Ground truth (12 findings); both implementations must produce this
└── fixtures/
    └── synthetic-tenant-001/
        ├── tenant.yaml          Synthetic tenant — id 00000000-0000-0000-0000-aaaa…aa
        └── scan-bundle/
            ├── manifest.json    Computed by build_fixture.py
            ├── bundle.sha256    Hash chain (computed)
            ├── entra.json
            ├── conditional-access.json
            ├── exchange.json
            ├── sharepoint.json
            ├── teams.json
            ├── purview.json
            ├── defender.json
            └── intune.json
```

## What the fixture exercises

The synthetic scan bundle has a deliberate mix of **passing** and **failing** values across every workload that the diff engine knows about. The 12 expected findings exercise:

| Compare mode | Exercised by |
|---|---|
| `equals`              | `entra.weak-auth-voice-disabled`, `sharepoint.sharing-capability`, `teams.anonymous-cannot-join`, `teams.federation-consumer-blocked`, `teams.lobby-bypass-restricted`, `sharepoint.guest-expire-required`, `sharepoint.prevent-external-resharing`, `exchange.auto-forwarding-off` |
| `invertedEquals`      | `exchange.mailbox-audit-on` (audit-disabled = true means audit is off) |
| `allTrue`             | `exchange.dkim-enabled-for-all` (one domain disabled in fixture) |
| `tenantSettingDisabled` (deferred) | `powerbi.publish-to-web-restricted`, `powerbi.guest-access-restricted` (no powerbi.json in bundle → deferred) |

Plus checks that **don't** produce findings (passing) — `entra.tenant-creation-restricted`, `entra.weak-auth-sms-disabled`, `entra.fido2-enabled`, `entra.admin-count-min/max/cloud-only`, `ca.block-legacy-auth-present`, `ca.break-glass-excluded-from-user-blocks`, `exchange.smtp-auth-disabled`, `purview.ual-enabled`, `purview.dlp-policies-present`, `purview.sensitivity-labels-published`, `sharepoint.default-link-type/permission`, `intune.non-compliant-by-default`. Coverage of compare-modes for those: `equals`, `presentAndNotEmpty`, `greaterOrEqual`, `lessOrEqual`, `equalsZeroWhenBaseline`, `allTrue`.

## Running locally (no pwsh required)

```bash
python3 tests/verify_fixture.py             # assert == expected; exit 0 = pass
python3 tests/verify_fixture.py --print     # print actual findings JSON
python3 tests/verify_fixture.py --update    # overwrite expected (use only when fixture changes)
```

The Python verifier mirrors the merger and diff engine in ~250 lines. It loads `scripts/common/diff-rules.yaml` directly — so a rule edit there is visible to the verifier on the next run.

## Running canonical (Pester, requires pwsh)

```powershell
Install-Module Pester           -Scope CurrentUser -AcceptLicense -Force
Install-Module powershell-yaml  -Scope CurrentUser -AcceptLicense -Force
Invoke-Pester -Path tests/end-to-end.Tests.ps1 -Output Detailed
```

The Pester test runs the actual `Resolve-Baseline.ps1` and `Compare-TenantState.ps1` and asserts the output matches `expected-findings.json`.

## Iterating on the fixture

When you intentionally change a scan JSON, a baseline profile, or a rule:

1. Edit the file(s).
2. `python3 tests/build_fixture.py` (only if you changed any JSON in `scan-bundle/` — recomputes manifest SHAs).
3. `python3 tests/verify_fixture.py --print` (eyeball findings — do they match what you intended?).
4. `python3 tests/verify_fixture.py --update` (lock in as expected).
5. Commit fixture + expected together. The Pester test must agree on the next CI run.

## When Python and Pester disagree

That's the signal you most want to see, because it's a real bug.

- **Most likely:** one engine handled a `compareMode`, dot-path edge case, or merge semantic differently.
- **Diagnose by:** running `python3 tests/verify_fixture.py --print > /tmp/actual-py.json` and `Compare-TenantState` → `/tmp/actual-ps1.json`, then `diff` them.
- **Resolution:** fix the engine that's wrong, not the expected.

Two-implementation cross-checks are deliberately annoying when they fail — that's their value. Don't bypass.

## What the fixture covers — apply path

Beyond the diff engine, the fixture also exercises [`scripts/apply/Set-ConditionalAccess.ps1`](../scripts/apply/Set-ConditionalAccess.ps1) in `plan` mode. The expected plan ([`expected-ca-plan.json`](expected-ca-plan.json)) asserts:

- 12 `create` actions for baseline CA policies not in the synthetic tenant.
- 1 `unchanged` action against `cis-l1-ca-001-block-legacy-auth` — the baseline-to-Graph normaliser maps the baseline's `include` / `exclude_groups` to Graph's `includeUsers` / `excludeGroups` and strips empty fields, so equivalent policies compare equal even though their on-disk encoding differs.
- 1 `untracked` action against the tenant's `CIS L1 — Require MFA for all users` policy, because `nis2-ca-030-phishing-resistant-all` *replaces* `cis-l1-ca-002-mfa-all-users` at merge time — the original baseline id is gone, so no displayName matches.
- 0 safety invariant blocks.
- The script throws when `apply` mode is invoked without `-ApprovalRef`.

The Python verifier ([verify_fixture.py](verify_fixture.py)) ports the planning logic so this assertion runs locally without pwsh; the Pester test runs the canonical PowerShell script in CI.

## Real bugs this fixture has caught

(Document drift here as it happens — provides a permanent record of why the fixture exists.)

- **2026-04-24** — `cis-l1-l2.yaml` profile claimed in description to be a combined "L1 + L2" profile but was implemented as L2-additive-only. Fixture forced this contradiction into the open by producing only 2 findings on first run instead of the expected ~12. Resolved by clarifying metadata + requiring tenants to layer cis-l1 first.
- **2026-04-24** — `auto_forwarding_mode: Off` in `cis-l1.yaml` and `dora-overlay.yaml`. YAML 1.1 parses bare `Off` as boolean `false`; Microsoft's `Set-HostedOutboundSpamFilterPolicy -AutoForwardingMode` expects the string `'Off'`. Apply path would have silently rejected the value in production. Fixed by quoting.
- **2026-04-24** — `evidence-bundle.schema.json` rejected real production bundles because `integrity.signature` was `type: object` only, but `Invoke-TenantScan.ps1` sets it to `null` when no signing cert is supplied. Loosened to `["object", "null"]`.
- **2026-04-26** (CA apply) — Baseline encoding doesn't match Graph encoding. Baseline YAML uses `include` / `exclude_groups`; Graph cmdlets emit `includeUsers` / `excludeGroups`. Fixture surfaced this as a phantom "drift in conditions" finding on every CA policy. **Fixed 2026-04-26**: `ConvertTo-GraphCaPolicy` (PowerShell) and `normalise_baseline_ca_policy` (Python) both apply the rename map + strip empty/null fields before diff. `cis-l1-ca-001-block-legacy-auth` now correctly resolves to `unchanged` against the fixture's tenant policy.
