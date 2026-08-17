[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CatalogPath,

    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$VencordDirectory,

    [switch]$AllowLocalGitSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$modulePath = Join-Path $PSScriptRoot "PluginCatalog.psm1"
Import-Module $modulePath -Force

Invoke-YuzuctusPluginMaterialization `
    -CatalogPath $CatalogPath `
    -SourceRoot $SourceRoot `
    -VencordDirectory $VencordDirectory `
    -AllowLocalGitSources:$AllowLocalGitSources | Out-Null
