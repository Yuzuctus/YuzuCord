Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-YuzuCordValidationTargets {
    [CmdletBinding()]
    param(
        [string[]]$Targets = @("All")
    )

    $requested = @($Targets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requested.Count -eq 0) {
        $requested = @("All")
    }

    $allowed = @("All", "Catalog", "Vencord", "Installer")
    foreach ($target in $requested) {
        if ($target -notin $allowed) {
            throw "Unknown YuzuCord validation target '$target'. Allowed targets: $($allowed -join ', ')."
        }
    }

    if ($requested -contains "All") {
        return @("Catalog", "Vencord", "Installer")
    }

    return @("Catalog", "Vencord", "Installer") |
        Where-Object { $requested -contains $_ }
}

function Resolve-YuzuCordDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$DisplayName directory was not found at '$Path'."
    }

    return [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function Get-YuzuCordPowerShellFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DistributionDirectory
    )

    $distributionRoot = Resolve-YuzuCordDirectory $DistributionDirectory "YuzuCord distribution"
    $scriptsDirectory = Join-Path $distributionRoot "scripts"

    return @(Get-ChildItem -LiteralPath $scriptsDirectory -Recurse -File |
        Where-Object { $_.Extension -in @(".ps1", ".psm1") } |
        Sort-Object FullName)
}

function Assert-YuzuCordPowerShellSyntax {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DistributionDirectory
    )

    $files = @(Get-YuzuCordPowerShellFiles -DistributionDirectory $DistributionDirectory)
    foreach ($file in $files) {
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            $file.FullName,
            [ref]$null,
            [ref]$errors
        )

        if ($errors) {
            $details = ($errors | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
            throw "PowerShell syntax validation failed for '$($file.FullName)':`n$details"
        }
    }

    Write-Host "PowerShell syntax: $($files.Count) files valid."
}

function Invoke-YuzuCordNativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Write-Host "`n==> $Label"
    Push-Location $WorkingDirectory
    try {
        $global:LASTEXITCODE = 0
        & $Command @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "$Label failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
}

function Invoke-YuzuCordScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [hashtable]$Parameters = @{},

        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Write-Host "`n==> $Label"
    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }
    try {
        $global:LASTEXITCODE = 0
        & $Path @Parameters
        if ($LASTEXITCODE -ne 0) {
            throw "$Label failed with exit code $LASTEXITCODE."
        }
    } finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Resolve-YuzuCordChromium {
    $configuredChromium = -not [string]::IsNullOrWhiteSpace($env:CHROMIUM_BIN)
    if ($configuredChromium -and (Test-Path -LiteralPath $env:CHROMIUM_BIN -PathType Leaf)) {
        return [IO.Path]::GetFullPath($env:CHROMIUM_BIN)
    }

    $candidates = @(
        "C:\Program Files\Google\Chrome\Application\chrome.exe",
        "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        $(if ($env:LOCALAPPDATA) {
            Join-Path $env:LOCALAPPDATA "Google\Chrome\Application\chrome.exe"
        }),
        "/usr/bin/google-chrome",
        "/usr/bin/chromium",
        "/usr/bin/chromium-browser"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $resolved = $candidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $resolved) {
        throw "Chrome or Chromium is required for the Discord reporter. Set CHROMIUM_BIN explicitly."
    }

    return [IO.Path]::GetFullPath($resolved)
}

