// TAP Portal – Infrastructure
// Deploys: Azure Static Web Apps + Logic App (Consumption) with System-Assigned Managed Identity
//
// Usage:
//   az group create -n rg-tap-portal -l westeurope
//   az deployment group create -g rg-tap-portal -f main.bicep \
//     -p staticWebAppName=swa-tap-portal logicAppName=logic-tap-portal

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the Azure Static Web Apps resource')
param staticWebAppName string = 'swa-tap-portal'

@description('Static Web App SKU. Use Standard for paid plan.')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Standard'

@description('Name of the Logic App resource')
param logicAppName string = 'logic-tap-portal'

// ── Azure Static Web Apps ────────────────────────────────────────────────────
resource staticWebApp 'Microsoft.Web/staticSites@2023-01-01' = {
  name: staticWebAppName
  location: location
  sku: {
    name: staticWebAppSku
    tier: staticWebAppSku
  }
  properties: {
    stagingEnvironmentPolicy: 'Disabled'
    allowConfigFileUpdates: true
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

// ── Logic App (Consumption) ───────────────────────────────────────────────────
resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: loadJsonContent('logic-app-definition.json').definition
    parameters: {}
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
@description('Managed Identity principal ID – use this to grant Graph API permissions via grant-graph-permissions.ps1')
output managedIdentityPrincipalId string = logicApp.identity.principalId

@description('Static Web Apps default hostname')
output staticWebAppHostname string = staticWebApp.properties.defaultHostname

@description('Logic App resource ID')
output logicAppResourceId string = logicApp.id

// NOTE: The Logic App trigger URL (containing the SAS key) cannot be output from
// Bicep directly because it is generated at runtime. Retrieve it with:
//   az logic workflow trigger list-callback-url \
//     -g <resource-group> -n <logicAppName> --trigger-name manual
