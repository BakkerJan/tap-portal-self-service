@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Name of the Azure Static Web App used to host the secretless frontend')
param staticWebAppName string = 'swa-tap-portal-secretless'

@description('Static Web App SKU')
@allowed([
  'Free'
  'Standard'
])
param staticWebAppSku string = 'Free'

@description('Name of the backend App Service plan')
param appServicePlanName string = 'asp-tap-portal-secretless'

@description('Name of the backend web app')
param webAppName string = 'app-tap-portal-secretless'

@description('Name of the Application Insights resource')
param appInsightsName string = 'appi-tap-portal-secretless'

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

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: 'B1'
    tier: 'Basic'
    capacity: 1
  }
  properties: {
    reserved: true
  }
}

resource webApp 'Microsoft.Web/sites@2023-12-01' = {
  name: webAppName
  location: location
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      cors: {
        allowedOrigins: [
          'https://${staticWebApp.properties.defaultHostname}'
        ]
        supportCredentials: false
      }
      appSettings: [
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
        {
          name: 'NODE_ENV'
          value: 'production'
        }
        {
          name: 'EXPECTED_TENANT_ID'
          value: ''
        }
        {
          name: 'EXPECTED_TOKEN_AUDIENCES'
          value: ''
        }
        {
          name: 'REQUIRED_SCOPE'
          value: 'TapPortal.RequestTap'
        }
        {
          name: 'ALLOWED_ORIGIN'
          value: 'https://${staticWebApp.properties.defaultHostname}'
        }
        {
          name: 'TAP_LIFETIME_MINUTES'
          value: '60'
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
      ]
    }
    httpsOnly: true
  }
}

@description('Secretless frontend hostname')
output staticWebAppHostname string = staticWebApp.properties.defaultHostname

@description('Secretless backend hostname')
output webAppHostname string = webApp.properties.defaultHostName

@description('Backend managed identity principal ID')
output webAppPrincipalId string = webApp.identity.principalId