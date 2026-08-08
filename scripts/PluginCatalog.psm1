Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-ObjectProperty {
    param([object]$Object, [string]$Name)

    return $null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name
}

function Get-ObjectArray {
    param([object]$Object, [string]$Name)

    if (-not (Test-ObjectProperty $Object $Name) -or $null -eq $Object.$Name) {
        return @()
    }

    return @($Object.$Name)
}

function Assert-Text {
    param([object]$Value, [string]$DisplayName)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        throw "$DisplayName must not be empty."
    }
}

function Assert-AllowedProperties {
    param(
        [object]$Object,
        [string[]]$Allowed,
        [string]$DisplayName
    )

    foreach ($property in $Object.PSObject.Properties.Name) {
        if ($Allowed -notcontains $property) {
            throw "$DisplayName contains unsupported property '$property'."
        }
    }
}

function Assert-SafeRelativePath {
    param(
        [string]$Path,
        [string]$DisplayName,
        [switch]$AllowCurrentDirectory
    )

    Assert-Text $Path $DisplayName
    if ([IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "$DisplayName must be a safe relative path: '$Path'."
    }
    if (-not $AllowCurrentDirectory -and $Path -eq ".") {
        throw "$DisplayName cannot target the directory root."
    }
}

function Get-NormalizedRoot {
    param([string]$Path, [string]$DisplayName)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$DisplayName directory was not found at '$Path'."
    }

    return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
}

function Resolve-ContainedPath {
    param(
        [string]$Root,
        [string]$RelativePath,
        [string]$DisplayName,
        [switch]$AllowRoot
    )

    Assert-SafeRelativePath $RelativePath $DisplayName -AllowCurrentDirectory:$AllowRoot
    $resolved = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath)).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $isRoot = $resolved.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase)
    $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    if ((-not $AllowRoot -and $isRoot) -or
        (-not $isRoot -and -not $resolved.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw "$DisplayName resolves outside '$rootPath'."
    }

    return $resolved
}

function Get-RelativeFilePath {
    param([string]$Root, [string]$Path)

    $prefix = $Root.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    ) + [IO.Path]::DirectorySeparatorChar
    if (-not $Path.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "'$Path' is not below '$Root'."
    }

    return $Path.Substring($prefix.Length).Replace("\", "/")
}

function Get-Sha256Text {
    param([string]$Text)

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        return (($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
    } finally {
        $algorithm.Dispose()
    }
}

function Test-GitLfsPointer {
    param([string]$Path)

    $signature = [Text.Encoding]::ASCII.GetBytes("version https://git-lfs.github.com/spec/v1")
    $stream = [IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -lt $signature.Length) { return $false }

        $bytes = New-Object byte[] $signature.Length
        if ($stream.Read($bytes, 0, $bytes.Length) -ne $bytes.Length) { return $false }
        for ($index = 0; $index -lt $signature.Length; $index++) {
            if ($bytes[$index] -ne $signature[$index]) { return $false }
        }
        return $true
    } finally {
        $stream.Dispose()
    }
}

