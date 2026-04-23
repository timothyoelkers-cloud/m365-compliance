# HIPAA — BAA Scope Tracking (per tenant)

> Microsoft's BAA is offered under the Online Services Terms and covers specific M365 / Azure services. Not all features are in-scope. Verify per tenant; re-verify when Microsoft updates the BAA or when the tenant adds new services.

## Record per tenant

```yaml
tenant_id: <GUID>
tenant_name: <legal name>
baa_accepted_on: <date>
baa_accepted_by: <admin name + UPN>
baa_version: <Microsoft BAA revision date>
in_scope_services:
  - Exchange Online
  - SharePoint Online
  - OneDrive for Business
  - Teams
  - Purview (specify components)
  - Intune
  - Defender (specify components)
  - Azure AD / Entra ID
out_of_scope_or_unverified:
  - <service>: <reason>
review_due: <date 12 months out>
owner: <role / person>
```

## Common gotchas

- **Preview / beta features** are typically not covered by BAA. Do not process ePHI through preview features.
- **Third-party apps / add-ons** installed into the tenant are separate processors; each needs its own BAA with the customer.
- **Bookings, Forms, Sway, Whiteboard, Lists, Power Platform** — BAA coverage varies by component and region; verify per engagement.
- **Connected services (LinkedIn, Whiteboard external collaboration, etc.)** may process data outside the BAA — disable or restrict.
- **Azure OpenAI / Copilot for Microsoft 365** — confirm current BAA coverage and data handling; enterprise data protection applies to Copilot for M365 but check specific add-ins and agents.

## Verification procedure

Quarterly (or on any licence change):

1. Pull current Microsoft BAA document.
2. Compare in-scope services list against tenant licensing and active workloads.
3. Inventory third-party applications consented into the tenant; confirm BAA status for each.
4. Log any gaps; remediate by disabling non-covered workloads or obtaining BAA coverage.
