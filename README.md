# TAP Portal

Recommended model: one automated Bicep-first deployment path.

You run one script, and it handles:

1. Azure infrastructure deployment (Bicep)
2. Entra app registration setup
3. API scope and consent setup
4. Backend and frontend publishing
5. Optional Conditional Access policy automation

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

## One command deployment

Run this from the repository root:

```powershell
.\infra\deploy.ps1 \
   -SubscriptionId <SUBSCRIPTION_ID> \
   -TenantId <TENANT_ID>
```

Optional: include Conditional Access setup in the same run:

```powershell
.\infra\deploy.ps1 \
   -SubscriptionId <SUBSCRIPTION_ID> \
   -TenantId <TENANT_ID> \
   -ApplyConditionalAccess \
   -ConditionalAccessState reportOnly
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

## What this script creates and configures

1. Resource group and infra components
2. Static Web App frontend hosting
3. App Service backend API with managed identity
4. Entra frontend and API app registrations
5. API scope `TapPortal.RequestTap` and frontend permission
6. Graph permission assignment for backend managed identity
7. Frontend runtime config (`portal-secretless/config.js`)
8. Frontend and backend code deployment

## App ID and secret handling

In the recommended model, app registrations are configured by script.

1. You do not manually create a Graph app secret for backend Graph calls.
2. Backend uses managed identity for Graph authentication.
3. Frontend uses client ID only, written into generated runtime config.
4. Keep generated IDs in deployment outputs and not in hardcoded source.

## Start testing (where to begin)

After deployment completes, start in this order:

1. Open the frontend URL shown in deployment output.
2. Sign in with a test user.
3. Click Generate TAP.
4. Confirm TAP appears with countdown.
5. Verify backend health endpoint:

```powershell
Invoke-WebRequest -Uri "https://<your-webapp>.azurewebsites.net/healthz" -UseBasicParsing
```

6. Verify Entra audit logs for TAP creation event.

## Optional reference guides

If needed, older split guides are still available:

1. [README-simple.md](README-simple.md)
2. [README-advanced.md](README-advanced.md)

## Troubleshooting quick map

1. Sign-in loops:
   Re-run `infra/deploy.ps1` and verify generated frontend app registration and redirect URI.
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

2. Verify app registrations were created by script
   Portal path:
   `Entra admin center -> Applications -> App registrations`
   Required checks:
   - Frontend app exists
   - API app exists
   - Frontend redirect URI points to deployed SWA host
   Screenshot placeholders:
   `[Screenshot: Frontend app registration overview]`
   `[Screenshot: API app registration overview]`

3. Verify backend managed identity permissions
   Portal path:
   `Azure portal -> App Services -> <webapp-name> -> Identity`
   Required checks:
   - System-assigned managed identity is enabled
   - Graph permission grant script has been applied
   Screenshot placeholder:
   `[Screenshot: Web App identity enabled]`

4. Run deployment script
   Local path:
   `Repository root -> infra`
   Command:
   - `.\infra\deploy.ps1 ...`
   Screenshot placeholder:
   `[Screenshot: Terminal showing successful deployment summary]`

5. Apply Conditional Access policy in report-only
   Portal path:
   `Entra admin center -> Protection -> Conditional Access -> Policies`
   Required action:
   - Create/update TAP policy in report-only first.
   - Validate sign-in logs before enforcing.
   Screenshot placeholders:
   `[Screenshot: CA policy assignment (apps/users)]`
   `[Screenshot: Grant control set to Phishing-resistant MFA]`
   `[Screenshot: Policy state report-only]`

6. Test end-to-end
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

7. Go-live checklist
   - Keep repository private until approval.
   - Confirm break-glass exclusion group in CA policy.
   - Move CA policy from report-only to enabled.
   - Re-run smoke test after enforcement.
   Screenshot placeholder:
   `[Screenshot: Final CA policy enabled state]`
