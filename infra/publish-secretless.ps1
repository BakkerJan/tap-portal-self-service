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

  [string]$ApiAppDisplayName = 'TAP Portal Secretless API',

  [string]$FrontendCustomDomain = '',

  [string]$ApiBaseUrl = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Normalize-Origin {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $candidate = $Value.Trim()
  if (-not $candidate) {
    return ''
  }

  if (-not ($candidate -match '^https?://')) {
    $candidate = "https://$candidate"
  }

  $uri = [Uri]$candidate
  return $uri.GetLeftPart([System.UriPartial]::Authority)
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host "Using subscription $SubscriptionId"
az account set --subscription $SubscriptionId | Out-Null

Write-Host 'Registering required resource providers'
az provider register --namespace microsoft.operationalinsights --wait | Out-Null
az provider register --namespace microsoft.web --wait | Out-Null
az provider register --namespace microsoft.resources --wait | Out-Null

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
$backendBaseUrl = if ($ApiBaseUrl) { Normalize-Origin -Value $ApiBaseUrl } else { "https://$backendHostname" }
$frontendOrigins = @($frontendOrigin)
if ($FrontendCustomDomain) {
  $frontendCustomOrigin = Normalize-Origin -Value $FrontendCustomDomain
  if ($frontendOrigins -notcontains $frontendCustomOrigin) {
    $frontendOrigins += $frontendCustomOrigin
  }
}
$allowedOriginSetting = ($frontendOrigins -join ',')

Write-Host 'Configuring Microsoft Entra applications'
$entraJson = .\infra\setup-secretless-entra.ps1 `
  -TenantId $TenantId `
  -FrontendHostname $frontendHostname `
  -AdditionalFrontendRedirectUris $frontendOrigins `
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
    EXPECTED_CLIENT_APP_IDS=$($entra.frontendClientId) `
    REQUIRED_SCOPE=TapPortal.RequestTap `
    ALLOWED_ORIGIN=$allowedOriginSetting | Out-Null

Write-Host 'Disabling App Service platform CORS (API handles CORS headers)'
$existingCorsOrigins = az webapp cors show `
  --resource-group $ResourceGroupName `
  --name $WebAppName `
  --query allowedOrigins -o tsv

if ($existingCorsOrigins) {
  $corsOrigins = @($existingCorsOrigins -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($corsOrigins.Count -gt 0) {
    az webapp cors remove `
      --resource-group $ResourceGroupName `
      --name $WebAppName `
      --allowed-origins @corsOrigins | Out-Null
  }
}

Write-Host 'Granting backend managed identity Microsoft Graph permissions'
.\infra\grant-graph-permissions.ps1 -ManagedIdentityPrincipalId $webAppPrincipalId -TenantId $TenantId

Write-Host 'Preparing frontend deployment package'
$frontendSourcePath = Join-Path $repoRoot 'portal-secretless'
$frontendDeployPath = Join-Path $repoRoot 'portal-secretless.deploy'

if (Test-Path $frontendDeployPath) {
  Remove-Item -Path $frontendDeployPath -Recurse -Force
}

Copy-Item -Path $frontendSourcePath -Destination $frontendDeployPath -Recurse

Write-Host 'Generating frontend runtime configuration'
$configPath = Join-Path $frontendDeployPath 'config.js'
$configContent = @"
window.__APP_CONFIG__ = {
  tenantId: '$TenantId',
  clientId: '$($entra.frontendClientId)',
  apiScope: '$($entra.apiScope)',
  apiBaseUrl: '$backendBaseUrl'
};
"@
Set-Content -Path $configPath -Value $configContent -Encoding UTF8

$swaConfigPath = Join-Path $frontendDeployPath 'staticwebapp.config.json'
$swaConfigContent = Get-Content -Path $swaConfigPath -Raw
$swaConfigContent = $swaConfigContent.Replace('__BACKEND_BASE_URL__', $backendBaseUrl)
Set-Content -Path $swaConfigPath -Value $swaConfigContent -Encoding UTF8

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
npx @azure/static-web-apps-cli deploy $frontendDeployPath `
  --deployment-token $deploymentToken `
  --env production

if (Test-Path $frontendDeployPath) {
  Remove-Item -Path $frontendDeployPath -Recurse -Force
}

Write-Host ''
Write-Host 'Secretless TAP portal deployed.' -ForegroundColor Green
Write-Host "Frontend: $frontendOrigin" -ForegroundColor Green
Write-Host "Backend:  $backendBaseUrl" -ForegroundColor Green