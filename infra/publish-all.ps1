param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$TenantId,

  [bool]$DeployLegacy = $true,

  [bool]$DeploySecretless = $true,

  [string]$Location = 'westeurope',

  [string]$LegacyResourceGroupName = 'rg-tap-portal',
  [string]$LegacyStaticWebAppName = 'swa-tap-portal',
  [string]$LegacyLogicAppName = 'logic-tap-portal',
  [string]$LegacyStaticWebAppSku = 'Standard',
  [string]$LegacyClientId,
  [string]$LegacyClientSecret,

  [string]$SecretlessResourceGroupName = 'rg-tap-portal-secretless',
  [string]$SecretlessStaticWebAppName = 'swa-tap-portal-secretless',
  [string]$SecretlessStaticWebAppSku = 'Free',
  [string]$SecretlessAppServicePlanName = 'asp-tap-portal-secretless',
  [string]$SecretlessWebAppName = 'app-tap-portal-secretless',
  [string]$SecretlessAppInsightsName = 'appi-tap-portal-secretless',
  [string]$SecretlessFrontendAppDisplayName = 'TAP Portal Secretless Frontend',
  [string]$SecretlessApiAppDisplayName = 'TAP Portal Secretless API'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "Using subscription $SubscriptionId"
az account set --subscription $SubscriptionId | Out-Null

if (-not $DeployLegacy -and -not $DeploySecretless) {
  throw 'Nothing to deploy. Set -DeployLegacy and/or -DeploySecretless to $true.'
}

if ($DeployLegacy) {
  Write-Host ''
  Write-Host '=== Deploying LEGACY solution ===' -ForegroundColor Cyan

  az group create --name $LegacyResourceGroupName --location $Location | Out-Null

  az deployment group create `
    --name main `
    --resource-group $LegacyResourceGroupName `
    --template-file .\infra\main.bicep `
    --parameters staticWebAppName=$LegacyStaticWebAppName logicAppName=$LegacyLogicAppName staticWebAppSku=$LegacyStaticWebAppSku `
    --output none

  if (-not $LegacyClientId -or -not $LegacyClientSecret) {
    throw 'Legacy deployment requires -LegacyClientId and -LegacyClientSecret for SWA EasyAuth.'
  }

  az staticwebapp appsettings set `
    --name $LegacyStaticWebAppName `
    --resource-group $LegacyResourceGroupName `
    --setting-names AZURE_CLIENT_ID=$LegacyClientId AZURE_CLIENT_SECRET=$LegacyClientSecret `
    --output none

  .\infra\publish-swa.ps1 `
    -SubscriptionId $SubscriptionId `
    -ResourceGroupName $LegacyResourceGroupName `
    -StaticWebAppName $LegacyStaticWebAppName `
    -LogicAppName $LegacyLogicAppName `
    -TenantId $TenantId
}

if ($DeploySecretless) {
  Write-Host ''
  Write-Host '=== Deploying SECRETLESS solution ===' -ForegroundColor Cyan

  .\infra\publish-secretless.ps1 `
    -SubscriptionId $SubscriptionId `
    -TenantId $TenantId `
    -Location $Location `
    -ResourceGroupName $SecretlessResourceGroupName `
    -StaticWebAppName $SecretlessStaticWebAppName `
    -StaticWebAppSku $SecretlessStaticWebAppSku `
    -AppServicePlanName $SecretlessAppServicePlanName `
    -WebAppName $SecretlessWebAppName `
    -AppInsightsName $SecretlessAppInsightsName `
    -FrontendAppDisplayName $SecretlessFrontendAppDisplayName `
    -ApiAppDisplayName $SecretlessApiAppDisplayName
}

Write-Host ''
Write-Host 'All requested deployments completed successfully.' -ForegroundColor Green
