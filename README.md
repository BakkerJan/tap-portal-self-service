# TAP Portal

This repo supports two deployment approaches:

1. Simple approach: Static Web App + built-in API + Logic App
2. Advanced approach: Static Web App frontend + App Service API + Managed Identity

## Requirements

Before deployment, make sure you have:

1. Azure subscription access with permissions to create resources and app registrations.
2. Entra ID tenant where Temporary Access Pass is enabled.
3. PowerShell 7+.
4. Azure CLI (`az`) installed and signed in.
5. Node.js and npm installed (for frontend deployment tooling).
6. GitHub access if you want CI/CD publishing.

Recommended checks:

```powershell
az account show
az --version
node --version
npm --version
```

## Step-by-step: Simple approach

Use this if you want the quickest setup.

1. Deploy infrastructure.

```powershell
az group create --name rg-tap-portal --location westeurope
az deployment group create \
  --name main \
  --resource-group rg-tap-portal \
  --template-file .\infra\main.bicep \
  --parameters staticWebAppName=swa-tap-portal logicAppName=logic-tap-portal staticWebAppSku=Standard
```

2. Create app registration for SWA sign-in and collect:
  - Client ID
  - Client Secret

3. Publish app and sync runtime settings.

```powershell
.\infra\publish-swa.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -ResourceGroupName rg-tap-portal \
  -StaticWebAppName swa-tap-portal \
  -LogicAppName logic-tap-portal \
  -TenantId <TENANT_ID>
```

4. Set SWA auth settings in Azure (client id/secret) if not already configured.

5. Test sign-in and TAP request flow.

## Step-by-step: Advanced approach

Use this for stronger security and cleaner separation of frontend/backend responsibilities.

1. Run the automated deployment.

```powershell
.\infra\publish-secretless.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -TenantId <TENANT_ID>
```

2. Confirm API health endpoint:
  - `https://<your-webapp>.azurewebsites.net/healthz`

3. Open frontend URL and test:
  - Sign-in
  - TAP creation
  - Expiry/countdown behavior

4. Apply Conditional Access in report-only first, then enforce.

## One-command automation for teams

To keep publishing simple for other folks, use [infra/publish-all.ps1](infra/publish-all.ps1).

```powershell
.\infra\publish-all.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -TenantId <TENANT_ID> \
  -DeploySimple $true \
  -DeployAdvanced $true \
  -SimpleClientId <SWA_CLIENT_ID> \
  -SimpleClientSecret <SWA_CLIENT_SECRET>
```

The script can deploy either approach or both in one run.

## Publish plan (simple)

1. Keep `main` as the release branch.
2. Use one script entrypoint from CI: [infra/publish-all.ps1](infra/publish-all.ps1).
3. Store required values as pipeline secrets:
  - `AZURE_SUBSCRIPTION_ID`
  - `AZURE_TENANT_ID`
  - `SWA_CLIENT_ID`
  - `SWA_CLIENT_SECRET`
4. Validate with smoke tests after each deployment:
  - Frontend loads
  - Sign-in works
  - TAP request works
5. Keep repository private until go-live.
