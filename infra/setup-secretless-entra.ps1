param(
  [Parameter(Mandatory = $true)]
  [string]$TenantId,

  [Parameter(Mandatory = $true)]
  [string]$FrontendHostname,

  [Parameter(Mandatory = $false)]
  [string[]]$AdditionalFrontendRedirectUris = @(),

  [Parameter(Mandatory = $true)]
  [string]$FrontendAppDisplayName,

  [Parameter(Mandatory = $true)]
  [string]$ApiAppDisplayName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GraphPatch {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Uri,

    [Parameter(Mandatory = $true)]
    [string]$JsonBody
  )

  $tempFile = [System.IO.Path]::GetTempFileName()
  try {
    Set-Content -Path $tempFile -Value $JsonBody -Encoding UTF8 -NoNewline
    az rest --method PATCH --headers Content-Type=application/json --uri $Uri --body "@$tempFile" | Out-Null
  }
  finally {
    if (Test-Path $tempFile) {
      Remove-Item $tempFile -Force
    }
  }
}

function Get-OrCreateApp {
  param(
    [Parameter(Mandatory = $true)]
    [string]$DisplayName,

    [Parameter(Mandatory = $false)]
    [string[]]$SpaRedirectUris = @()
  )

  $existing = az ad app list --display-name $DisplayName --query '[0]' -o json | ConvertFrom-Json
  if ($existing) {
    if ($SpaRedirectUris.Count -gt 0) {
      $spaPatch = @{ spa = @{ redirectUris = $SpaRedirectUris } } | ConvertTo-Json -Depth 5 -Compress
      Invoke-GraphPatch -Uri "https://graph.microsoft.com/v1.0/applications/$($existing.id)" -JsonBody $spaPatch
      $existing = az ad app show --id $existing.appId -o json | ConvertFrom-Json
    }

    return $existing
  }

  $createAppArgs = @(
    'ad', 'app', 'create',
    '--display-name', $DisplayName,
    '--sign-in-audience', 'AzureADMyOrg'
  )

  $created = az @createAppArgs -o json | ConvertFrom-Json

  if ($SpaRedirectUris.Count -gt 0) {
    $spaPatch = @{ spa = @{ redirectUris = $SpaRedirectUris } } | ConvertTo-Json -Depth 5 -Compress
    Invoke-GraphPatch -Uri "https://graph.microsoft.com/v1.0/applications/$($created.id)" -JsonBody $spaPatch
    $created = az ad app show --id $created.appId -o json | ConvertFrom-Json
  }

  return $created
}

Write-Host 'Ensuring frontend SPA app registration exists'
$frontendRedirectUri = "https://$FrontendHostname"
$frontendRedirectUris = @($frontendRedirectUri) + @($AdditionalFrontendRedirectUris | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$frontendRedirectUris = @($frontendRedirectUris | Select-Object -Unique)
$frontendApp = Get-OrCreateApp -DisplayName $FrontendAppDisplayName -SpaRedirectUris $frontendRedirectUris
az ad sp create --id $frontendApp.appId 2>$null | Out-Null

Write-Host 'Ensuring backend API app registration exists'
$apiApp = Get-OrCreateApp -DisplayName $ApiAppDisplayName
az ad sp create --id $apiApp.appId 2>$null | Out-Null

$apiObjectId = $apiApp.id
$scopeValue = 'TapPortal.RequestTap'
$existingScopeId = az rest --method GET --uri "https://graph.microsoft.com/v1.0/applications/${apiObjectId}?`$select=api" --query "api.oauth2PermissionScopes[?value=='$scopeValue'].id | [0]" -o tsv
if (-not $existingScopeId) {
  $existingScopeId = [guid]::NewGuid().Guid
}

$apiPatch = @{
  identifierUris = @("api://$($apiApp.appId)")
  api = @{
    requestedAccessTokenVersion = 2
    oauth2PermissionScopes = @(
      @{
        id = $existingScopeId
        adminConsentDisplayName = 'Request TAP for the signed-in user'
        adminConsentDescription = 'Allow the TAP portal frontend to request a Temporary Access Pass for the signed-in user.'
        isEnabled = $true
        type = 'User'
        userConsentDisplayName = 'Create TAP for me'
        userConsentDescription = 'Allow this application to request a Temporary Access Pass for you.'
        value = $scopeValue
      }
    )
  }
} | ConvertTo-Json -Depth 8 -Compress

Write-Host 'Configuring backend API scope'
Invoke-GraphPatch -Uri "https://graph.microsoft.com/v1.0/applications/${apiObjectId}" -JsonBody $apiPatch

Write-Host 'Granting frontend permission to backend scope'
az ad app permission add --id $frontendApp.appId --api $apiApp.appId --api-permissions "$existingScopeId=Scope" 2>$null | Out-Null
az ad app permission admin-consent --id $frontendApp.appId 2>$null | Out-Null

$result = [ordered]@{
  tenantId = $TenantId
  frontendClientId = $frontendApp.appId
  frontendObjectId = $frontendApp.id
  apiAppId = $apiApp.appId
  apiObjectId = $apiApp.id
  apiAudience = "api://$($apiApp.appId)"
  apiScope = "api://$($apiApp.appId)/$scopeValue"
}

$result | ConvertTo-Json -Depth 4