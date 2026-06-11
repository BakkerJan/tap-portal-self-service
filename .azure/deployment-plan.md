# Secretless TAP Portal Deployment Plan

Status: Planning

## Goal

Build a new TAP portal in the same Azure subscription and tenant as the current app, while keeping the current app unchanged and operational. The new app must remove both runtime secret classes:

- No Static Web Apps built-in auth client secret
- No Logic App callback/SAS secret

The new app must still support Microsoft Entra Conditional Access so authentication strengths such as phishing-resistant MFA can be enforced.

## Assumptions

- Subscription: `2d3da3bf-ad81-48eb-abca-95b0ff256191`
- Tenant: `f43cfd98-c931-4d4c-95f3-9616cc2bee83`
- Region: `westeurope`
- Current app remains deployed and untouched except for shared documentation updates if needed.

## Mode

MODIFY existing workspace by adding a parallel secretless implementation.

## Proposed Architecture

### Frontend

- New static frontend hosted as a separate Azure Static Web App
- Static Web App auth disabled for app logic; frontend uses Microsoft Entra SPA auth with Authorization Code + PKCE via MSAL.js
- Frontend requests an access token for the new backend API
- Conditional Access targets the new frontend app registration / enterprise app

### Backend

- New Azure Function App on Flex Consumption plan
- System-assigned managed identity enabled
- HTTP-triggered API endpoint validates Entra access tokens
- API derives the signed-in user object ID from validated token claims
- API creates TAP directly through Microsoft Graph using managed identity

### Identity and Authorization

- New SPA app registration for frontend login
- New app registration / exposed API scope for backend access token audience
- Backend only accepts tokens from the expected tenant, issuer, and audience
- Conditional Access auth strength policy applies to the frontend sign-in app

## Planned Resource Additions

- New resource group or parallel resources in `rg-tap-portal` depending on final naming choice
- New Static Web App for secretless frontend
- New Function App (Flex Consumption)
- New Storage Account required by Function App
- New Application Insights resource
- New frontend app registration (SPA)
- New backend app registration / scope exposure if needed for token audience
- Managed identity Graph permission assignment for backend Function App

## Planned Repository Changes

- Add new frontend folder for secretless portal UI
- Add new function app folder for secretless TAP API
- Add new Bicep templates or extend infra with separate secretless deployment path
- Add deployment/readme notes for the new architecture
- Keep current app folders and deployment flow intact

## Security Design

- No client secrets in frontend or hosting settings
- No Logic App callback secrets in app settings
- Managed identity used for Graph access
- API authorization enforced with JWT validation
- User identity derived server-side from token claims, not trusted from request body
- Existing app remains available during migration/testing

## Validation Plan

- Validate Bicep deployment with `what-if`
- Validate Function App code locally where feasible
- Verify Entra sign-in and Conditional Access challenge on new frontend
- Verify API rejects unauthenticated and wrong-audience tokens
- Verify TAP creation succeeds through managed identity Graph call

## Naming Plan

Working names unless changed before implementation:

- Static Web App: `swa-tap-portal-secretless`
- Function App: `func-tap-portal-secretless`
- Application Insights: `appi-tap-portal-secretless`
- Storage Account: generated compliant name based on `tapsecretless`

## Risks / Decisions

- Static Web Apps built-in auth will not be used for the new app flow
- Conditional Access enforcement depends on targeting the correct enterprise application for the SPA sign-in
- Function App managed identity needs correct Graph app role assignment before TAP creation works

## Execution Steps

1. Scaffold new secretless frontend and backend folders
2. Implement MSAL.js SPA login flow with PKCE
3. Implement Function API token validation and Graph TAP creation via managed identity
4. Create parallel Bicep deployment for new hosting resources
5. Add app registration configuration guidance and tenant-specific settings
6. Validate locally where possible
7. Prepare for Azure validation and deployment

## Out of Scope

- Replacing or deleting the current working TAP portal
- Migrating existing users or URLs automatically
- Removing the current app's secrets from its existing design