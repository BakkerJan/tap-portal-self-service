# TAP Portal

This repository contains two deployable TAP portal solutions:

1. Legacy solution (SWA + Functions + Logic App): see [README-legacy.md](README-legacy.md)
2. Secretless solution (SWA SPA + App Service API + Managed Identity): see [README-secretless.md](README-secretless.md)

## Quick start (automated)

Use one script to publish either solution or both.

```powershell
.\infra\publish-all.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -TenantId <TENANT_ID> \
  -DeployLegacy $true \
  -DeploySecretless $true \
  -LegacyClientId <LEGACY_APP_CLIENT_ID> \
  -LegacyClientSecret <LEGACY_APP_CLIENT_SECRET>
```

Notes:

- For legacy deployment, `LegacyClientId` and `LegacyClientSecret` are required for SWA EasyAuth.
- Secretless deployment is fully automated by `infra/publish-secretless.ps1`.

## Simple publishing plan (for other teams)

1. Keep `main` as the release branch.
2. Run `infra/publish-all.ps1` from CI (or manually) with environment-specific parameters.
3. Promote by environment via script parameters (resource group names, app names, location).
4. Validate with health checks:
   - Secretless API: `/healthz`
   - Portal sign-in and TAP flow
5. Keep Conditional Access in report-only first, then enforce.

## Recommended CI inputs

- `AZURE_SUBSCRIPTION_ID`
- `AZURE_TENANT_ID`
- `LEGACY_CLIENT_ID` (legacy only)
- `LEGACY_CLIENT_SECRET` (legacy only)

This keeps publishing simple and repeatable for other folks without manually stepping through portal configuration each time.