function Get-YuzuctusTreeDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Root)

    $rootPath = Get-NormalizedRoot $Root "Plugin tree"
    $records = foreach ($file in Get-ChildItem -LiteralPath $rootPath -Recurse -Force -File |
        Sort-Object { Get-RelativeFilePath $rootPath $_.FullName }) {
        $relative = Get-RelativeFilePath $rootPath $file.FullName
        if ($relative -eq ".git" -or $relative.StartsWith(".git/", [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in plugin sources: '$relative'."
        }

        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relative`0$($file.Length)`0$hash"
    }

    return Get-Sha256Text (($records -join "`n") + "`n")
}

function Invoke-GitCapture {
    param([string[]]$Arguments, [string]$DisplayName)

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git @Arguments 2>&1
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($LASTEXITCODE -ne 0) {
        throw "$DisplayName failed: $($output -join [Environment]::NewLine)"
    }

    return ($output -join "`n").Trim()
}

function Read-YuzuctusPluginCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [switch]$AllowLocalGitSources
    )

    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
        throw "Plugin catalog was not found at '$CatalogPath'."
    }

    $catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-AllowedProperties $catalog @('$schema', 'schemaVersion', 'plugins') "Plugin catalog"
    if ([int]$catalog.schemaVersion -ne 2) {
        throw "Unsupported plugin catalog schema version '$($catalog.schemaVersion)'."
    }

    $plugins = @($catalog.plugins)
    if ($plugins.Count -eq 0) {
        throw "The plugin catalog does not contain any plugin."
    }

    $byId = @{}
    foreach ($plugin in $plugins) {
        $id = [string]$plugin.id
        if ($id -notmatch '^[a-z][A-Za-z0-9]*$') {
            throw "Plugin id '$id' is invalid."
        }
        if ($byId.ContainsKey($id)) {
            throw "Plugin id '$id' appears more than once in the catalog."
        }
        $byId[$id] = $plugin

        Assert-AllowedProperties $plugin @(
            'id', 'displayName', 'source', 'mappings', 'entrypoint', 'settingsKey',
            'distributionTags', 'dependencies', 'conflicts', 'license', 'licenseFile',
            'maintainer', 'status'
        ) "Plugin '$id'"

        foreach ($property in @("displayName", "entrypoint", "license", "licenseFile", "maintainer", "status")) {
            if (-not (Test-ObjectProperty $plugin $property)) {
                throw "Plugin '$id' is missing '$property'."
            }
            Assert-Text $plugin.$property "Plugin '$id' $property"
        }
        if (-not (Test-ObjectProperty $plugin "settingsKey")) {
            throw "Plugin '$id' is missing 'settingsKey'."
        }
        foreach ($property in @("distributionTags", "dependencies", "conflicts", "mappings")) {
            if (-not (Test-ObjectProperty $plugin $property)) {
                throw "Plugin '$id' is missing '$property'."
            }
        }
        if ([string]$plugin.status -notin @("maintained", "beta", "experimental", "deprecated")) {
            throw "Plugin '$id' has an unsupported status '$($plugin.status)'."
        }

        Assert-SafeRelativePath ([string]$plugin.entrypoint) "Plugin '$id' entrypoint"
        if ([string]$plugin.entrypoint -notin @("index.ts", "index.tsx")) {
            throw "Plugin '$id' entrypoint must be index.ts or index.tsx for Vencord discovery."
        }
        Assert-SafeRelativePath ([string]$plugin.licenseFile) "Plugin '$id' licenseFile"

        $distributionTags = @(Get-ObjectArray $plugin "distributionTags")
        if ($distributionTags.Count -eq 0) {
            throw "Plugin '$id' must declare at least one distribution tag."
        }
        $seenDistributionTags = @{}
        foreach ($tag in $distributionTags) {
            $tagValue = [string]$tag
            if ($tagValue -notmatch '^[A-Za-z][A-Za-z0-9 -]{0,31}$') {
                throw "Plugin '$id' has invalid distribution tag '$tagValue'."
            }
            if ($seenDistributionTags.ContainsKey($tagValue)) {
                throw "Plugin '$id' declares distribution tag '$tagValue' more than once."
            }
            $seenDistributionTags[$tagValue] = $true
        }

        if (-not (Test-ObjectProperty $plugin "source")) {
            throw "Plugin '$id' is missing its source."
        }
        $sourceType = [string]$plugin.source.type
        if ($sourceType -eq "local") {
            Assert-AllowedProperties $plugin.source @('type', 'path', 'repository') "Plugin '$id' local source"
            Assert-SafeRelativePath ([string]$plugin.source.path) "Plugin '$id' local source path" -AllowCurrentDirectory
            if ([string]$plugin.source.repository -notmatch '^https://') {
                throw "Plugin '$id' local source repository must use HTTPS."
            }
        } elseif ($sourceType -eq "git") {
            Assert-AllowedProperties $plugin.source @(
                'type', 'repository', 'commit', 'integrity', 'review'
            ) "Plugin '$id' Git source"
            $repository = [string]$plugin.source.repository
            $isPublicGitHub = $repository -match '^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$'
            $isAllowedLocal = $AllowLocalGitSources -and
                (($repository -match '^file://') -or (Test-Path -LiteralPath $repository))
            if (-not $isPublicGitHub -and -not $isAllowedLocal) {
                throw "Plugin '$id' Git source must be a public HTTPS GitHub repository."
            }
            if ([string]$plugin.source.commit -notmatch '^[0-9a-fA-F]{40}$') {
                throw "Plugin '$id' Git source must use a full immutable 40-character commit."
            }
            if ([string]$plugin.source.integrity -notmatch '^sha256:[0-9a-fA-F]{64}$') {
                throw "Plugin '$id' Git source must declare a SHA-256 integrity value."
            }
            if (-not (Test-ObjectProperty $plugin.source "review") -or
                [string]::IsNullOrWhiteSpace([string]$plugin.source.review.approvedBy) -or
                [string]$plugin.source.review.reviewedAt -notmatch '^\d{4}-\d{2}-\d{2}$') {
                throw "Plugin '$id' Git source requires approvedBy and reviewedAt review metadata."
            }
            Assert-AllowedProperties $plugin.source.review @('approvedBy', 'reviewedAt') "Plugin '$id' Git review"
            $reviewDate = [DateTime]::MinValue
            $parsedReviewDate = [DateTime]::TryParseExact(
                [string]$plugin.source.review.reviewedAt,
                "yyyy-MM-dd",
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal,
                [ref]$reviewDate
            )
            if (-not $parsedReviewDate -or $reviewDate.Date -gt [DateTime]::UtcNow.Date) {
                throw "Plugin '$id' Git review date is invalid or in the future."
            }
        } else {
            throw "Plugin '$id' has unsupported source type '$sourceType'."
        }

        $mappings = @(Get-ObjectArray $plugin "mappings")
        if ($mappings.Count -eq 0) {
            throw "Plugin '$id' does not declare any file mapping."
        }
        foreach ($mapping in $mappings) {
            Assert-AllowedProperties $mapping @('from', 'to') "Plugin '$id' mapping"
            Assert-SafeRelativePath ([string]$mapping.from) "Plugin '$id' mapping source" -AllowCurrentDirectory
            Assert-SafeRelativePath ([string]$mapping.to) "Plugin '$id' mapping target" -AllowCurrentDirectory
        }

        foreach ($dependency in Get-ObjectArray $plugin "dependencies") {
            if ([string]$dependency -notmatch '^[a-z][A-Za-z0-9]*$' -or $dependency -eq $id) {
                throw "Plugin '$id' has invalid dependency '$dependency'."
            }
        }
        foreach ($conflict in Get-ObjectArray $plugin "conflicts") {
            if ([string]$conflict -notmatch '^[a-z][A-Za-z0-9]*$' -or $conflict -eq $id) {
                throw "Plugin '$id' has invalid conflict '$conflict'."
            }
        }
    }

    foreach ($plugin in $plugins) {
        $id = [string]$plugin.id
        foreach ($dependency in Get-ObjectArray $plugin "dependencies") {
            if (-not $byId.ContainsKey([string]$dependency)) {
                throw "Plugin '$id' depends on missing plugin '$dependency'."
            }
        }
        foreach ($conflict in Get-ObjectArray $plugin "conflicts") {
            if ($byId.ContainsKey([string]$conflict)) {
                throw "Plugin '$id' conflicts with included plugin '$conflict'."
            }
        }
    }

    $remaining = @{}
    foreach ($plugin in $plugins) {
        $remaining[[string]$plugin.id] = @(
            Get-ObjectArray $plugin "dependencies" | ForEach-Object { [string]$_ }
        )
    }
    $ordered = @()
    while ($remaining.Count -gt 0) {
        $ready = @($remaining.Keys | Where-Object {
            @($remaining[$_] | Where-Object { $remaining.ContainsKey($_) }).Count -eq 0
        } | Sort-Object)
        if ($ready.Count -eq 0) {
            throw "The plugin catalog contains a dependency cycle."
        }
        foreach ($id in $ready) {
            $ordered += ,$byId[$id]
            $remaining.Remove($id)
        }
    }

    return [PSCustomObject]@{
        Catalog = $catalog
        Plugins = $ordered
    }
}

