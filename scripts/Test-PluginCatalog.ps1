[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "PluginCatalog.psm1") -Force

function Assert-True {
    param([bool]$Condition, [string]$Message)

    if (-not $Condition) {
        throw "Assertion failed: $Message"
    }
}

function Invoke-FixtureGit {
    param([string]$Repository, [string[]]$Arguments)

    $output = & git -C $Repository @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Fixture Git command failed: git -C '$Repository' $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)"
    }

    return ($output -join "`n").Trim()
}

function Initialize-FixtureRepository {
    param([string]$Path)

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Invoke-FixtureGit $Path @("init", "--quiet") | Out-Null
    Invoke-FixtureGit $Path @("config", "user.name", "Yuzuctus catalog tests") | Out-Null
    Invoke-FixtureGit $Path @("config", "user.email", "catalog-tests@example.invalid") | Out-Null
}

function Save-Json {
    param([object]$Value, [string]$Path)

    $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-PluginDefinition {
    param(
        [string]$Id,
        [object]$Source,
        [object[]]$Mappings,
        [ValidateSet("yuzuctus", "thirdParty")]
        [string]$Provenance = "yuzuctus",
        [string[]]$Dependencies = @()
    )

    return [ordered]@{
        id = $Id
        displayName = $Id
        source = $Source
        mappings = $Mappings
        entrypoint = "index.tsx"
        settingsKey = $Id
        provenance = $Provenance
        dependencies = $Dependencies
        conflicts = @()
        license = "GPL-3.0-or-later"
        licenseFile = "LICENSE"
        maintainer = "Yuzuctus"
        status = "experimental"
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("yuzuctus-plugin-catalog-tests-" + [Guid]::NewGuid().ToString("N"))
$distributionRoot = Join-Path $testRoot "distribution"
$externalRoot = Join-Path $testRoot "external"
$vencordRoot = Join-Path $testRoot "vencord"

try {
    Initialize-FixtureRepository $distributionRoot
    $localRoot = Join-Path $distributionRoot "plugins\localPlugin"
    New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
    "export default {};" | Set-Content -LiteralPath (Join-Path $localRoot "index.tsx") -Encoding UTF8
    "GPL-3.0-or-later" | Set-Content -LiteralPath (Join-Path $localRoot "LICENSE") -Encoding UTF8
    Invoke-FixtureGit $distributionRoot @("add", ".") | Out-Null
    Invoke-FixtureGit $distributionRoot @("commit", "--quiet", "-m", "test: local plugin") | Out-Null

    Initialize-FixtureRepository $externalRoot
    "export default { name: 'external' };" | Set-Content -LiteralPath (Join-Path $externalRoot "index.tsx") -Encoding UTF8
    "GPL-3.0-or-later" | Set-Content -LiteralPath (Join-Path $externalRoot "LICENSE") -Encoding UTF8
    Invoke-FixtureGit $externalRoot @("add", ".") | Out-Null
    Invoke-FixtureGit $externalRoot @("commit", "--quiet", "-m", "test: external plugin") | Out-Null
    $externalCommit = Invoke-FixtureGit $externalRoot @("rev-parse", "HEAD")

    New-Item -ItemType Directory -Path (Join-Path $vencordRoot "src\userplugins\unmanagedPlugin") -Force | Out-Null
    "keep" | Set-Content -LiteralPath (Join-Path $vencordRoot "src\userplugins\unmanagedPlugin\marker.txt") -Encoding UTF8
    New-Item -ItemType Directory -Path (Join-Path $vencordRoot "src\userplugins\stalePlugin") -Force | Out-Null
    "remove" | Set-Content -LiteralPath (Join-Path $vencordRoot "src\userplugins\stalePlugin\marker.txt") -Encoding UTF8
    New-Item -ItemType Directory -Path (Join-Path $vencordRoot "src\userplugins\.yuzuctus") -Force | Out-Null
    Save-Json ([ordered]@{
        schemaVersion = 1
        plugins = @([ordered]@{ id = "stalePlugin" })
    }) (Join-Path $vencordRoot "src\userplugins\.yuzuctus\resolved-plugins.json")

    $catalogPath = Join-Path $distributionRoot "catalog.json"
    $localPlugin = New-PluginDefinition `
        -Id "localPlugin" `
        -Source ([ordered]@{
            type = "local"
            path = "plugins/localPlugin"
            repository = "https://github.com/Yuzuctus/localPlugin.git"
        }) `
        -Mappings @([ordered]@{ from = "."; to = "." })
    $externalPlugin = New-PluginDefinition `
        -Id "externalPlugin" `
        -Source ([ordered]@{
            type = "git"
            repository = $externalRoot
            commit = $externalCommit
            integrity = "sha256:" + ("0" * 64)
            review = [ordered]@{ approvedBy = "Yuzuctus"; reviewedAt = "2026-08-08" }
        }) `
        -Mappings @([ordered]@{ from = "."; to = "." }) `
        -Provenance "thirdParty" `
        -Dependencies @("localPlugin")
    Save-Json ([ordered]@{
        schemaVersion = 2
        plugins = @($externalPlugin, $localPlugin)
    }) $catalogPath
    Invoke-FixtureGit $distributionRoot @("add", "catalog.json") | Out-Null
    Invoke-FixtureGit $distributionRoot @("commit", "--quiet", "-m", "test: catalog") | Out-Null

    $reviewedIntegrity = Get-YuzuctusExternalPluginIntegrity `
        -CatalogPath $catalogPath `
        -PluginId "externalPlugin" `
        -AllowLocalGitSources
    Assert-True (
        $reviewedIntegrity -match '^sha256:[0-9a-f]{64}$'
    ) "the external review command should hash exactly the materialized files"
    $externalPlugin.source.integrity = $reviewedIntegrity
    Save-Json ([ordered]@{
        schemaVersion = 2
        plugins = @($externalPlugin, $localPlugin)
    }) $catalogPath
    Invoke-FixtureGit $distributionRoot @("add", "catalog.json") | Out-Null
    Invoke-FixtureGit $distributionRoot @("commit", "--quiet", "-m", "test: reviewed integrity") | Out-Null

    $first = Invoke-YuzuctusPluginMaterialization `
        -CatalogPath $catalogPath `
        -SourceRoot $distributionRoot `
        -VencordDirectory $vencordRoot `
        -AllowLocalGitSources

    Assert-True ($first.plugins.Count -eq 2) "both plugins should be resolved"
    Assert-True ($first.plugins[0].id -eq "localPlugin") "dependencies should be ordered before dependants"
    Assert-True (Test-Path -LiteralPath (Join-Path $vencordRoot "src\userplugins\localPlugin\index.tsx")) "local plugin should be materialized"
    Assert-True (Test-Path -LiteralPath (Join-Path $vencordRoot "src\userplugins\externalPlugin\index.tsx")) "external plugin should be materialized"
    Assert-True (Test-Path -LiteralPath (Join-Path $vencordRoot "src\userplugins\externalPlugin\index.yuzuctus-source.tsx")) "the original external entrypoint should be preserved beside its wrapper"
    Assert-True (
        (Get-Content -LiteralPath (Join-Path $vencordRoot "src\userplugins\localPlugin\index.tsx") -Raw) -match 'YuzuMod'
    ) "a Yuzuctus plugin should receive the YuzuMod tag"
    Assert-True (
        (Get-Content -LiteralPath (Join-Path $vencordRoot "src\userplugins\externalPlugin\index.tsx") -Raw) -match 'ThirdParty'
    ) "a third-party plugin should receive the ThirdParty tag"
    Assert-True ($first.plugins[0].provenance -eq "yuzuctus") "the resolved manifest should preserve Yuzuctus provenance"
    Assert-True ($first.plugins[1].provenance -eq "thirdParty") "the resolved manifest should preserve third-party provenance"
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $vencordRoot "src\userplugins\stalePlugin"))) "previously managed stale plugin should be removed"
    Assert-True (Test-Path -LiteralPath (Join-Path $vencordRoot "src\userplugins\unmanagedPlugin\marker.txt")) "unmanaged userplugin should be preserved"

    $second = Invoke-YuzuctusPluginMaterialization `
        -CatalogPath $catalogPath `
        -SourceRoot $distributionRoot `
        -VencordDirectory $vencordRoot `
        -AllowLocalGitSources
    Assert-True ($first.pluginsDigest -eq $second.pluginsDigest) "the resolved plugin digest should be deterministic"

    $materializeLockPath = Join-Path $vencordRoot "src\userplugins\.yuzuctus\materialize.lock"
    $heldMaterializeLock = [IO.File]::Open(
        $materializeLockPath,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
    try {
        $concurrentRunRejected = $false
        try {
            Invoke-YuzuctusPluginMaterialization `
                -CatalogPath $catalogPath `
                -SourceRoot $distributionRoot `
                -VencordDirectory $vencordRoot `
                -AllowLocalGitSources | Out-Null
        } catch {
            $concurrentRunRejected = $_.Exception.Message -match "already running"
        }
        Assert-True $concurrentRunRejected "concurrent materialization should be rejected"
    } finally {
        $heldMaterializeLock.Dispose()
    }

    $installedLocalEntrypoint = Join-Path $vencordRoot "src\userplugins\localPlugin\index.tsx"
    "preserve this installed version" | Set-Content -LiteralPath $installedLocalEntrypoint -Encoding UTF8
    $temporaryManifestPath = Join-Path $vencordRoot "src\userplugins\.yuzuctus\resolved-plugins.json.tmp"
    $heldManifest = [IO.File]::Open(
        $temporaryManifestPath,
        [IO.FileMode]::OpenOrCreate,
        [IO.FileAccess]::ReadWrite,
        [IO.FileShare]::None
    )
    try {
        $deploymentFailed = $false
        try {
            Invoke-YuzuctusPluginMaterialization `
                -CatalogPath $catalogPath `
                -SourceRoot $distributionRoot `
                -VencordDirectory $vencordRoot `
                -AllowLocalGitSources | Out-Null
        } catch {
            $deploymentFailed = $true
        }
        Assert-True $deploymentFailed "the locked resolved manifest should force a deployment failure"
        Assert-True (
            (Get-Content -LiteralPath $installedLocalEntrypoint -Raw) -match "preserve this installed version"
        ) "a failed deployment should restore the previously installed plugin"
    } finally {
        $heldManifest.Dispose()
        Remove-Item -LiteralPath $temporaryManifestPath -Force -ErrorAction SilentlyContinue
    }

    Invoke-YuzuctusPluginMaterialization `
        -CatalogPath $catalogPath `
        -SourceRoot $distributionRoot `
        -VencordDirectory $vencordRoot `
        -AllowLocalGitSources | Out-Null

    $invalidIntegrity = "sha256:" + ("0" * 64)
    $externalPlugin.source.integrity = $invalidIntegrity
    Save-Json ([ordered]@{ schemaVersion = 2; plugins = @($localPlugin, $externalPlugin) }) $catalogPath
    $integrityRejected = $false
    try {
        Invoke-YuzuctusPluginMaterialization `
            -CatalogPath $catalogPath `
            -SourceRoot $distributionRoot `
            -VencordDirectory $vencordRoot `
            -AllowLocalGitSources | Out-Null
    } catch {
        $integrityRejected = $_.Exception.Message -match "integrity mismatch"
    }
    Assert-True $integrityRejected "an external plugin with an invalid digest should be rejected"
    Assert-True (Test-Path -LiteralPath (Join-Path $vencordRoot "src\userplugins\externalPlugin\index.tsx")) "a failed resolution should not remove the installed plugin"

    $externalPlugin.source.integrity = $reviewedIntegrity
    $localPlugin.mappings = @([ordered]@{ from = "..\outside"; to = "." })
    Save-Json ([ordered]@{ schemaVersion = 2; plugins = @($localPlugin, $externalPlugin) }) $catalogPath
    $unsafePathRejected = $false
    try {
        Read-YuzuctusPluginCatalog $catalogPath -AllowLocalGitSources | Out-Null
    } catch {
        $unsafePathRejected = $_.Exception.Message -match "safe relative path"
    }
    Assert-True $unsafePathRejected "path traversal should be rejected"

    Write-Host "Plugin catalog integration tests passed."
} finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
