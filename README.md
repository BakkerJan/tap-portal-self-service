# TAP Portal

This repository includes two deployment approaches:

1. Simple: Static Web Apps + built-in API + Logic App
2. Advanced: Static Web Apps frontend + App Service API + Managed Identity

## Choose your option

If you are unsure, start with Simple.

1. Simple option
   Best for quick setup and fewer components.
   Full guide: [README-simple.md](README-simple.md)

2. Advanced option
   Best for stronger backend security and managed identity-based Graph access.
   Full guide: [README-advanced.md](README-advanced.md)

## Start here first

1. Decide if you are doing a local/manual deployment or CI deployment.
2. If local/manual, yes, you need the files on your machine:
   Download ZIP from GitHub or clone the repo.
3. Open PowerShell in the repository root.
4. Sign in to Azure CLI and verify the correct subscription.

```powershell
az login
az account show --output table
```

## Requirements checklist

1. Azure subscription with permission to create resources.
2. Entra tenant with permission to create app registrations and grant consent.
3. Temporary Access Pass enabled in Entra Authentication Methods.
4. PowerShell 7+.
5. Azure CLI (`az`).
6. Node.js and npm.

Validation commands:

```powershell
az --version
node --version
npm --version
```

## What to do with App ID and Secret

Simple approach:

1. You create an Entra app registration for SWA authentication.
2. You get two values:
   App ID (client ID) and Client Secret.
3. You store those in SWA app settings as:
   `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET`.
4. Do not put the secret in source code.

Advanced approach:

1. App registrations are created/updated by script.
2. Frontend uses client ID only (in generated runtime config).
3. Backend authenticates to Graph with Managed Identity (no client secret for Graph).

## App registration settings you must enable

Simple approach (manual app registration):

1. Sign-in audience: Accounts in this organizational directory only.
2. Platform: Web.
3. Redirect URI:
   `https://<your-simple-swa-hostname>/.auth/login/aad/callback`
4. Create a client secret and copy it once.
5. Keep App ID and Secret secure. Add to SWA app settings.

Advanced approach (script-managed):

1. Frontend app audience: single tenant.
2. Frontend SPA redirect URI:
   `https://<your-advanced-swa-hostname>`
3. API app exposes scope `TapPortal.RequestTap`.
4. Frontend gets permission to that API scope.

## Step-by-step deployment: Simple

1. Create resource group and deploy infrastructure.

```powershell
az group create --name rg-tap-portal --location westeurope
az deployment group create \
  --name main \
  --resource-group rg-tap-portal \
  --template-file .\infra\main.bicep \
  --parameters staticWebAppName=swa-tap-portal logicAppName=logic-tap-portal staticWebAppSku=Standard
```

2. Create app registration in Entra with settings listed above.
3. Save the App ID and Secret.
4. Set SWA app settings:

```powershell
az staticwebapp appsettings set \
  --name swa-tap-portal \
  --resource-group rg-tap-portal \
  --setting-names AZURE_CLIENT_ID=<APP_ID> AZURE_CLIENT_SECRET=<APP_SECRET>
```

5. Publish app and sync backend settings:

```powershell
.\infra\publish-swa.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -ResourceGroupName rg-tap-portal \
  -StaticWebAppName swa-tap-portal \
  -LogicAppName logic-tap-portal \
  -TenantId <TENANT_ID>
```

## Step-by-step deployment: Advanced

1. Run full automated deployment:

```powershell
.\infra\publish-secretless.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -TenantId <TENANT_ID>
```

2. Script actions include:
   Entra app setup, API scope setup, managed identity Graph permission, backend deploy, frontend deploy.

3. Validate API health:

```powershell
Invoke-WebRequest -Uri "https://<your-advanced-webapp>.azurewebsites.net/healthz" -UseBasicParsing
```

## One-command deploy for teams

Use one script to deploy either approach or both:

```powershell
.\infra\publish-all.ps1 \
  -SubscriptionId <SUBSCRIPTION_ID> \
  -TenantId <TENANT_ID> \
  -DeploySimple $true \
  -DeployAdvanced $true \
  -SimpleClientId <SIMPLE_APP_ID> \
  -SimpleClientSecret <SIMPLE_APP_SECRET>
```

