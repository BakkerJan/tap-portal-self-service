#Requires -Modules Microsoft.Graph.Applications

<#
.SYNOPSIS
  Grants the App Service Managed Identity the Graph API permission required
  to create Temporary Access Passes on behalf of any user.

.DESCRIPTION
  Assigns the Application permission "UserAuthMethod-TAP.ReadWrite.All"
  to the managed identity. This is the least-privileged permission that
  allows creating Temporary Access Passes without granting access to any
  other authentication method (passwords, FIDO2, phone, etc.).

  Run this ONCE after deploying main.bicep.

.PARAMETER ManagedIdentityPrincipalId
  The Object ID of the App Service's Managed Identity.
  Shown as 'webAppPrincipalId' in the Bicep deployment output.
  Can also be found: Azure Portal → App Service → Identity → Object (principal) ID

.PARAMETER TenantId
  Your Entra ID tenant ID.

.EXAMPLE
  .\grant-graph-permissions.ps1 `
      -ManagedIdentityPrincipalId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
      -TenantId "yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy"
#>

param(
    [Parameter(Mandatory)]
    [string] $ManagedIdentityPrincipalId,

    [Parameter(Mandatory)]
    [string] $TenantId
)

$ErrorActionPreference = 'Stop'

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantId -Scopes "AppRoleAssignment.ReadWrite.All", "Application.Read.All"

# Get the Microsoft Graph service principal in this tenant
$graphSp = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'"
Write-Host "Found Microsoft Graph SP: $($graphSp.Id)"

# Find the UserAuthMethod-TAP.ReadWrite.All app role (TAP-only, least privilege)
$appRole = $graphSp.AppRoles | Where-Object {
    $_.Value -eq 'UserAuthMethod-TAP.ReadWrite.All' -and $_.AllowedMemberTypes -contains 'Application'
}

if (-not $appRole) {
    throw "Could not find the UserAuthMethod-TAP.ReadWrite.All app role on Microsoft Graph."
}

Write-Host "Found app role: $($appRole.Value) ($($appRole.Id))"

# Check if already assigned
$existing = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentityPrincipalId |
    Where-Object { $_.AppRoleId -eq $appRole.Id -and $_.ResourceId -eq $graphSp.Id }

if ($existing) {
    Write-Host "Permission already assigned. Nothing to do." -ForegroundColor Green
} else {
    $params = @{
        PrincipalId = $ManagedIdentityPrincipalId
        ResourceId  = $graphSp.Id
        AppRoleId   = $appRole.Id
    }

    New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ManagedIdentityPrincipalId -BodyParameter $params | Out-Null
    Write-Host "Successfully granted UserAuthMethod-TAP.ReadWrite.All" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. The managed identity can now create Temporary Access Passes." -ForegroundColor Green
