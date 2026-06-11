param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$TenantId,

  [string]$Location = 'westeurope',

  [string]$ResourceGroupName = 'rg-tap-portal-secretless',

  [string]$StaticWebAppName = 'swa-tap-portal-secretless',

  [string]$StaticWebAppSku = 'Free',

  [string]$AppServicePlanName = 'asp-tap-portal-secretless',

  [string]$WebAppName = 'app-tap-portal-secretless',

  [string]$AppInsightsName = 'appi-tap-portal-secretless',

  [string]$FrontendAppDisplayName = 'TAP Portal Secretless Frontend',

  [string]$ApiAppDisplayName = 'TAP Portal Secretless API'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "Using subscription $SubscriptionId"
az account set --subscription $SubscriptionId | Out-Null

Write-Host 'Ensuring resource group exists'
az group create --name $ResourceGroupName --location $Location | Out-Null

Write-Host 'Deploying secretless infrastructure'
$deployment = az deployment group create `
  --name main-secretless `
  --resource-group $ResourceGroupName `
  --template-file .\infra\main-secretless.bicep `
  --parameters staticWebAppName=$StaticWebAppName staticWebAppSku=$StaticWebAppSku appServicePlanName=$AppServicePlanName webAppName=$WebAppName appInsightsName=$AppInsightsName `
  -o json | ConvertFrom-Json

$outputs = $deployment.properties.outputs
$frontendHostname = $outputs.staticWebAppHostname.value
$backendHostname = $outputs.webAppHostname.value
$webAppPrincipalId = $outputs.webAppPrincipalId.value
$frontendOrigin = "https://$frontendHostname"
$backendBaseUrl = "https://$backendHostname"

Write-Host 'Configuring Microsoft Entra applications'
$entraJson = .\infra\setup-secretless-entra.ps1 `
  -TenantId $TenantId `
  -FrontendHostname $frontendHostname `
  -FrontendAppDisplayName $FrontendAppDisplayName `
  -ApiAppDisplayName $ApiAppDisplayName

$entra = $entraJson | ConvertFrom-Json

Write-Host 'Updating backend app settings'
az webapp config appsettings set `
  --resource-group $ResourceGroupName `
  --name $WebAppName `
  --settings `
    EXPECTED_TENANT_ID=$TenantId `
    EXPECTED_TOKEN_AUDIENCES="$($entra.apiAppId),$($entra.apiAudience)" `
    REQUIRED_SCOPE=TapPortal.RequestTap `
    ALLOWED_ORIGIN=$frontendOrigin | Out-Null

Write-Host 'Granting backend managed identity Microsoft Graph permissions'
.\infra\grant-graph-permissions.ps1 -ManagedIdentityPrincipalId $webAppPrincipalId -TenantId $TenantId

Write-Host 'Generating frontend runtime configuration'
$configPath = Join-Path $repoRoot 'portal-secretless\config.js'
$configContent = @"
window.__APP_CONFIG__ = {
  tenantId: '$TenantId',
  clientId: '$($entra.frontendClientId)',
  apiScope: '$($entra.apiScope)',
  apiBaseUrl: '$backendBaseUrl'
};
"@
Set-Content -Path $configPath -Value $configContent -Encoding UTF8

Write-Host 'Installing backend dependencies'
Push-Location (Join-Path $repoRoot 'secretless-api')
npm install --omit=dev
Pop-Location

$packagePath = Join-Path $repoRoot 'secretless-api.zip'
if (Test-Path $packagePath) {
  Remove-Item $packagePath -Force
}

Write-Host 'Packaging backend application'
Compress-Archive -Path (Join-Path $repoRoot 'secretless-api\*') -DestinationPath $packagePath -Force

Write-Host 'Deploying backend application'
az webapp deploy `
  --resource-group $ResourceGroupName `
  --name $WebAppName `
  --src-path $packagePath `
  --type zip `
  --restart true | Out-Null

Write-Host 'Fetching Static Web App deployment token'
$deploymentToken = az staticwebapp secrets list `
  --name $StaticWebAppName `
  --resource-group $ResourceGroupName `
  --query properties.apiKey -o tsv

if (-not $deploymentToken) {
  throw 'Unable to resolve Static Web App deployment token.'
}

Write-Host 'Deploying secretless frontend'
npx @azure/static-web-apps-cli deploy .\portal-secretless `
  --deployment-token $deploymentToken `
  --env production

Write-Host ''
Write-Host 'Secretless TAP portal deployed.' -ForegroundColor Green
Write-Host "Frontend: $frontendOrigin" -ForegroundColor Green
Write-Host "Backend:  $backendBaseUrl" -ForegroundColor Green