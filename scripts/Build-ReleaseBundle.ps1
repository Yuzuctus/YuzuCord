[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DistributionDirectory,

    [Parameter(Mandatory = $true)]
    [string]$VencordDirectory,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^v(?:[0-9]+\.[0-9]+\.[0-9]+(?:-beta\.[0-9]+)?|[0-9]+-beta[0-9]+)$")]
    [string]$Version,

    [string]$CatalogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Resolve-ExistingDirectory {
    param([string]$Path, [string]$DisplayName)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$DisplayName directory was not found at '$Path'."
    }

    return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Get-GitCommit {
    param([string]$RepositoryDirectory)

    $commit = & git -C $RepositoryDirectory rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commit)) {
        throw "Could not resolve the Git commit for '$RepositoryDirectory'."
    }

    $value = $commit.Trim()
    if ($value -notmatch '^[0-9a-fA-F]{40}$') {
        throw "The Git commit for '$RepositoryDirectory' is invalid."
    }

    return $value.ToLowerInvariant()
}

function Get-GitRemote {
    param([string]$RepositoryDirectory)

    $remote = & git -C $RepositoryDirectory remote get-url origin
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($remote)) {
        throw "Could not resolve the Git remote for '$RepositoryDirectory'."
    }

    return $remote.Trim()
}

function Get-Sha256Text {
    param([string]$Text)

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $algorithm.ComputeHash($bytes)
        return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $algorithm.Dispose()
    }
}

function Assert-RelativePath {
    param(
        [string]$Path,
        [string]$DisplayName
    )

    if ([string]::IsNullOrWhiteSpace($Path) `
        -or [IO.Path]::IsPathRooted($Path) `
        -or $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "$DisplayName must be a safe relative path: '$Path'."
    }
}

function Read-PluginCatalog {
    param(
        [string]$Path,
        [string]$DistributionRoot
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Plugin catalog was not found at '$Path'."
    }

    $catalog = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ([int]$catalog.schemaVersion -ne 1) {
        throw "Unsupported plugin catalog schema version '$($catalog.schemaVersion)'."
    }

    $plugins = @($catalog.plugins)
    if ($plugins.Count -eq 0) {
        throw "The plugin catalog does not contain any plugin."
    }

    $commit = Get-GitCommit $DistributionRoot
    $seenIds = @{}
    $entries = foreach ($plugin in $plugins) {
        $id = [string]$plugin.id
        if ($id -notmatch '^[a-z][A-Za-z0-9]*$') {
            throw "Plugin id '$id' is invalid."
        }
        if ($seenIds.ContainsKey($id)) {
            throw "Plugin id '$id' appears more than once in the catalog."
        }
        $seenIds[$id] = $true

        $sourcePath = [string]$plugin.sourcePath
        Assert-RelativePath $sourcePath "Plugin '$id' sourcePath"
        $sourceRoot = [IO.Path]::GetFullPath((Join-Path $DistributionRoot $sourcePath))
        if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
            throw "Plugin '$id' sourcePath was not found at '$sourceRoot'."
        }

        $files = @($plugin.files)
        if ($files.Count -eq 0) {
            throw "Plugin '$id' does not declare any source files."
        }
        foreach ($file in $files) {
            Assert-RelativePath ([string]$file) "Plugin '$id' source file"
        }

        $entrypoint = [string]$plugin.entrypoint
        Assert-RelativePath $entrypoint "Plugin '$id' entrypoint"
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $entrypoint) -PathType Leaf)) {
            throw "Plugin '$id' entrypoint was not found at '$sourceRoot\$entrypoint'."
        }

        $licenseFile = [string]$plugin.licenseFile
        Assert-RelativePath $licenseFile "Plugin '$id' licenseFile"
        if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $licenseFile) -PathType Leaf)) {
            throw "Plugin '$id' licenseFile was not found at '$sourceRoot\$licenseFile'."
        }
        if ([string]::IsNullOrWhiteSpace([string]$plugin.displayName) `
            -or [string]::IsNullOrWhiteSpace([string]$plugin.repository) `
            -or [string]::IsNullOrWhiteSpace([string]$plugin.license)) {
            throw "Plugin '$id' is missing displayName, repository, or license metadata."
        }

        [ordered]@{
            id = $id
            displayName = [string]$plugin.displayName
            repository = [string]$plugin.repository
            commit = $commit
            sourcePath = $sourcePath
            entrypoint = $entrypoint
            files = @($files | ForEach-Object { [string]$_ })
            settingsKey = [string]$plugin.settingsKey
            license = [string]$plugin.license
            licenseFile = $licenseFile
            maintainer = [string]$plugin.maintainer
            status = [string]$plugin.status
        }
    }

    $entryArray = @($entries)
    $canonical = ConvertTo-Json -InputObject $entryArray -Depth 8 -Compress
    return [PSCustomObject]@{
        Entries = $entryArray
        Digest = Get-Sha256Text $canonical
        DistributionCommit = $commit
    }
}

