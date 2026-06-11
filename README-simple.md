# Simple Approach Guide

## What this is

Use this approach if you want the fastest setup with minimal moving parts.

Architecture:

- Static Web App frontend (`portal/`)
- Static Web App managed API (`api/`)
- Logic App for TAP creation

## When to choose this

Choose Simple when:

1. You need to get started quickly.
2. You are okay with a smaller architecture footprint.
3. You want easy operations with fewer components.

## Requirements

1. Azure subscription and tenant permissions.
2. TAP enabled in Entra Authentication Methods.
3. Azure CLI, PowerShell, Node.js, npm.
4. Entra app registration (single-tenant) for SWA auth.

## Step-by-step

1. Deploy infrastructure.

```powershell
az group create --name rg-tap-portal --location westeurope
az deployment group create \
  --name main \
  --resource-group rg-tap-portal \
  --template-file .\infra\main.bicep \
  --parameters staticWebAppName=swa-tap-portal logicAppName=logic-tap-portal staticWebAppSku=Standard
```

2. Create Entra app registration with:
   - Single tenant audience
   - Web redirect URI: `https://<simple-swa-host>/.auth/login/aad/callback`

3. Create client secret and securely store:
   - App ID (client ID)
   - Client Secret value

4. Set SWA app settings:

```powershell
az staticwebapp appsettings set \
  --name swa-tap-portal \
  --resource-group rg-tap-portal \
  --setting-names AZURE_CLIENT_ID=<APP_ID> AZURE_CLIENT_SECRET=<APP_SECRET>
```

5. Publish app and sync backend runtime config:

```powershell
.\infra\publish-swa.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -ResourceGroupName rg-tap-portal \
  -StaticWebAppName swa-tap-portal \
  -LogicAppName logic-tap-portal \
  -TenantId <TENANT_ID>
```

## Testing checklist

1. Open frontend URL.
2. Sign in successfully.
3. Request TAP.
4. Confirm TAP is shown with countdown.
5. Verify Entra audit log entry for TAP creation.
