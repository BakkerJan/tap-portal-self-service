param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$TenantId,

  [Alias('DeployLegacy')]
  [bool]$DeploySimple = $true,

  [Alias('DeploySecretless')]
  [bool]$DeployAdvanced = $true,

  [string]$Location = 'westeurope',

  [Alias('LegacyResourceGroupName')]
  [string]$SimpleResourceGroupName = 'rg-tap-portal',
  [Alias('LegacyStaticWebAppName')]
  [string]$SimpleStaticWebAppName = 'swa-tap-portal',
  [Alias('LegacyLogicAppName')]
  [string]$SimpleLogicAppName = 'logic-tap-portal',
  [Alias('LegacyStaticWebAppSku')]
  [string]$SimpleStaticWebAppSku = 'Standard',
  [Alias('LegacyClientId')]
  [string]$SimpleClientId,
  [Alias('LegacyClientSecret')]
  [string]$SimpleClientSecret,

  [Alias('SecretlessResourceGroupName')]
  [string]$AdvancedResourceGroupName = 'rg-tap-portal-secretless',
  [Alias('SecretlessStaticWebAppName')]
  [string]$AdvancedStaticWebAppName = 'swa-tap-portal-secretless',
  [Alias('SecretlessStaticWebAppSku')]
  [string]$AdvancedStaticWebAppSku = 'Free',
  [Alias('SecretlessAppServicePlanName')]
  [string]$AdvancedAppServicePlanName = 'asp-tap-portal-secretless',
  [Alias('SecretlessWebAppName')]
  [string]$AdvancedWebAppName = 'app-tap-portal-secretless',
  [Alias('SecretlessAppInsightsName')]
  [string]$AdvancedAppInsightsName = 'appi-tap-portal-secretless',
  [Alias('SecretlessFrontendAppDisplayName')]
  [string]$AdvancedFrontendAppDisplayName = 'TAP Portal Advanced Frontend',
  [Alias('SecretlessApiAppDisplayName')]
  [string]$AdvancedApiAppDisplayName = 'TAP Portal Advanced API'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "Using subscription $SubscriptionId"
az account set --subscription $SubscriptionId | Out-Null

if (-not $DeploySimple -and -not $DeployAdvanced) {
  throw 'Nothing to deploy. Set -DeploySimple and/or -DeployAdvanced to $true.'
}

if ($DeploySimple) {
  Write-Host ''
  Write-Host '=== Deploying SIMPLE approach ===' -ForegroundColor Cyan

  az group create --name $SimpleResourceGroupName --location $Location | Out-Null

  az deployment group create `
    --name main `
    --resource-group $SimpleResourceGroupName `
    --template-file .\infra\main.bicep `
    --parameters staticWebAppName=$SimpleStaticWebAppName logicAppName=$SimpleLogicAppName staticWebAppSku=$SimpleStaticWebAppSku `
    --output none

  if (-not $SimpleClientId -or -not $SimpleClientSecret) {
    throw 'Simple approach requires -SimpleClientId and -SimpleClientSecret for SWA EasyAuth.'
  }

  az staticwebapp appsettings set `
    --name $SimpleStaticWebAppName `
    --resource-group $SimpleResourceGroupName `
    --setting-names AZURE_CLIENT_ID=$SimpleClientId AZURE_CLIENT_SECRET=$SimpleClientSecret `
    --output none

  .\infra\publish-swa.ps1 `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $SimpleResourceGroupName `
    -StaticWebAppName $SimpleStaticWebAppName `
    -LogicAppName $SimpleLogicAppName `
    -TenantId $TenantId
}

if ($DeployAdvanced) {
  Write-Host ''
  Write-Host '=== Deploying ADVANCED approach ===' -ForegroundColor Cyan

  .\infra\publish-secretless.ps1 `
    -SubscriptionId $SubscriptionId `
    -TenantId $TenantId `
    -Location $Location `
    -ResourceGroupName $AdvancedResourceGroupName `
    -StaticWebAppName $AdvancedStaticWebAppName `
    -StaticWebAppSku $AdvancedStaticWebAppSku `
    -AppServicePlanName $AdvancedAppServicePlanName `
    -WebAppName $AdvancedWebAppName `
    -AppInsightsName $AdvancedAppInsightsName `
    -FrontendAppDisplayName $AdvancedFrontendAppDisplayName `
    -ApiAppDisplayName $AdvancedApiAppDisplayName
}

Write-Host ''
Write-Host 'All requested deployments completed successfully.' -ForegroundColor Green
