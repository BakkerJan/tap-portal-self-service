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
  [string]$FrontendAppDisplayName = 'TAP Portal Frontend',
  [string]$ApiAppDisplayName = 'TAP Portal API',

  [switch]$ApplyConditionalAccess,
  [ValidateSet('reportOnly', 'enabled')]
  [string]$ConditionalAccessState = 'reportOnly',
  [string]$ConditionalAccessPolicyName = 'TAP Portal - Require Phishing-Resistant MFA',
  [string]$ExcludeGroupId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

Write-Host 'Starting TAP Portal deployment (recommended path)...' -ForegroundColor Cyan

.\infra\publish-secretless.ps1 `
  -SubscriptionId $SubscriptionId `
  -TenantId $TenantId `
  -Location $Location `
  -ResourceGroupName $ResourceGroupName `
  -StaticWebAppName $StaticWebAppName `
  -StaticWebAppSku $StaticWebAppSku `
  -AppServicePlanName $AppServicePlanName `
  -WebAppName $WebAppName `
  -AppInsightsName $AppInsightsName `
  -FrontendAppDisplayName $FrontendAppDisplayName `
  -ApiAppDisplayName $ApiAppDisplayName

if ($ApplyConditionalAccess) {
  Write-Host ''
  Write-Host 'Applying Conditional Access policy...' -ForegroundColor Cyan

  $configPath = Join-Path $repoRoot 'portal-secretless\config.js'
  if (-not (Test-Path $configPath)) {
    throw 'Could not find portal-secretless/config.js to read frontend client ID.'
  }

  $configText = Get-Content -Path $configPath -Raw
  $clientIdMatch = [regex]::Match($configText, "clientId:\s*'([^']+)'")
  if (-not $clientIdMatch.Success) {
    throw 'Could not extract frontend clientId from portal-secretless/config.js.'
  }

  $frontendClientId = $clientIdMatch.Groups[1].Value
  $policyState = if ($ConditionalAccessState -eq 'enabled') { 'enabled' } else { 'enabledForReportingButNotEnforced' }

  $existingPolicy = az rest `
    --method get `
    --url "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies?`$select=id,displayName,conditions,state" `
    --query "value[?displayName=='$ConditionalAccessPolicyName'] | [0]" `
    -o json | ConvertFrom-Json

  if ($existingPolicy -and $existingPolicy.id) {
    $apps = @($existingPolicy.conditions.applications.includeApplications)
    if ($apps -notcontains $frontendClientId) {
      $apps += $frontendClientId
    }

    $patchPayload = @{
      state = $policyState
      conditions = @{
        applications = @{
          includeApplications = $apps
          excludeApplications = @()
        }
      }
    } | ConvertTo-Json -Depth 8

    $tmpPatchFile = [System.IO.Path]::GetTempFileName()
    try {
      Set-Content -Path $tmpPatchFile -Value $patchPayload -Encoding UTF8 -NoNewline
      az rest --method patch --url "https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies/$($existingPolicy.id)" --headers Content-Type=application/json --body "@$tmpPatchFile" | Out-Null
    }
    finally {
      if (Test-Path $tmpPatchFile) {
        Remove-Item $tmpPatchFile -Force
      }
    }

    Write-Host "Updated existing Conditional Access policy: $ConditionalAccessPolicyName" -ForegroundColor Green
  }
  else {
    $policy = @{
      displayName = $ConditionalAccessPolicyName
      state = $policyState
      conditions = @{
        applications = @{
          includeApplications = @($frontendClientId)
          excludeApplications = @()
        }
        users = @{
          includeUsers = @('All')
          excludeGroups = @()
        }
        clientAppTypes = @('browser', 'mobileAppsAndDesktopClients')
        platforms = @{ includePlatforms = @('all') }
        locations = @{ includeLocations = @('All') }
      }
      grantControls = @{
        operator = 'OR'
        authenticationStrength = @{
          id = '00000000-0000-0000-0000-000000000004'
        }
      }
      sessionControls = @{
        signInFrequency = @{
          value = 4
          type = 'hours'
          isEnabled = $true
          authenticationType = 'primaryAndSecondaryAuthentication'
          frequencyInterval = 'timeBased'
        }
      }
    }

    if ($ExcludeGroupId) {
      $policy.conditions.users.excludeGroups = @($ExcludeGroupId)
    }

    $createPayload = $policy | ConvertTo-Json -Depth 20
    $tmpCreateFile = [System.IO.Path]::GetTempFileName()
    try {
      Set-Content -Path $tmpCreateFile -Value $createPayload -Encoding UTF8 -NoNewline
      az rest --method post --url 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies' --headers Content-Type=application/json --body "@$tmpCreateFile" | Out-Null
    }
    finally {
      if (Test-Path $tmpCreateFile) {
        Remove-Item $tmpCreateFile -Force
      }
    }

    Write-Host "Created new Conditional Access policy: $ConditionalAccessPolicyName" -ForegroundColor Green
  }
}

Write-Host ''
Write-Host 'Deployment complete.' -ForegroundColor Green
Write-Host 'Next: run the test steps in README.md (Start testing section).' -ForegroundColor Green