$distributionRoot = Resolve-ExistingDirectory $DistributionDirectory "Yuzuctus Vencord distribution"
$vencordRoot = Resolve-ExistingDirectory $VencordDirectory "Vencord"
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$catalogFile = if ([string]::IsNullOrWhiteSpace($CatalogPath)) {
    Join-Path $distributionRoot "catalog\plugins.json"
} else {
    $CatalogPath
}
$catalogInfo = Read-PluginCatalog $catalogFile $distributionRoot
$vencordCommit = Get-GitCommit $vencordRoot
$vencordRepository = Get-GitRemote $vencordRoot
$stagingRoot = Join-Path $outputRoot (".bundle-" + [Guid]::NewGuid().ToString("N"))
$distRoot = Join-Path $stagingRoot "dist"
$toolsRoot = Join-Path $stagingRoot "tools"
$licensesRoot = Join-Path $stagingRoot "licenses"
$catalogRoot = Join-Path $stagingRoot "catalog"
$bundlePath = Join-Path $outputRoot "YuzuctusVencordBundle.zip"

New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
New-Item -ItemType Directory -Force -Path $distRoot, $toolsRoot, $licensesRoot, $catalogRoot | Out-Null

try {
    $openAsarRelease = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/GooseMod/OpenAsar/releases/tags/nightly" `
        -Headers @{ "User-Agent" = "YuzuctusVencordReleaseBuilder" }
    $openAsarAsset = $openAsarRelease.assets |
        Where-Object { $_.name -eq "app.asar" } |
        Select-Object -First 1
    if (-not $openAsarAsset -or $openAsarAsset.digest -notmatch '^sha256:[0-9a-fA-F]{64}$') {
        throw "The official OpenAsar release does not publish a valid SHA-256 digest."
    }
    if ($openAsarAsset.browser_download_url -notmatch '^https://github\.com/GooseMod/OpenAsar/releases/download/') {
        throw "The official OpenAsar asset has an unexpected download URL."
    }
    $openAsarPublishedAt = [DateTimeOffset]::Parse(
        $openAsarRelease.published_at,
        [Globalization.CultureInfo]::InvariantCulture
    )
    $openAsarVerificationPath = Join-Path $stagingRoot "OpenAsar.verify.asar"
    Invoke-WebRequest `
        -Uri $openAsarAsset.browser_download_url `
        -OutFile $openAsarVerificationPath `
        -UseBasicParsing
    $expectedOpenAsarHash = $openAsarAsset.digest.Substring("sha256:".Length).ToLowerInvariant()
    $actualOpenAsarHash = (Get-FileHash `
        -LiteralPath $openAsarVerificationPath `
        -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualOpenAsarHash -ne $expectedOpenAsarHash) {
        throw "The official OpenAsar asset does not match its published SHA-256 digest."
    }
    $openAsarBytes = [IO.File]::ReadAllBytes($openAsarVerificationPath)
    if (-not [Text.Encoding]::ASCII.GetString($openAsarBytes).Contains("OpenAsar")) {
        throw "The official OpenAsar asset does not contain the expected signature."
    }
    Remove-Item -LiteralPath $openAsarVerificationPath

    Get-ChildItem -LiteralPath (Join-Path $vencordRoot "dist") -File |
        Where-Object { $_.Name -match '^(package\.json|patcher\.|preload\.|renderer\.)' } |
        Copy-Item -Destination $distRoot -Force

    $requiredDistFiles = @("patcher.js", "preload.js", "renderer.js", "renderer.css")
    foreach ($requiredFile in $requiredDistFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $distRoot $requiredFile) -PathType Leaf)) {
            throw "The compiled Vencord file '$requiredFile' is missing."
        }
    }

    $officialInstallerPath = Join-Path $toolsRoot "VencordInstallerCli.exe"
    $officialChecksumsPath = Join-Path $toolsRoot "checksums.sha256"
    Invoke-WebRequest `
        -Uri "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe" `
        -OutFile $officialInstallerPath `
        -UseBasicParsing
    Invoke-WebRequest `
        -Uri "https://github.com/Vencord/Installer/releases/latest/download/checksums.sha256" `
        -OutFile $officialChecksumsPath `
        -UseBasicParsing

    $checksumLine = Get-Content -LiteralPath $officialChecksumsPath |
        Where-Object { $_ -match '\sVencordInstallerCli\.exe$' } |
        Select-Object -First 1
    if (-not $checksumLine) {
        throw "VencordInstallerCli.exe is missing from the official checksum file."
    }

    $expectedInstallerHash = ($checksumLine -split '\s+')[0]
    $actualInstallerHash = (Get-FileHash -LiteralPath $officialInstallerPath -Algorithm SHA256).Hash
    if ($actualInstallerHash -ne $expectedInstallerHash) {
        throw "The official Vencord installer checksum does not match."
    }
    Remove-Item -LiteralPath $officialChecksumsPath

    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/Vencord/Installer/main/LICENSE" `
        -OutFile (Join-Path $licensesRoot "Vencord-Installer-LICENSE") `
        -UseBasicParsing
    Copy-Item `
        -LiteralPath (Join-Path $vencordRoot "LICENSE") `
        -Destination (Join-Path $licensesRoot "Vencord-LICENSE")
    Copy-Item `
        -LiteralPath (Join-Path $distributionRoot "LICENSE") `
        -Destination (Join-Path $licensesRoot "YuzuctusVencord-LICENSE")
    Copy-Item `
        -LiteralPath (Join-Path $distributionRoot "installer\THIRD_PARTY_NOTICES.md") `
        -Destination $stagingRoot
    Copy-Item -LiteralPath $catalogFile -Destination (Join-Path $catalogRoot "plugins.json")

    foreach ($plugin in $catalogInfo.Entries) {
        $pluginSourceRoot = Join-Path $distributionRoot $plugin.sourcePath
        $declaredLicense = Join-Path $pluginSourceRoot $plugin.licenseFile
        if (Test-Path -LiteralPath $declaredLicense -PathType Leaf) {
            Copy-Item -LiteralPath $declaredLicense -Destination (Join-Path $licensesRoot "$($plugin.id)-LICENSE")
        }
    }

    $manifest = [ordered]@{
        schemaVersion = 2
        productId = "YuzuctusVencord"
        productName = "Yuzuctus Vencord"
        version = $Version
        vencordRepository = $vencordRepository
        vencordCommit = $vencordCommit
        distributionCommit = $catalogInfo.DistributionCommit
        pluginCommit = $catalogInfo.DistributionCommit
        pluginsDigest = $catalogInfo.Digest
        plugins = @($catalogInfo.Entries)
        openAsarDigest = $openAsarAsset.digest.ToLowerInvariant()
        openAsarPublishedAtUtc = $openAsarPublishedAt.ToUniversalTime().ToString("o")
        builtAtUtc = [DateTimeOffset]::UtcNow.ToString("o")
        requiredFiles = @(
            "dist/patcher.js"
            "dist/preload.js"
            "dist/renderer.js"
            "dist/renderer.css"
            "tools/VencordInstallerCli.exe"
        )
    }
    $manifestPath = Join-Path $stagingRoot "manifest.json"
    $manifest | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $manifestPath -Encoding utf8
    Copy-Item `
        -LiteralPath $manifestPath `
        -Destination (Join-Path $outputRoot "YuzuctusVencordBundle.manifest.json") `
        -Force

    Compress-Archive `
        -Path (Join-Path $stagingRoot "*") `
        -DestinationPath $bundlePath `
        -CompressionLevel Optimal `
        -Force
    $bundleHash = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$bundleHash  YuzuctusVencordBundle.zip" |
        Set-Content -LiteralPath "$bundlePath.sha256" -Encoding ascii -NoNewline

    Write-Host "Built $bundlePath"
    Write-Host "Vencord commit: $($manifest.vencordCommit)"
    Write-Host "Plugin catalog digest: $($manifest.pluginsDigest)"
    Write-Host "OpenAsar digest: $($manifest.openAsarDigest)"
} finally {
    $resolvedStaging = [IO.Path]::GetFullPath($stagingRoot)
    $resolvedOutput = [IO.Path]::GetFullPath($outputRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    if ((Test-Path -LiteralPath $resolvedStaging) -and
        $resolvedStaging.StartsWith(
            $resolvedOutput + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase
        )) {
        Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
    }
}
