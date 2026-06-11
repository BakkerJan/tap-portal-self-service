# Legacy TAP Portal (SWA + Functions + Logic App)

## Overview

Legacy solution using:

- Azure Static Web Apps (`portal/`)
- SWA-managed Azure Functions API (`api/`)
- Logic App for Graph TAP creation

Flow:

1. User signs in via SWA EasyAuth.
2. Browser calls `/api/request-tap`.
3. API sends server-side request to Logic App trigger.
4. Logic App managed identity calls Microsoft Graph to create TAP.

## Prerequisites

- Azure subscription and tenant access
- Temporary Access Pass enabled in Entra ID
- Azure CLI (`az`)
- PowerShell
- `npx @azure/static-web-apps-cli`

You also need a single-tenant app registration for SWA EasyAuth:

- Client ID
- Client secret

## Deploy (simple)

1. Deploy or update infrastructure:

```powershell
az group create --name rg-tap-portal --location westeurope
az deployment group create \
  --name main \
  --resource-group rg-tap-portal \
  --template-file .\infra\main.bicep \
  --parameters staticWebAppName=swa-tap-portal logicAppName=logic-tap-portal staticWebAppSku=Standard
```

2. Configure SWA EasyAuth settings:

```powershell
az staticwebapp appsettings set \
  --name swa-tap-portal \
  --resource-group rg-tap-portal \
  --setting-names AZURE_CLIENT_ID=<CLIENT_ID> AZURE_CLIENT_SECRET=<CLIENT_SECRET>
```

3. Publish code + sync callback settings:

```powershell
.\infra\publish-swa.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -ResourceGroupName rg-tap-portal \
  -StaticWebAppName swa-tap-portal \
  -LogicAppName logic-tap-portal \
  -TenantId <TENANT_ID>
```

## Security notes

- Logic App callback secret is stored in SWA app settings, not in browser code.
- Conditional Access should target the legacy app registration client ID.
- Prefer report-only CA first, then enforce.

## Typical troubleshooting

- Sign-in loop: verify `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET` in SWA app settings.
- TAP request errors: re-run `infra/grant-graph-permissions.ps1` for the Logic App managed identity.
- Wrong tenant: verify `EXPECTED_TENANT_ID` in app settings.