function Invoke-YuzuCordValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DistributionDirectory,

        [string]$VencordDirectory,

        [string[]]$Targets = @("All"),

        [switch]$AllowLocalGitSources,

        [switch]$InstallVencordDependencies,

        [switch]$IncludeReporter,

        [switch]$PublishInstaller,

        [string]$InstallerOutputDirectory,

        [string]$InstallerReleaseTag
    )

    $distributionRoot = Resolve-YuzuCordDirectory $DistributionDirectory "YuzuCord distribution"
    $resolvedTargets = @(Resolve-YuzuCordValidationTargets -Targets $Targets)
    $scriptsRoot = Join-Path $distributionRoot "scripts"
    $catalogPath = Join-Path $distributionRoot "catalog\plugins.json"

    if (($resolvedTargets -contains "Vencord") -and [string]::IsNullOrWhiteSpace($VencordDirectory)) {
        throw "VencordDirectory is required for the Vencord validation target."
    }
    if ($PublishInstaller -and ($resolvedTargets -notcontains "Installer")) {
        throw "PublishInstaller requires the Installer validation target."
    }
    if ($PublishInstaller -and [string]::IsNullOrWhiteSpace($InstallerOutputDirectory)) {
        throw "InstallerOutputDirectory is required when PublishInstaller is enabled."
    }

    Write-Host "YuzuCord validation targets: $($resolvedTargets -join ', ')"
    Assert-YuzuCordPowerShellSyntax -DistributionDirectory $distributionRoot

    if ($resolvedTargets -contains "Catalog") {
        Invoke-YuzuCordScript `
            -Path (Join-Path $scriptsRoot "Test-PluginCatalog.ps1") `
            -Label "Plugin catalog integration tests"
        Invoke-YuzuCordScript `
            -Path (Join-Path $scriptsRoot "Test-YuzuCordValidation.ps1") `
            -Label "Validation orchestration tests"
    }

    if ($resolvedTargets -contains "Vencord") {
        $vencordRoot = Resolve-YuzuCordDirectory $VencordDirectory "Vencord"
        Invoke-YuzuCordScript `
            -Path (Join-Path $scriptsRoot "Materialize-Plugins.ps1") `
            -Parameters @{
                CatalogPath = $catalogPath
                SourceRoot = $distributionRoot
                VencordDirectory = $vencordRoot
                AllowLocalGitSources = $AllowLocalGitSources
            } `
            -Label "Materialize catalog plugins"

        if ($InstallVencordDependencies) {
            Invoke-YuzuCordNativeCommand `
                -Command "pnpm" `
                -Arguments @("install", "--frozen-lockfile") `
                -WorkingDirectory $vencordRoot `
                -Label "Install exact Vencord dependencies"
        }

        Invoke-YuzuCordNativeCommand `
            -Command "pnpm" `
            -Arguments @("exec", "tsx", "--test", "src/userplugins/**/*.test.ts") `
            -WorkingDirectory $vencordRoot `
            -Label "Catalog plugin unit tests"
        Invoke-YuzuCordNativeCommand `
            -Command "pnpm" `
            -Arguments @("eslint", "src/userplugins") `
            -WorkingDirectory $vencordRoot `
            -Label "Catalog plugin ESLint"
        Invoke-YuzuCordNativeCommand `
            -Command "pnpm" `
            -Arguments @("stylelint", "src/userplugins/**/*.css") `
            -WorkingDirectory $vencordRoot `
            -Label "Catalog plugin Stylelint"
        Invoke-YuzuCordNativeCommand `
            -Command "pnpm" `
            -Arguments @("testTsc") `
            -WorkingDirectory $vencordRoot `
            -Label "Vencord TypeScript validation"

        if ($IncludeReporter) {
            $env:CHROMIUM_BIN = Resolve-YuzuCordChromium
            Invoke-YuzuCordNativeCommand `
                -Command "pnpm" `
                -Arguments @("buildReporter") `
                -WorkingDirectory $vencordRoot `
                -Label "Build Discord reporter"
            Invoke-YuzuCordNativeCommand `
                -Command "pnpm" `
                -Arguments @(
                    "exec", "esbuild", "scripts/generateReport.ts",
                    "--platform=node", "--format=esm", "--outfile=dist/report.mjs"
                ) `
                -WorkingDirectory $vencordRoot `
                -Label "Bundle Discord reporter"
            Invoke-YuzuCordScript `
                -Path (Join-Path $scriptsRoot "Test-CatalogReporter.ps1") `
                -Parameters @{
                    CatalogPath = $catalogPath
                    ReporterPath = Join-Path $vencordRoot "dist\report.mjs"
                } `
                -WorkingDirectory $vencordRoot `
                -Label "Test patches against Discord Stable"
        }

        Invoke-YuzuCordNativeCommand `
            -Command "pnpm" `
            -Arguments @("build") `
            -WorkingDirectory $vencordRoot `
            -Label "Production Vencord build"
    }

    if ($resolvedTargets -contains "Installer") {
        $installerProject = Join-Path $distributionRoot `
            "installer\YuzuCord.Setup\YuzuCord.Setup.csproj"
        $smokeProject = Join-Path $distributionRoot `
            "installer\YuzuCord.Setup.SmokeTests\YuzuCord.Setup.SmokeTests.csproj"

        Invoke-YuzuCordNativeCommand `
            -Command "dotnet" `
            -Arguments @("build", $installerProject, "-c", "Release") `
            -WorkingDirectory $distributionRoot `
            -Label "Installer build"
        Invoke-YuzuCordNativeCommand `
            -Command "dotnet" `
            -Arguments @("run", "--project", $smokeProject, "-c", "Release") `
            -WorkingDirectory $distributionRoot `
            -Label "Installer safety smoke tests"

        if ($PublishInstaller) {
            $publishRoot = [IO.Path]::GetFullPath($InstallerOutputDirectory)
            $publishArguments = @(
                "publish", $installerProject,
                "-c", "Release",
                "-r", "win-x64",
                "--self-contained", "true",
                "-o", $publishRoot
            )
            if (-not [string]::IsNullOrWhiteSpace($InstallerReleaseTag)) {
                $publishArguments += "-p:YuzuCordReleaseTag=$InstallerReleaseTag"
                if ($InstallerReleaseTag -match '^v(?<version>.+)$') {
                    $publishArguments += "-p:Version=$($Matches.version)"
                }
            }

            Invoke-YuzuCordNativeCommand `
                -Command "dotnet" `
                -Arguments $publishArguments `
                -WorkingDirectory $distributionRoot `
                -Label "Publish self-contained YuzuCordSetup.exe"
        }
    }

    Write-Host "`nYuzuCord validation completed successfully."
}

Export-ModuleMember -Function @(
    "Assert-YuzuCordPowerShellSyntax",
    "Get-YuzuCordPowerShellFiles",
    "Invoke-YuzuCordValidation",
    "Resolve-YuzuCordValidationTargets"
)