function Assert-NoGitLinks {
    param([string]$RepositoryRoot, [string]$PluginId)

    $tree = Invoke-GitCapture @("-C", $RepositoryRoot, "ls-tree", "-r", "--full-tree", "HEAD") "Inspecting plugin '$PluginId' Git tree"
    foreach ($line in @($tree -split "`n")) {
        if ($line -match '^(120000|160000)\s') {
            throw "Plugin '$PluginId' Git source contains a symlink or submodule, which is not allowed."
        }
    }
}

function Copy-PluginMappings {
    param(
        [object]$Plugin,
        [string]$SourceRoot,
        [string]$DestinationRoot
    )

    $seenTargets = @{}
    foreach ($mapping in @($Plugin.mappings)) {
        $pluginId = [string]$Plugin.id
        $source = Resolve-ContainedPath $SourceRoot ([string]$mapping.from) "Plugin '$pluginId' mapping source" -AllowRoot
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Plugin '$pluginId' mapping source was not found at '$source'."
        }
        $targetBase = Resolve-ContainedPath $DestinationRoot ([string]$mapping.to) "Plugin '$pluginId' mapping target" -AllowRoot

        $sourceItem = Get-Item -LiteralPath $source -Force
        if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Plugin '$pluginId' mapping source cannot be a reparse point."
        }

        $copyItems = if ($sourceItem.PSIsContainer) {
            foreach ($directory in Get-ChildItem -LiteralPath $source -Recurse -Force -Directory) {
                if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw "Plugin '$pluginId' source contains a reparse point at '$($directory.FullName)'."
                }
            }
            @(Get-ChildItem -LiteralPath $source -Recurse -Force -File)
        } else {
            @($sourceItem)
        }
        foreach ($file in $copyItems) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Plugin '$pluginId' source contains a reparse point at '$($file.FullName)'."
            }

            $relative = if ($sourceItem.PSIsContainer) {
                Get-RelativeFilePath $source $file.FullName
            } else {
                ""
            }
            if ($relative -eq ".git" -or $relative.StartsWith(".git/", [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if ([string]$Plugin.source.type -eq "git" -and (Test-GitLfsPointer $file.FullName)) {
                throw "Plugin '$pluginId' contains a Git LFS pointer at '$relative'; release assets must contain the real file."
            }

            $destination = if ($sourceItem.PSIsContainer) {
                if ([string]$mapping.to -eq ".") {
                    Resolve-ContainedPath $DestinationRoot $relative "Plugin '$pluginId' mapped file"
                } else {
                    Resolve-ContainedPath $DestinationRoot (([string]$mapping.to).TrimEnd("/", "\") + "/" + $relative) "Plugin '$pluginId' mapped file"
                }
            } else {
                Resolve-ContainedPath $DestinationRoot ([string]$mapping.to) "Plugin '$pluginId' mapped file"
            }
            $destinationRelative = Get-RelativeFilePath $DestinationRoot $destination
            $targetKey = $destinationRelative.ToLowerInvariant()
            if ($seenTargets.ContainsKey($targetKey)) {
                throw "Plugin '$pluginId' maps more than one source to '$destinationRelative'."
            }
            $seenTargets[$targetKey] = $true

            $parent = Split-Path -Parent $destination
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        }
    }
}

function Add-DistributionPluginTags {
    param(
        [object]$Plugin,
        [string]$DestinationRoot
    )

    $pluginId = [string]$Plugin.id
    $entrypointRelative = [string]$Plugin.entrypoint
    $entrypoint = Resolve-ContainedPath $DestinationRoot $entrypointRelative "Plugin '$pluginId' entrypoint"
    if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
        throw "Plugin '$pluginId' entrypoint was not materialized."
    }

    $extension = [IO.Path]::GetExtension($entrypoint)
    $stem = [IO.Path]::GetFileNameWithoutExtension($entrypoint)
    $sourceName = "$stem.yuzuctus-source$extension"
    $sourcePath = Join-Path (Split-Path -Parent $entrypoint) $sourceName
    if (Test-Path -LiteralPath $sourcePath) {
        throw "Plugin '$pluginId' collides with the generated entrypoint source '$sourceName'."
    }

    Move-Item -LiteralPath $entrypoint -Destination $sourcePath
    $importSpecifier = "./$([IO.Path]::GetFileNameWithoutExtension($sourceName))"
    $tagsJson = ConvertTo-Json -InputObject @(
        Get-ObjectArray $Plugin "distributionTags" | ForEach-Object { [string]$_ }
    ) -Compress
    $wrapper = @"
/*
 * Vencord, a Discord client mod
 * Copyright (c) 2026 Vendicated and contributors
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

// Generated by Yuzuctus Vencord's plugin catalog. Do not edit the materialized copy.
import { PluginTags } from "@utils/types";

import plugin from "$importSpecifier";

export * from "$importSpecifier";

const distributionTags = $tagsJson as unknown as Array<typeof PluginTags[number]>;
const knownPluginTags = PluginTags as unknown as string[];
const pluginTags = (plugin.tags ??= []);

for (const tag of distributionTags) {
    if (!knownPluginTags.includes(tag)) knownPluginTags.push(tag);
    if (!pluginTags.includes(tag)) pluginTags.push(tag);
}

export default plugin;
"@
    $normalizedWrapper = $wrapper.Replace("`r`n", "`n") + "`n"
    [IO.File]::WriteAllText(
        $entrypoint,
        $normalizedWrapper,
        (New-Object Text.UTF8Encoding($false))
    )
}

function Get-YuzuctusExternalPluginIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [Parameter(Mandatory = $true)][string]$PluginId,
        [switch]$AllowLocalGitSources
    )

    $catalogInfo = Read-YuzuctusPluginCatalog `
        -CatalogPath $CatalogPath `
        -AllowLocalGitSources:$AllowLocalGitSources
    $plugin = @($catalogInfo.Plugins | Where-Object { [string]$_.id -eq $PluginId })
    if ($plugin.Count -ne 1) {
        throw "Plugin '$PluginId' was not found exactly once in the catalog."
    }
    $plugin = $plugin[0]
    if ([string]$plugin.source.type -ne "git") {
        throw "Plugin '$PluginId' is not an external Git source."
    }

    $reviewRoot = Join-Path ([IO.Path]::GetTempPath()) (
        "yuzuctus-plugin-review-" + [Guid]::NewGuid().ToString("N")
    )
    $sourceRoot = Join-Path $reviewRoot "source"
    $stageRoot = Join-Path $reviewRoot "staged"
    $hooksRoot = Join-Path $reviewRoot "empty-hooks"
    $oldLfsSetting = $env:GIT_LFS_SKIP_SMUDGE
    $env:GIT_LFS_SKIP_SMUDGE = "1"
    try {
        New-Item -ItemType Directory -Force -Path $sourceRoot, $stageRoot, $hooksRoot | Out-Null
        $gitPrefix = @(
            "-c", "core.hooksPath=$hooksRoot",
            "-c", "core.autocrlf=false",
            "-c", "core.eol=lf",
            "-c", "submodule.recurse=false",
            "-c", "protocol.file.allow=never"
        )
        if ($AllowLocalGitSources) {
            $gitPrefix[-1] = "protocol.file.allow=always"
        }
        Invoke-GitCapture ($gitPrefix + @("-C", $sourceRoot, "init")) "Initializing plugin '$PluginId' review" | Out-Null
        Invoke-GitCapture ($gitPrefix + @(
            "-C", $sourceRoot, "remote", "add", "origin", [string]$plugin.source.repository
        )) "Configuring plugin '$PluginId' review" | Out-Null
        Invoke-GitCapture ($gitPrefix + @(
            "-C", $sourceRoot, "fetch", "--depth", "1", "--no-tags", "origin", [string]$plugin.source.commit
        )) "Fetching plugin '$PluginId' review" | Out-Null
        Invoke-GitCapture ($gitPrefix + @(
            "-C", $sourceRoot, "checkout", "--detach", "FETCH_HEAD"
        )) "Checking out plugin '$PluginId' review" | Out-Null

        $resolvedCommit = Invoke-GitCapture @(
            "-C", $sourceRoot, "rev-parse", "HEAD"
        ) "Resolving plugin '$PluginId' review commit"
        if ($resolvedCommit.ToLowerInvariant() -ne ([string]$plugin.source.commit).ToLowerInvariant()) {
            throw "Plugin '$PluginId' review resolved to unexpected commit '$resolvedCommit'."
        }
        Assert-NoGitLinks $sourceRoot $PluginId
        Copy-PluginMappings $plugin $sourceRoot $stageRoot
        Add-DistributionPluginTags $plugin $stageRoot

        $entrypoint = Resolve-ContainedPath $stageRoot ([string]$plugin.entrypoint) "Plugin '$PluginId' review entrypoint"
        $licenseFile = Resolve-ContainedPath $stageRoot ([string]$plugin.licenseFile) "Plugin '$PluginId' review license"
        if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf) `
            -or -not (Test-Path -LiteralPath $licenseFile -PathType Leaf)) {
            throw "Plugin '$PluginId' review did not materialize its entrypoint and license."
        }

        return "sha256:$(Get-YuzuctusTreeDigest $stageRoot)"
    } finally {
        $env:GIT_LFS_SKIP_SMUDGE = $oldLfsSetting
        if (Test-Path -LiteralPath $reviewRoot) {
            Remove-Item -LiteralPath $reviewRoot -Recurse -Force
        }
    }
}

function Invoke-YuzuctusPluginMaterialization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$VencordDirectory,
        [switch]$AllowLocalGitSources
    )

    $sourceRootPath = Get-NormalizedRoot $SourceRoot "Distribution source"
    $vencordRoot = Get-NormalizedRoot $VencordDirectory "Vencord"
    $userPluginsRoot = Join-Path $vencordRoot "src\userplugins"
    if (-not (Test-Path -LiteralPath $userPluginsRoot)) {
        New-Item -ItemType Directory -Path $userPluginsRoot -Force | Out-Null
    }
    $userPluginsRoot = Get-NormalizedRoot $userPluginsRoot "Vencord userplugins"

    $catalogInfo = Read-YuzuctusPluginCatalog $CatalogPath -AllowLocalGitSources:$AllowLocalGitSources
    $distributionCommit = Invoke-GitCapture @("-C", $sourceRootPath, "rev-parse", "HEAD") "Resolving distribution commit"
    if ($distributionCommit -notmatch '^[0-9a-fA-F]{40}$') {
        throw "The distribution source is not at a valid Git commit."
    }

    $metadataRoot = Join-Path $userPluginsRoot ".yuzuctus"
    if (-not (Test-Path -LiteralPath $metadataRoot)) {
        New-Item -ItemType Directory -Path $metadataRoot -Force | Out-Null
    }
    $resolvedManifestPath = Join-Path $metadataRoot "resolved-plugins.json"
    $previousIds = @()
    if (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf) {
        try {
            $previous = Get-Content -LiteralPath $resolvedManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $previousIds = @($previous.plugins | ForEach-Object { [string]$_.id })
        } catch {
            throw "The previous Yuzuctus materialization manifest is invalid."
        }
    }

    $workRoot = Join-Path $userPluginsRoot (".yuzuctus-work-" + [Guid]::NewGuid().ToString("N"))
    $stagingRoot = Join-Path $workRoot "staged"
    $sourcesRoot = Join-Path $workRoot "sources"
    $hooksRoot = Join-Path $workRoot "empty-hooks"
    $backupRoot = Join-Path $workRoot "backup"

    $oldLfsSetting = $env:GIT_LFS_SKIP_SMUDGE
    $env:GIT_LFS_SKIP_SMUDGE = "1"
    $lockPath = Join-Path $metadataRoot "materialize.lock"
    $lockStream = $null
    try {
        try {
            $lockStream = [IO.File]::Open(
                $lockPath,
                [IO.FileMode]::OpenOrCreate,
                [IO.FileAccess]::ReadWrite,
                [IO.FileShare]::None
            )
        } catch {
            throw "Another Yuzuctus plugin materialization is already running for '$vencordRoot'."
        }
        New-Item -ItemType Directory -Force -Path `
            $stagingRoot, $sourcesRoot, $hooksRoot, $backupRoot | Out-Null

        $resolvedPlugins = @()
        foreach ($plugin in @($catalogInfo.Plugins)) {
            $id = [string]$plugin.id
            $sourceType = [string]$plugin.source.type
            $pluginSourceRoot = $null
            $repository = [string]$plugin.source.repository
            $commit = $distributionCommit.ToLowerInvariant()

            if ($sourceType -eq "local") {
                $pluginSourceRoot = Resolve-ContainedPath $sourceRootPath ([string]$plugin.source.path) "Plugin '$id' local source" -AllowRoot
                if (-not (Test-Path -LiteralPath $pluginSourceRoot -PathType Container)) {
                    throw "Plugin '$id' local source was not found at '$pluginSourceRoot'."
                }
            } else {
                $pluginSourceRoot = Join-Path $sourcesRoot $id
                New-Item -ItemType Directory -Path $pluginSourceRoot -Force | Out-Null
                $gitPrefix = @(
                    "-c", "core.hooksPath=$hooksRoot",
                    "-c", "core.autocrlf=false",
                    "-c", "core.eol=lf",
                    "-c", "submodule.recurse=false",
                    "-c", "protocol.file.allow=never"
                )
                if ($AllowLocalGitSources) {
                    $gitPrefix[-1] = "protocol.file.allow=always"
                }
                Invoke-GitCapture ($gitPrefix + @("-C", $pluginSourceRoot, "init")) "Initializing plugin '$id' source" | Out-Null
                Invoke-GitCapture ($gitPrefix + @("-C", $pluginSourceRoot, "remote", "add", "origin", $repository)) "Configuring plugin '$id' source" | Out-Null
                Invoke-GitCapture ($gitPrefix + @("-C", $pluginSourceRoot, "fetch", "--depth", "1", "--no-tags", "origin", [string]$plugin.source.commit)) "Fetching plugin '$id' source" | Out-Null
                Invoke-GitCapture ($gitPrefix + @("-C", $pluginSourceRoot, "checkout", "--detach", "FETCH_HEAD")) "Checking out plugin '$id' source" | Out-Null
                $commit = (Invoke-GitCapture @("-C", $pluginSourceRoot, "rev-parse", "HEAD") "Resolving plugin '$id' commit").ToLowerInvariant()
                if ($commit -ne ([string]$plugin.source.commit).ToLowerInvariant()) {
                    throw "Plugin '$id' resolved to unexpected commit '$commit'."
                }
                Assert-NoGitLinks $pluginSourceRoot $id
            }

            $pluginStage = Join-Path $stagingRoot $id
            New-Item -ItemType Directory -Path $pluginStage -Force | Out-Null
            Copy-PluginMappings $plugin $pluginSourceRoot $pluginStage
            Add-DistributionPluginTags $plugin $pluginStage

            $entrypoint = Resolve-ContainedPath $pluginStage ([string]$plugin.entrypoint) "Plugin '$id' entrypoint"
            if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
                throw "Plugin '$id' entrypoint was not materialized."
            }
            $licenseFile = Resolve-ContainedPath $pluginStage ([string]$plugin.licenseFile) "Plugin '$id' license file"
            if (-not (Test-Path -LiteralPath $licenseFile -PathType Leaf)) {
                throw "Plugin '$id' license file was not materialized."
            }

            $sourceDigest = Get-YuzuctusTreeDigest $pluginStage
            if ($sourceType -eq "git") {
                $expected = ([string]$plugin.source.integrity).Substring("sha256:".Length).ToLowerInvariant()
                if ($sourceDigest -ne $expected) {
                    throw "Plugin '$id' integrity mismatch. Expected sha256:$expected but materialized sha256:$sourceDigest."
                }
            }

            $files = @(Get-ChildItem -LiteralPath $pluginStage -Recurse -Force -File |
                ForEach-Object { Get-RelativeFilePath $pluginStage $_.FullName } |
                Sort-Object)
            $resolvedPlugins += ,[PSCustomObject][ordered]@{
                id = $id
                displayName = [string]$plugin.displayName
                repository = $repository
                commit = $commit
                sourceType = $sourceType
                sourceDigest = $sourceDigest
                entrypoint = [string]$plugin.entrypoint
                files = $files
                settingsKey = [string]$plugin.settingsKey
                distributionTags = @(
                    Get-ObjectArray $plugin "distributionTags" | ForEach-Object { [string]$_ }
                )
                dependencies = @(Get-ObjectArray $plugin "dependencies" | ForEach-Object { [string]$_ })
                conflicts = @(Get-ObjectArray $plugin "conflicts" | ForEach-Object { [string]$_ })
                license = [string]$plugin.license
                licenseFile = [string]$plugin.licenseFile
                maintainer = [string]$plugin.maintainer
                status = [string]$plugin.status
            }
        }

        $resolvedArray = $resolvedPlugins
        $canonical = ConvertTo-Json -InputObject $resolvedArray -Depth 12 -Compress
        $pluginsDigest = Get-Sha256Text $canonical
        $newIds = @($resolvedArray | ForEach-Object { [string]$_.id })

        $managedIds = @($previousIds + $newIds |
            Where-Object { $_ -match '^[a-z][A-Za-z0-9]*$' } |
            Sort-Object -Unique)
        $deployedIds = @()
        try {
            foreach ($managedId in $managedIds) {
                $installed = Resolve-ContainedPath $userPluginsRoot $managedId "Managed plugin destination"
                if (Test-Path -LiteralPath $installed) {
                    Move-Item -LiteralPath $installed -Destination (Join-Path $backupRoot $managedId)
                }
            }

            foreach ($plugin in $resolvedArray) {
                $destination = Resolve-ContainedPath $userPluginsRoot ([string]$plugin.id) "Plugin destination"
                Move-Item -LiteralPath (Join-Path $stagingRoot ([string]$plugin.id)) -Destination $destination
                $deployedIds += [string]$plugin.id
                Write-Host "Materialized $($plugin.displayName) as $($plugin.id)"
            }

            $resolvedManifest = [ordered]@{
                schemaVersion = 1
                catalogSchemaVersion = 2
                distributionCommit = $distributionCommit.ToLowerInvariant()
                pluginsDigest = $pluginsDigest
                plugins = $resolvedArray
            }
            $temporaryManifest = "$resolvedManifestPath.tmp"
            $resolvedManifest | ConvertTo-Json -Depth 12 |
                Set-Content -LiteralPath $temporaryManifest -Encoding UTF8
            Move-Item -LiteralPath $temporaryManifest -Destination $resolvedManifestPath -Force
        } catch {
            foreach ($deployedId in $deployedIds) {
                $failedDestination = Resolve-ContainedPath $userPluginsRoot $deployedId "Failed plugin destination"
                if (Test-Path -LiteralPath $failedDestination) {
                    Remove-Item -LiteralPath $failedDestination -Recurse -Force
                }
            }
            foreach ($managedId in $managedIds) {
                $backup = Join-Path $backupRoot $managedId
                if (Test-Path -LiteralPath $backup) {
                    Move-Item `
                        -LiteralPath $backup `
                        -Destination (Resolve-ContainedPath $userPluginsRoot $managedId "Restored plugin destination")
                }
            }
            throw
        }

        return [PSCustomObject]$resolvedManifest
    } finally {
        $env:GIT_LFS_SKIP_SMUDGE = $oldLfsSetting
        if (Test-Path -LiteralPath $workRoot) {
            Remove-Item -LiteralPath $workRoot -Recurse -Force
        }
        if ($null -ne $lockStream) {
            $lockStream.Dispose()
        }
    }
}

Export-ModuleMember -Function @(
    "Get-YuzuctusExternalPluginIntegrity",
    "Get-YuzuctusTreeDigest",
    "Invoke-YuzuctusPluginMaterialization",
    "Read-YuzuctusPluginCatalog"
)
