[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CatalogPath,

    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$VencordDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-FullPath {
    param([string]$Path)

    return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
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

function Assert-ChildPath {
    param(
        [string]$Path,
        [string]$Root,
        [string]$DisplayName,
        [switch]$AllowRoot
    )

    $resolvedPath = [IO.Path]::GetFullPath($Path).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $prefix = $resolvedRoot + [IO.Path]::DirectorySeparatorChar
    $isRoot = $resolvedPath.Equals($resolvedRoot, [StringComparison]::OrdinalIgnoreCase)
    if ((-not $AllowRoot -and $isRoot) `
        -or (-not $isRoot -and -not $resolvedPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase))) {
        throw "$DisplayName resolves outside '$resolvedRoot'."
    }
}

function Copy-CatalogPath {
    param(
        [string]$Source,
        [string]$RelativePath,
        [string]$Destination
    )

    $parent = Split-Path -Parent $RelativePath
    $destinationParent = if ([string]::IsNullOrWhiteSpace($parent)) {
        $Destination
    } else {
        Join-Path $Destination $parent
    }
    New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null

    $sourceName = Split-Path -Leaf $Source
    if (Test-Path -LiteralPath $Source -PathType Container) {
        Copy-Item -LiteralPath $Source -Destination $destinationParent -Recurse -Force
    } else {
        Copy-Item -LiteralPath $Source -Destination (Join-Path $destinationParent $sourceName) -Force
    }
}

if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
    throw "Plugin catalog was not found at '$CatalogPath'."
}
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "Plugin source root was not found at '$SourceRoot'."
}
if (-not (Test-Path -LiteralPath $VencordDirectory -PathType Container)) {
    throw "Vencord directory was not found at '$VencordDirectory'."
}

$sourceRootFull = Resolve-FullPath $SourceRoot
$vencordRootFull = Resolve-FullPath $VencordDirectory
$userPluginsRoot = Join-Path $vencordRootFull "src\userplugins"
New-Item -ItemType Directory -Path $userPluginsRoot -Force | Out-Null

$catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
if ([int]$catalog.schemaVersion -ne 1) {
    throw "Unsupported plugin catalog schema version '$($catalog.schemaVersion)'."
}

$plugins = @($catalog.plugins)
if ($plugins.Count -eq 0) {
    throw "The plugin catalog does not contain any plugin."
}

$seenIds = @{}
foreach ($plugin in $plugins) {
    $pluginId = [string]$plugin.id
    if ($pluginId -notmatch '^[a-z][A-Za-z0-9]*$') {
        throw "Plugin id '$pluginId' is not a valid Vencord userplugin directory name."
    }
    if ($seenIds.ContainsKey($pluginId)) {
        throw "Plugin id '$pluginId' appears more than once in the catalog."
    }
    $seenIds[$pluginId] = $true

    $sourcePath = [string]$plugin.sourcePath
    Assert-RelativePath $sourcePath "Plugin '$pluginId' sourcePath"
    $pluginSourceRoot = Join-Path $sourceRootFull $sourcePath
    Assert-ChildPath $pluginSourceRoot $sourceRootFull "Plugin '$pluginId' sourcePath" -AllowRoot
    if (-not (Test-Path -LiteralPath $pluginSourceRoot -PathType Container)) {
        throw "Plugin '$pluginId' sourcePath was not found at '$pluginSourceRoot'."
    }

    $destination = Join-Path $userPluginsRoot $pluginId
    Assert-ChildPath $destination $userPluginsRoot "Plugin '$pluginId' destination"
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    New-Item -ItemType Directory -Path $destination -Force | Out-Null

    $files = @($plugin.files)
    if ($files.Count -eq 0) {
        throw "Plugin '$pluginId' does not declare any source files."
    }
    foreach ($relativePath in $files) {
        $relativePath = [string]$relativePath
        Assert-RelativePath $relativePath "Plugin '$pluginId' source file"
        $source = Join-Path $pluginSourceRoot $relativePath
        Assert-ChildPath $source $pluginSourceRoot "Plugin '$pluginId' source file"
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Plugin '$pluginId' source file was not found at '$source'."
        }
        Copy-CatalogPath $source $relativePath $destination
    }

    $entrypoint = [string]$plugin.entrypoint
    Assert-RelativePath $entrypoint "Plugin '$pluginId' entrypoint"
    $resolvedEntrypoint = Join-Path $destination $entrypoint
    Assert-ChildPath $resolvedEntrypoint $destination "Plugin '$pluginId' entrypoint"
    if (-not (Test-Path -LiteralPath $resolvedEntrypoint -PathType Leaf)) {
        throw "Plugin '$pluginId' entrypoint was not materialized at '$resolvedEntrypoint'."
    }

    Write-Host "Materialized $($plugin.displayName) as $pluginId"
}
