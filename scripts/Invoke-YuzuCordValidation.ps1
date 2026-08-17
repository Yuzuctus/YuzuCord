[CmdletBinding()]
param(
    [string]$DistributionDirectory = (Split-Path $PSScriptRoot -Parent),

    [string]$VencordDirectory,

    [ValidateSet("All", "Catalog", "Vencord", "Installer")]
    [string[]]$Targets = @("All"),

    [switch]$AllowLocalGitSources,

    [switch]$InstallVencordDependencies,

    [switch]$IncludeReporter,

    [switch]$PublishInstaller,

    [string]$InstallerOutputDirectory,

    [string]$InstallerReleaseTag
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "YuzuCord.Validation.psm1") -Force
Invoke-YuzuCordValidation `
    -DistributionDirectory $DistributionDirectory `
    -VencordDirectory $VencordDirectory `
    -Targets $Targets `
    -AllowLocalGitSources:$AllowLocalGitSources `
    -InstallVencordDependencies:$InstallVencordDependencies `
    -IncludeReporter:$IncludeReporter `
    -PublishInstaller:$PublishInstaller `
    -InstallerOutputDirectory $InstallerOutputDirectory `
    -InstallerReleaseTag $InstallerReleaseTag
