param(
  [Parameter(Mandatory = $true)]
  [string]$SubscriptionId,

  [Parameter(Mandatory = $true)]
  [string]$ResourceGroupName,

  [Parameter(Mandatory = $true)]
  [string]$StaticWebAppName,

  [Parameter(Mandatory = $true)]
  [string]$LogicAppName,

  [Parameter(Mandatory = $true)]
  [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "Using subscription $SubscriptionId"
az account set --subscription $SubscriptionId | Out-Null

Write-Host 'Fetching Logic App callback URL'
$callbackUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/$LogicAppName/triggers/manual/listCallbackUrl?api-version=2019-05-01"
$callbackDetails = az rest `
  --method post `
  --uri $callbackUri `
  -o json | ConvertFrom-Json

if (-not $callbackDetails.value) {
  throw 'Unable to resolve Logic App callback URL.'
}

Write-Host 'Updating Static Web App application settings'
$appSettingArgs = @(
  'staticwebapp', 'appsettings', 'set',
  '--name', $StaticWebAppName,
  '--resource-group', $ResourceGroupName,
  '--setting-names',
  "LOGIC_APP_BASE_URL=$($callbackDetails.basePath)",
  "LOGIC_APP_API_VERSION=$($callbackDetails.queries.'api-version')",
  "LOGIC_APP_SP=$($callbackDetails.queries.sp)",
  "LOGIC_APP_SV=$($callbackDetails.queries.sv)",
  "LOGIC_APP_SIG=$($callbackDetails.queries.sig)",
  "EXPECTED_TENANT_ID=$TenantId"
)

az @appSettingArgs | Out-Null

Write-Host 'Fetching Static Web App deployment token'
$deploymentToken = az staticwebapp secrets list `
  --name $StaticWebAppName `
  --resource-group $ResourceGroupName `
  --query properties.apiKey -o tsv

if (-not $deploymentToken) {
  throw 'Unable to resolve Static Web App deployment token.'
}

Write-Host 'Deploying portal and API'
npx @azure/static-web-apps-cli deploy ./portal `
  --api-location ./api `
  --api-language node `
  --api-version 18 `
  --deployment-token $deploymentToken `
  --env production
