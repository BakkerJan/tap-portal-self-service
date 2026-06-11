#Requires -Modules Microsoft.Graph.Applications

<#
.SYNOPSIS
  Grants the Logic App Managed Identity the Graph API permission required
  to create Temporary Access Passes on behalf of any user.

.DESCRIPTION
  Assigns the Application permission "UserAuthenticationMethod.ReadWrite.All"
  to the Logic App's System-Assigned Managed Identity.

  Run this ONCE after deploying main.bicep.

.PARAMETER ManagedIdentityPrincipalId
  The Object ID of the Logic App's Managed Identity.
  Shown as 'managedIdentityPrincipalId' in the Bicep deployment output.
  Can also be found: Azure Portal → Logic App → Identity → Object (principal) ID

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

# Find the UserAuthenticationMethod.ReadWrite.All app role
$appRole = $graphSp.AppRoles | Where-Object {
    $_.Value -eq 'UserAuthenticationMethod.ReadWrite.All' -and $_.AllowedMemberTypes -contains 'Application'
}

if (-not $appRole) {
    throw "Could not find the UserAuthenticationMethod.ReadWrite.All app role on Microsoft Graph."
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
    Write-Host "Successfully granted UserAuthenticationMethod.ReadWrite.All" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done. The Logic App Managed Identity can now create Temporary Access Passes." -ForegroundColor Green
