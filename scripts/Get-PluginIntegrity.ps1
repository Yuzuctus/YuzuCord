[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CatalogPath,

    [Parameter(Mandatory = $true)]
    [string]$PluginId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "PluginCatalog.psm1") -Force

$integrity = Get-YuzuctusExternalPluginIntegrity `
    -CatalogPath $CatalogPath `
    -PluginId $PluginId

Write-Output $integrity
