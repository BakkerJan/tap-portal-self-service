# Secretless TAP Portal (SWA SPA + App Service API + Managed Identity)

## Overview

Modern solution using:

- Azure Static Web Apps for frontend (`portal-secretless/`)
- Node API on Azure Web App (`secretless-api/`)
- Managed identity for Microsoft Graph
- No shared secrets in frontend code

Flow:

1. Frontend signs in with MSAL PKCE.
2. Frontend sends access token to backend `/api/request-tap`.
3. Backend validates token tenant/audience/scope.
4. Backend uses managed identity to call Graph TAP API.

## Prerequisites

- Azure subscription and tenant access
- Temporary Access Pass enabled in Entra ID
- Azure CLI (`az`)
- PowerShell
- Node.js and npm
- `npx @azure/static-web-apps-cli`

## Deploy (fully automated)

```powershell
.\infra\publish-secretless.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -TenantId <TENANT_ID>
```

What this script automates:

1. Deploys infra from `infra/main-secretless.bicep`
2. Creates/updates Entra app registrations and API scope
3. Grants Graph permission to backend managed identity
4. Writes frontend runtime config (`portal-secretless/config.js`)
5. Packages and deploys backend API
6. Deploys frontend to Static Web Apps

## Runtime checks

- API health: `https://<webapp-name>.azurewebsites.net/healthz`
- Anonymous API call should return 401 on `/api/request-tap`
- Frontend loads from SWA host and signs in successfully

## Security notes

- Backend binds to `WEBSITES_PORT` first for App Service reliability.
- Frontend has hardened security headers in `portal-secretless/staticwebapp.config.json`.
- CA policy should include this frontend app registration client ID.
- Backend uses `EXPECTED_TENANT_ID`, `EXPECTED_TOKEN_AUDIENCES`, and `REQUIRED_SCOPE` to constrain token trust.

## Typical troubleshooting

- Sign-in stuck: hard refresh and check browser console/network.
- `Microsoft sign-in library failed to load`: verify `/vendor/msal-browser.min.js` is reachable from SWA.
- Backend 404/health issues: ensure startup command and port binding are correct.
- API 403 scope issues: confirm app registration scope consent was granted.