## How to test the app (where to start)

Start in this order:

1. Open frontend URL.
2. Sign in with a test user who is allowed to request TAP.
3. Click Generate TAP.
4. Confirm TAP is shown and countdown starts.
5. Use the TAP in Security Info flow.
6. Verify audit entries in Entra logs.

Expected quick checks:

1. Frontend opens without blank page.
2. Sign-in completes successfully.
3. API returns TAP or a clear policy error.
4. `healthz` returns 200 for advanced approach.

## Troubleshooting quick map

1. Sign-in loops:
   Check redirect URI and `AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET`.
2. 401 from API:
   Check tenant, audience, and scope configuration.
3. TAP not generated:
   Check TAP method enablement and Graph permissions.
4. Frontend works but API fails:
   Check backend app settings and deployment logs.

## Operator runbook (add screenshots here)

Use this section for non-technical operators. Follow each portal click path and add screenshots in your internal copy.

1. Enable TAP in Entra
   Portal path:
   `Entra admin center -> Protection -> Authentication methods -> Policies -> Temporary Access Pass`
   Screenshot placeholder:
   `[Screenshot: TAP policy enabled and targeted users]`

2. Create app registration (Simple approach only)
   Portal path:
   `Entra admin center -> Applications -> App registrations -> New registration`
   Required values:
   - Name: any friendly name (for example, TAP Portal Simple)
   - Supported account types: Single tenant
   - Redirect URI type: Web
   - Redirect URI value: `https://<simple-swa-host>/.auth/login/aad/callback`
   Screenshot placeholders:
   `[Screenshot: New registration form filled]`
   `[Screenshot: App overview showing Application (client) ID]`

3. Create client secret (Simple approach only)
   Portal path:
   `Entra admin center -> Applications -> App registrations -> <your app> -> Certificates & secrets -> New client secret`
   Required action:
   - Copy the secret value immediately and store it in your secure vault.
   Screenshot placeholders:
   `[Screenshot: Client secret created]`
   `[Screenshot: Secret copied to secure vault]`

4. Configure SWA app settings (Simple approach only)
   Portal path:
   `Azure portal -> Static Web Apps -> <simple-swa-name> -> Environment variables`
   Required settings:
   - `AZURE_CLIENT_ID = <simple app id>`
   - `AZURE_CLIENT_SECRET = <simple app secret>`
   Screenshot placeholder:
   `[Screenshot: SWA environment variables with AZURE_CLIENT_ID and AZURE_CLIENT_SECRET]`

5. Run deployment script
   Local path:
   `Repository root -> infra`
   Commands:
   - Simple: `.\infra\publish-swa.ps1 ...`
   - Advanced: `.\infra\publish-secretless.ps1 ...`
   - Both: `.\infra\publish-all.ps1 ...`
   Screenshot placeholder:
   `[Screenshot: Terminal showing successful deployment summary]`

6. Apply Conditional Access policy in report-only
   Portal path:
   `Entra admin center -> Protection -> Conditional Access -> Policies`
   Required action:
   - Create/update TAP policy in report-only first.
   - Validate sign-in logs before enforcing.
   Screenshot placeholders:
   `[Screenshot: CA policy assignment (apps/users)]`
   `[Screenshot: Grant control set to Phishing-resistant MFA]`
   `[Screenshot: Policy state report-only]`

7. Test end-to-end
   Start here:
   - Open frontend URL.
   - Sign in as test user.
   - Generate TAP.
   - Confirm countdown and one-time display.
   - Validate Entra audit log event.
   Portal path for logs:
   `Entra admin center -> Monitoring & health -> Audit logs`
   Screenshot placeholders:
   `[Screenshot: Successful portal sign-in]`
   `[Screenshot: TAP generated in UI]`
   `[Screenshot: Entra audit log entry for TAP method creation]`

8. Go-live checklist
   - Keep repository private until approval.
   - Confirm break-glass exclusion group in CA policy.
   - Move CA policy from report-only to enabled.
   - Re-run smoke test after enforcement.
   Screenshot placeholder:
   `[Screenshot: Final CA policy enabled state]`
