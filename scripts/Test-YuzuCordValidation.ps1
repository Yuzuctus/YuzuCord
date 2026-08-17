[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$validationModulePath = Join-Path $PSScriptRoot "YuzuCord.Validation.psm1"
$loadedValidationModule = Get-Module | Where-Object {
    $_.Path -and [IO.Path]::GetFullPath($_.Path) -eq [IO.Path]::GetFullPath($validationModulePath)
}
if (-not $loadedValidationModule) {
    Import-Module $validationModulePath -Force
}

function Assert-Equal {
    param(
        [object]$Actual,
        [object]$Expected,
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "Assertion failed: $Message. Expected '$Expected', received '$Actual'."
    }
}

function Assert-Sequence {
    param(
        [object[]]$Actual,
        [object[]]$Expected,
        [string]$Message
    )

    Assert-Equal ($Actual -join "|") ($Expected -join "|") $Message
}

$distributionRoot = Split-Path $PSScriptRoot -Parent

Assert-Sequence `
    @(Resolve-YuzuCordValidationTargets -Targets @("All")) `
    @("Catalog", "Vencord", "Installer") `
    "All expands to every validation target in stable order"
Assert-Sequence `
    @(Resolve-YuzuCordValidationTargets -Targets @("Installer", "Catalog", "Installer")) `
    @("Catalog", "Installer") `
    "Explicit targets are deduplicated and normalized"
Assert-Sequence `
    @(Resolve-YuzuCordValidationTargets -Targets @()) `
    @("Catalog", "Vencord", "Installer") `
    "An empty target list uses the complete validation suite"

$invalidTargetRejected = $false
try {
    Resolve-YuzuCordValidationTargets -Targets @("Unknown") | Out-Null
} catch {
    $invalidTargetRejected = $_.Exception.Message -match "Unknown YuzuCord validation target"
}
Assert-Equal $invalidTargetRejected $true "Unknown validation targets are rejected"

$scriptNames = @(Get-YuzuCordPowerShellFiles -DistributionDirectory $distributionRoot |
    ForEach-Object { $_.Name })
foreach ($requiredScript in @(
    "Invoke-YuzuCordValidation.ps1",
    "Materialize-Plugins.ps1",
    "PluginCatalog.psm1",
    "Test-YuzuCordValidation.ps1",
    "YuzuCord.Tui.ps1",
    "YuzuCord.Validation.psm1"
)) {
    Assert-Equal `
        ($scriptNames -contains $requiredScript) `
        $true `
        "PowerShell discovery includes $requiredScript"
}

Assert-YuzuCordPowerShellSyntax -DistributionDirectory $distributionRoot

$ciWorkflow = Get-Content -Raw -LiteralPath (Join-Path $distributionRoot ".github\workflows\ci.yml")
$releaseWorkflow = Get-Content -Raw -LiteralPath (Join-Path $distributionRoot ".github\workflows\release.yml")
Assert-Equal `
    ([regex]::Matches($ciWorkflow, "Invoke-YuzuCordValidation\.ps1").Count) `
    2 `
    "Both CI jobs use the shared validation entrypoint"
Assert-Equal `
    ([regex]::Matches($releaseWorkflow, "Invoke-YuzuCordValidation\.ps1").Count) `
    1 `
    "The release workflow uses the shared validation entrypoint"

$validationModule = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot "YuzuCord.Validation.psm1")
foreach ($requiredGate in @("tsx", "eslint", "stylelint", "testTsc", "buildReporter", "dotnet")) {
    Assert-Equal `
        ($validationModule -match [regex]::Escape("`"$requiredGate`"")) `
        $true `
        "Shared validation keeps the $requiredGate gate"
}

Write-Host "YuzuCord validation orchestration tests passed."
