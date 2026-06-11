# Advanced Approach Guide

## What this is

Use this approach for stronger separation of concerns and secretless backend access to Graph.

Architecture:

- Static Web App frontend (`portal-secretless/`)
- Node API on App Service (`secretless-api/`)
- Managed Identity to call Microsoft Graph

## When to choose this

Choose Advanced when:

1. You want stronger backend security controls.
2. You prefer managed identity over app secrets for Graph access.
3. You want independent scaling of frontend and backend.

## Requirements

1. Azure subscription and tenant permissions.
2. TAP enabled in Entra Authentication Methods.
3. Azure CLI, PowerShell, Node.js, npm.

## Step-by-step

1. Run automated deployment:

```powershell
.\infra\publish-secretless.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -TenantId <TENANT_ID>
```

2. Script automatically does:
   - Infrastructure deployment
   - Entra app registration setup
   - API scope and consent setup
   - Managed identity Graph permission setup
   - Backend and frontend deployment

3. Verify API health endpoint:

```powershell
Invoke-WebRequest -Uri "https://<advanced-webapp>.azurewebsites.net/healthz" -UseBasicParsing
```

4. Verify frontend sign-in and TAP request.

## Testing checklist

1. Frontend loads and sign-in works.
2. Anonymous POST to `/api/request-tap` returns 401.
3. Authenticated TAP request returns success.
4. Countdown and one-time display behavior works.
5. Entra audit logs show TAP creation.
