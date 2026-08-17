[CmdletBinding()]
param(
    [ValidateSet("stable", "ptb", "canary")]
    [string]$Branch = "stable",

    [string]$InstallRoot = (Join-Path $env:LOCALAPPDATA "YuzuctusVencord"),

    [string]$VencordRepository = "https://github.com/Vendicated/Vencord.git",

    [Alias("PluginRepository")]
    [string]$DistributionRepository = "https://github.com/Yuzuctus/YuzuCord.git",

    [switch]$SkipInject,

    # Conserved for compatibility with older shortcuts. Discord is never restarted automatically.
    [switch]$SkipRestart,

    [switch]$NonInteractive,

    [switch]$ShowDetails
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:OriginalProgressPreference = $ProgressPreference
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:TranscriptStarted = $false
$script:LogPath = $null
$script:TechnicalLogPath = $null
$script:ResolvedInstallRoot = $null
$script:BootstrapDirectory = $null
$script:GitExecutable = $null
$script:NodeExecutable = $null
$script:NpmExecutable = $null
$script:OriginalPath = $env:Path
$script:IsFrench = [Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq "fr"
$script:RunTimer = [Diagnostics.Stopwatch]::StartNew()
$script:CommandCounter = 0
$script:CurrentStage = $null
$script:Completed = $false
$script:UpdateLauncherPath = $null
$script:InstalledToDiscord = $false
$script:TuiEnabled = $false
$script:TuiInitialized = $false
$script:TuiStages = @()
$script:TuiCurrentStage = 0
$script:TuiStageProgress = 0.0
$script:TuiDetail = ""
$script:TuiOutcome = "running"
$script:TuiTop = 0
$script:TuiHeight = 23
$script:TuiSpinnerIndex = 0
$script:TuiLastRender = [DateTime]::MinValue
$script:TuiOriginalCursorVisible = $true
$script:TuiOriginalForegroundColor = [ConsoleColor]::Gray
$script:TuiOriginalBackgroundColor = [ConsoleColor]::Black

. (Join-Path $PSScriptRoot "lib\YuzuCord.Tui.ps1")

function Test-Command {
    param([string]$Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Format-Command {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $formattedArguments = $Arguments | ForEach-Object {
        if ($_ -match "\s") { '"{0}"' -f $_ } else { $_ }
    }

    return "$FilePath $($formattedArguments -join ' ')"
}

function ConvertTo-PowerShellSingleQuotedLiteral {
    param([AllowNull()][string]$Value)

    return "'" + ([string]$Value).Replace("'", "''") + "'"
}

function Invoke-LiveExternalCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$CommandLog
    )

    $fileLiteral = ConvertTo-PowerShellSingleQuotedLiteral $FilePath
    $logLiteral = ConvertTo-PowerShellSingleQuotedLiteral $CommandLog
    $argumentLiterals = @($Arguments | ForEach-Object {
        ConvertTo-PowerShellSingleQuotedLiteral ([string]$_)
    })
    $argumentExpression = "@(" + ($argumentLiterals -join ", ") + ")"
    $workingDirectoryLine = if ($WorkingDirectory) {
        "Set-Location -LiteralPath $(ConvertTo-PowerShellSingleQuotedLiteral $WorkingDirectory)"
    } else {
        ""
    }

    $childScript = @"
`$ErrorActionPreference = "Continue"
try {
    $workingDirectoryLine
    `$commandArguments = $argumentExpression
    & $fileLiteral @commandArguments *> $logLiteral
    `$commandExitCode = `$LASTEXITCODE
    if (`$null -eq `$commandExitCode) {
        `$commandExitCode = 1
    }
    exit `$commandExitCode
} catch {
    (`$_ | Out-String) | Add-Content -LiteralPath $logLiteral -Encoding UTF8
    exit 1
}
"@

    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
    $processStartInfo = New-Object Diagnostics.ProcessStartInfo
    $processStartInfo.FileName = Join-Path $PSHOME "powershell.exe"
    $processStartInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
    $processStartInfo.UseShellExecute = $false
    $processStartInfo.CreateNoWindow = $true
    $processStartInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $processStartInfo

    try {
        if (-not $process.Start()) {
            throw "The background command process could not be started."
        }

        while (-not $process.HasExited) {
            Update-TuiActivity $script:TuiDetail
            [Threading.Thread]::Sleep(120)
        }
        $process.WaitForExit()
        return [int]$process.ExitCode
    } finally {
        $process.Dispose()
    }
}

function Invoke-External {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory
    )

    $formattedCommand = Format-Command $FilePath $Arguments
    Write-TechnicalLog "COMMAND: $formattedCommand"

    $script:CommandCounter++
    $commandLog = "$script:TechnicalLogPath.command-$($script:CommandCounter).tmp"

    if ($WorkingDirectory) {
        Push-Location -LiteralPath $WorkingDirectory
    }

    try {
        if ($script:TuiEnabled) {
            $exitCode = Invoke-LiveExternalCommand $FilePath $Arguments $WorkingDirectory $commandLog
        } else {
            $previousErrorPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                & $FilePath @Arguments *> $commandLog
            } finally {
                $ErrorActionPreference = $previousErrorPreference
            }
            $exitCode = $LASTEXITCODE
        }

        $output = if (Test-Path -LiteralPath $commandLog) {
            Get-Content -LiteralPath $commandLog -Raw -ErrorAction SilentlyContinue
        } else {
            ""
        }

        if (-not [string]::IsNullOrWhiteSpace($output)) {
            Add-Content -LiteralPath $script:TechnicalLogPath -Value $output -Encoding UTF8
            if ($ShowDetails) {
                Write-Host $output.TrimEnd() -ForegroundColor DarkGray
            }
        }

        if ($exitCode -ne 0) {
            Write-TechnicalLog "COMMAND FAILED with exit code $exitCode`: $formattedCommand"
            throw (Get-UiText `
                "A technical command stopped unexpectedly (code $exitCode). See the diagnostic log below." `
                "Une commande technique s'est arretee de facon inattendue (code $exitCode). Consulte le journal de diagnostic ci-dessous.")
        }
    } finally {
        if (Test-Path -LiteralPath $commandLog) {
            Remove-Item -LiteralPath $commandLog -Force
        }
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Invoke-ExternalCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory
    )

    if ($WorkingDirectory) {
        Push-Location -LiteralPath $WorkingDirectory
    }

    try {
        $formattedCommand = Format-Command $FilePath $Arguments
        Write-TechnicalLog "COMMAND (capture): $formattedCommand"
        $previousErrorPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = & $FilePath @Arguments 2>&1
        } finally {
            $ErrorActionPreference = $previousErrorPreference
        }
        $exitCode = $LASTEXITCODE
        $outputText = ($output | Out-String).Trim()
        if (-not [string]::IsNullOrWhiteSpace($outputText)) {
            Write-TechnicalLog "OUTPUT: $outputText"
        }

        if ($exitCode -ne 0) {
            Write-TechnicalLog "COMMAND FAILED with exit code $exitCode`: $formattedCommand"
            throw (Get-UiText `
                "A technical command stopped unexpectedly (code $exitCode). See the diagnostic log below." `
                "Une commande technique s'est arretee de facon inattendue (code $exitCode). Consulte le journal de diagnostic ci-dessous.")
        }

        return $outputText
    } finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
}

function Get-WindowsArchitecture {
    $architecture = if ($env:PROCESSOR_ARCHITEW6432) {
        $env:PROCESSOR_ARCHITEW6432
    } else {
        $env:PROCESSOR_ARCHITECTURE
    }

    switch -Regex ($architecture) {
        "ARM64" {
            return [PSCustomObject]@{
                GitAssetSuffix = "arm64"
                NodeArchiveSuffix = "win-arm64"
                NodeFileToken = "win-arm64-zip"
            }
        }
        "AMD64|x86_64" {
            return [PSCustomObject]@{
                GitAssetSuffix = "64-bit"
                NodeArchiveSuffix = "win-x64"
                NodeFileToken = "win-x64-zip"
            }
        }
        default {
            throw "YuzuCord Manager supports 64-bit x64 and ARM64 Windows installations."
        }
    }
}

function New-YuzuCordHttpClient {
    $client = New-Object Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromMinutes(30)
    $null = $client.DefaultRequestHeaders.TryAddWithoutValidation(
        "User-Agent",
        "YuzuCordManager/2.0"
    )
    return $client
}

function Wait-HttpTask {
    param(
        [Threading.Tasks.Task]$Task,
        [string]$Activity
    )

    while (-not $Task.IsCompleted) {
        Update-TuiActivity $Activity
        [Threading.Thread]::Sleep(120)
    }
}

function Invoke-JsonRequest {
    param(
        [string]$Uri,
        [string]$Activity
    )

    Write-TechnicalLog "JSON REQUEST: $Uri"
    $client = New-YuzuCordHttpClient

    try {
        $requestTask = $client.GetStringAsync($Uri)
        Wait-HttpTask $requestTask $Activity
        $json = $requestTask.GetAwaiter().GetResult()
        return ($json | ConvertFrom-Json)
    } finally {
        $client.Dispose()
    }
}

function Format-ByteCount {
    param([long]$Bytes)

    if ($Bytes -ge 1GB) {
        return "{0:N1} GB" -f ($Bytes / 1GB)
    }
    if ($Bytes -ge 1MB) {
        return "{0:N1} MB" -f ($Bytes / 1MB)
    }
    if ($Bytes -ge 1KB) {
        return "{0:N1} KB" -f ($Bytes / 1KB)
    }

    return "$Bytes B"
}

function Invoke-Download {
    param(
        [string]$Uri,
        [string]$Destination,
        [string]$DisplayName = "Download"
    )

    Write-TechnicalLog "DOWNLOAD: $Uri -> $Destination"
    $client = New-YuzuCordHttpClient
    $response = $null
    $networkStream = $null
    $fileStream = $null

    try {
        $responseTask = $client.GetAsync(
            [Uri]$Uri,
            [Net.Http.HttpCompletionOption]::ResponseHeadersRead
        )
        Wait-HttpTask $responseTask $DisplayName
        $response = $responseTask.GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode() | Out-Null

        $streamTask = $response.Content.ReadAsStreamAsync()
        Wait-HttpTask $streamTask $DisplayName
        $networkStream = $streamTask.GetAwaiter().GetResult()
        $fileStream = [IO.File]::Open(
            $Destination,
            [IO.FileMode]::Create,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )

        $buffer = New-Object byte[] 65536
        $downloadedBytes = [long]0
        $totalBytes = $response.Content.Headers.ContentLength

        while ($true) {
            $readTask = $networkStream.ReadAsync($buffer, 0, $buffer.Length)
            while (-not $readTask.IsCompleted) {
                Update-TuiActivity $script:TuiDetail -Progress $script:TuiStageProgress
                [Threading.Thread]::Sleep(20)
            }

            $read = $readTask.GetAwaiter().GetResult()
            if ($read -le 0) {
                break
            }

            $fileStream.Write($buffer, 0, $read)
            $downloadedBytes += $read

            if ($null -ne $totalBytes -and [long]$totalBytes -gt 0) {
                $ratio = [Math]::Min(1.0, $downloadedBytes / [double]$totalBytes)
                $detail = "{0} : {1} / {2}" -f `
                    $DisplayName,
                    (Format-ByteCount $downloadedBytes),
                    (Format-ByteCount ([long]$totalBytes))
                Update-TuiActivity $detail -Progress (0.10 + ($ratio * 0.75))
            } else {
                $detail = "{0} : {1}" -f $DisplayName, (Format-ByteCount $downloadedBytes)
                Update-TuiActivity $detail
            }
        }

        $fileStream.Flush()
        Write-TechnicalLog "DOWNLOAD COMPLETE: $downloadedBytes bytes"
    } finally {
        if ($null -ne $fileStream) {
            $fileStream.Dispose()
        }
        if ($null -ne $networkStream) {
            $networkStream.Dispose()
        }
        if ($null -ne $response) {
            $response.Dispose()
        }
        $client.Dispose()
    }
}

function Expand-ZipArchive {
    param(
        [string]$ArchivePath,
        [string]$DestinationPath
    )

    if (Test-Path -LiteralPath $DestinationPath) {
        $existingItems = @(Get-ChildItem -LiteralPath $DestinationPath -Force)
        if ($existingItems.Count -gt 0) {
            throw "The extraction folder '$DestinationPath' is not empty."
        }
    } else {
        New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
    }

    if ($script:TuiEnabled) {
        $archiveLiteral = ConvertTo-PowerShellSingleQuotedLiteral $ArchivePath
        $destinationLiteral = ConvertTo-PowerShellSingleQuotedLiteral $DestinationPath
        $extractScript = @"
`$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory($archiveLiteral, $destinationLiteral)
"@
        $encodedExtractScript = [Convert]::ToBase64String(
            [Text.Encoding]::Unicode.GetBytes($extractScript)
        )
        Invoke-External (Join-Path $PSHOME "powershell.exe") @(
            "-NoLogo",
            "-NoProfile",
            "-NonInteractive",
            "-ExecutionPolicy", "Bypass",
            "-EncodedCommand", $encodedExtractScript
        )
    } else {
        [IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $DestinationPath)
    }
}

function Assert-Sha256 {
    param(
        [string]$Path,
        [string]$ExpectedHash
    )

    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actualHash -ne $ExpectedHash.ToUpperInvariant()) {
        throw "SHA-256 verification failed for '$Path'."
    }
}

function Install-PortableGit {
    param([string]$BootstrapDirectory)

    $architecture = Get-WindowsArchitecture
    $release = Invoke-JsonRequest `
        "https://api.github.com/repos/git-for-windows/git/releases/latest" `
        (Get-UiText "Looking for a portable Git version..." "Recherche d'une version portable de Git...")

    $assetPattern = "^MinGit-.+-$([regex]::Escape($architecture.GitAssetSuffix))\.zip$"
    $asset = $release.assets |
        Where-Object { $_.name -match $assetPattern -and $_.name -notmatch "busybox" } |
        Select-Object -First 1

    if ($null -eq $asset) {
        throw "The latest Git for Windows release does not contain a compatible MinGit archive."
    }

    $expectedHash = [string]$asset.digest
    if ($expectedHash -notmatch "^sha256:([a-fA-F0-9]{64})$") {
        throw "GitHub did not provide a SHA-256 digest for '$($asset.name)'."
    }
    $expectedHash = $Matches[1]

    $archivePath = Join-Path $BootstrapDirectory $asset.name
    $gitDirectory = Join-Path $BootstrapDirectory "git"

    Write-TechnicalLog "Git was not found; using temporary MinGit $($release.tag_name)."
    Invoke-Download `
        $asset.browser_download_url `
        $archivePath `
        (Get-UiText "Downloading portable Git" "Telechargement de Git portable")
    Update-TuiActivity (Get-UiText "Checking the Git download..." "Verification du telechargement de Git...") -Progress 0.88 -Force
    Assert-Sha256 $archivePath $expectedHash
    Update-TuiActivity (Get-UiText "Extracting portable Git..." "Extraction de Git portable...") -Progress 0.90 -Force
    Expand-ZipArchive $archivePath $gitDirectory

    $gitExecutable = Join-Path $gitDirectory "cmd\git.exe"
    if (-not (Test-Path -LiteralPath $gitExecutable)) {
        throw "The MinGit archive did not contain '$gitExecutable'."
    }

    return $gitExecutable
}

function Ensure-Git {
    $existingGit = Get-Command "git.exe" -ErrorAction SilentlyContinue
    if ($null -ne $existingGit) {
        $script:GitExecutable = $existingGit.Source
        Write-TechnicalLog "Reusing the existing Git installation."
        Update-TuiActivity (Get-UiText "Using the Git installation already present." "Utilisation de Git deja present.") -Progress 0.65 -Force
    } else {
        $script:GitExecutable = Install-PortableGit $script:BootstrapDirectory
        $env:Path = "$(Split-Path -Parent $script:GitExecutable);$env:Path"
    }

    $version = Invoke-ExternalCapture $script:GitExecutable @("--version")
    Write-TechnicalLog "Git version: $version"
}

function Get-NodeMajorVersion {
    param([string]$NodeExecutable)

    if (-not $NodeExecutable -or -not (Test-Path -LiteralPath $NodeExecutable)) {
        return 0
    }

    $version = Invoke-ExternalCapture $NodeExecutable @("--version")
    if ($version -notmatch "^v(\d+)") {
        return 0
    }

    return [int]$Matches[1]
}

function Install-PortableNode {
    param(
        [int]$RequiredMajor,
        [string]$BootstrapDirectory
    )

    $architecture = Get-WindowsArchitecture
    $nodeIndex = Invoke-JsonRequest `
        "https://nodejs.org/dist/index.json" `
        (Get-UiText "Looking for a compatible Node.js version..." "Recherche d'une version compatible de Node.js...")
    $compatibleReleases = @($nodeIndex | Where-Object {
        $major = [int](($_.version -replace "^v", "").Split(".")[0])
        $major -ge $RequiredMajor -and $_.files -contains $architecture.NodeFileToken
    })

    $selectedRelease = $compatibleReleases | Where-Object { $_.lts } | Select-Object -First 1
    if ($null -eq $selectedRelease) {
        $selectedRelease = $compatibleReleases | Select-Object -First 1
    }
    if ($null -eq $selectedRelease) {
        throw "No compatible official Node.js Windows archive satisfies Vencord's Node.js requirement."
    }

    $version = [string]$selectedRelease.version
    $archiveName = "node-$version-$($architecture.NodeArchiveSuffix).zip"
    $releaseUri = "https://nodejs.org/dist/$version"
    $archivePath = Join-Path $BootstrapDirectory $archiveName
    $checksumsPath = Join-Path $BootstrapDirectory "node-SHASUMS256.txt"
    $extractDirectory = Join-Path $BootstrapDirectory "node"

    Write-TechnicalLog "A compatible Node.js was not found; using temporary Node.js $version."
    Invoke-Download `
        "$releaseUri/$archiveName" `
        $archivePath `
        (Get-UiText "Downloading portable Node.js" "Telechargement de Node.js portable")
    Invoke-Download `
        "$releaseUri/SHASUMS256.txt" `
        $checksumsPath `
        (Get-UiText "Downloading official checksums" "Telechargement des empreintes officielles")

    $checksumLine = Get-Content -LiteralPath $checksumsPath |
        Where-Object { $_ -match "^([a-fA-F0-9]{64})\s+$([regex]::Escape($archiveName))$" } |
        Select-Object -First 1
    if (-not $checksumLine -or $checksumLine -notmatch "^([a-fA-F0-9]{64})") {
        throw "The official Node.js checksum file does not contain '$archiveName'."
    }

    Update-TuiActivity (Get-UiText "Checking the Node.js download..." "Verification du telechargement de Node.js...") -Progress 0.88 -Force
    Assert-Sha256 $archivePath $Matches[1]
    Update-TuiActivity (Get-UiText "Extracting portable Node.js..." "Extraction de Node.js portable...") -Progress 0.90 -Force
    Expand-ZipArchive $archivePath $extractDirectory

    $nodeDirectory = Join-Path $extractDirectory "node-$version-$($architecture.NodeArchiveSuffix)"
    $nodeExecutable = Join-Path $nodeDirectory "node.exe"
    $npmExecutable = Join-Path $nodeDirectory "npm.cmd"

    if (-not (Test-Path -LiteralPath $nodeExecutable) -or -not (Test-Path -LiteralPath $npmExecutable)) {
        throw "The Node.js archive is incomplete."
    }

    return [PSCustomObject]@{
        NodeExecutable = $nodeExecutable
        NpmExecutable = $npmExecutable
        NodeDirectory = $nodeDirectory
    }
}

function Ensure-Node {
    param([int]$RequiredMajor)

    $existingNode = Get-Command "node.exe" -ErrorAction SilentlyContinue
    $existingNpm = Get-Command "npm.cmd" -ErrorAction SilentlyContinue
    $installedMajor = if ($null -ne $existingNode) {
        Get-NodeMajorVersion $existingNode.Source
    } else {
        0
    }

    if ($installedMajor -ge $RequiredMajor -and $null -ne $existingNpm) {
        $script:NodeExecutable = $existingNode.Source
        $script:NpmExecutable = $existingNpm.Source
        Write-TechnicalLog "Reusing the existing Node.js installation."
        Update-TuiActivity (Get-UiText "Using the Node.js installation already present." "Utilisation de Node.js deja present.") -Progress 0.45 -Force
    } else {
        $portableNode = Install-PortableNode $RequiredMajor $script:BootstrapDirectory
        $script:NodeExecutable = $portableNode.NodeExecutable
        $script:NpmExecutable = $portableNode.NpmExecutable
        $env:Path = "$($portableNode.NodeDirectory);$env:Path"
    }

    $version = Invoke-ExternalCapture $script:NodeExecutable @("--version")
    Write-TechnicalLog "Node.js version: $version"
}

function Normalize-Repository {
    param([string]$Repository)

    $candidate = $Repository.Trim()
    if (Test-Path -LiteralPath $candidate) {
        return ([IO.Path]::GetFullPath((Resolve-Path -LiteralPath $candidate).Path)).Replace("\", "/").TrimEnd("/").ToLowerInvariant()
    }

    if ($candidate -match "^git@([^:]+):(.+)$") {
        $candidate = "$($Matches[1])/$($Matches[2])"
    }

    $candidate = $candidate -replace "^https?://", ""
    $candidate = $candidate -replace "\.git$", ""
    return $candidate.Replace("\", "/").TrimEnd("/").ToLowerInvariant()
}

function Update-Repository {
    param(
        [string]$Repository,
        [string]$Destination,
        [string]$DisplayName
    )

    if (Test-Path -LiteralPath $Destination) {
        if (-not (Test-Path -LiteralPath (Join-Path $Destination ".git"))) {
            throw "$DisplayName already exists at '$Destination', but it is not a Git repository. Rename that folder and run the manager again."
        }

        $actualRemote = Invoke-ExternalCapture $script:GitExecutable @("-C", $Destination, "remote", "get-url", "origin")
        $normalizedActualRemote = Normalize-Repository $actualRemote
        $normalizedExpectedRemote = Normalize-Repository $Repository
        $legacyDistributionRemote = Normalize-Repository "https://github.com/Yuzuctus/RandomFavorites.git"
        $yuzuCordRemote = Normalize-Repository "https://github.com/Yuzuctus/YuzuCord.git"
        $isYuzuCordRename = $normalizedActualRemote -eq $legacyDistributionRemote `
            -and $normalizedExpectedRemote -eq $yuzuCordRemote

        if ($isYuzuCordRename) {
            Write-TechnicalLog "Migrating the distribution remote from RandomFavorites to YuzuCord."
            Invoke-External $script:GitExecutable @(
                "-C", $Destination,
                "remote", "set-url", "origin", $Repository
            )
        } elseif ($normalizedActualRemote -ne $normalizedExpectedRemote) {
            throw "$DisplayName uses an unexpected Git remote: '$actualRemote'. Expected '$Repository'."
        }

        $trackedChanges = Invoke-ExternalCapture $script:GitExecutable @(
            "-C", $Destination,
            "status",
            "--porcelain",
            "--untracked-files=no"
        )

        if (-not [string]::IsNullOrWhiteSpace($trackedChanges)) {
            throw "$DisplayName contains local tracked changes. They were not overwritten. Commit or revert them, then run the manager again."
        }

        Write-TechnicalLog "Updating $DisplayName."
        Update-TuiActivity `
            (Get-UiText "Updating $DisplayName..." "Mise a jour de $DisplayName...") `
            -Progress 0.18 `
            -Force
        Invoke-External $script:GitExecutable @("-C", $Destination, "pull", "--ff-only")
        return
    }

    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-TechnicalLog "Installing $DisplayName."
    Update-TuiActivity `
        (Get-UiText "Downloading $DisplayName..." "Telechargement de $DisplayName...") `
        -Progress 0.12 `
        -Force
    Invoke-External $script:GitExecutable @("clone", $Repository, $Destination)
}

function Get-VencordRequirements {
    param([string]$VencordDirectory)

    $packageJsonPath = Join-Path $VencordDirectory "package.json"
    if (-not (Test-Path -LiteralPath $packageJsonPath)) {
        throw "Vencord package.json was not found at '$packageJsonPath'."
    }

    $packageJson = Get-Content -LiteralPath $packageJsonPath -Raw | ConvertFrom-Json
    $nodeRange = [string]$packageJson.engines.node
    $packageManager = [string]$packageJson.packageManager

    if ($nodeRange -notmatch "(\d+)") {
        throw "Could not determine the Node.js version required by Vencord."
    }
    $nodeMajor = [int]$Matches[1]

    if ($packageManager -notmatch "^pnpm@(.+)$") {
        throw "Could not determine the pnpm version required by Vencord."
    }
    $pnpmVersion = $Matches[1]

    return [PSCustomObject]@{
        NodeMajor = $nodeMajor
        PnpmVersion = $pnpmVersion
    }
}

function Resolve-Pnpm {
    param(
        [string]$Version,
        [string]$ToolsDirectory
    )

    $existingPnpm = Get-Command "pnpm.cmd" -ErrorAction SilentlyContinue
    if ($null -eq $existingPnpm) {
        $existingPnpm = Get-Command "pnpm" -ErrorAction SilentlyContinue
    }

    if ($null -ne $existingPnpm) {
        $existingVersion = Invoke-ExternalCapture $existingPnpm.Source @("--version")
        if ($existingVersion -eq $Version) {
            Write-TechnicalLog "Reusing pnpm $existingVersion."
            return $existingPnpm.Source
        }
    }

    if (-not (Test-Path -LiteralPath $ToolsDirectory)) {
        New-Item -ItemType Directory -Path $ToolsDirectory -Force | Out-Null
    }

    Write-TechnicalLog "Installing the Vencord-required pnpm $Version temporarily."
    Update-TuiActivity `
        (Get-UiText "Preparing pnpm $Version..." "Preparation de pnpm $Version...") `
        -Progress 0.55 `
        -Force
    Invoke-External $script:NpmExecutable @(
        "install",
        "--prefix", $ToolsDirectory,
        "--no-save",
        "--no-package-lock",
        "pnpm@$Version"
    )

    $localPnpm = Join-Path $ToolsDirectory "node_modules\.bin\pnpm.cmd"
    if (-not (Test-Path -LiteralPath $localPnpm)) {
        throw "The local pnpm installation did not create '$localPnpm'."
    }

    return $localPnpm
}

function Get-DiscordProcessName {
    param([string]$DiscordBranch)

    switch ($DiscordBranch) {
        "stable" { return "Discord" }
        "ptb" { return "DiscordPTB" }
        "canary" { return "DiscordCanary" }
    }
}

function Get-DiscordRootName {
    param([string]$DiscordBranch)

    switch ($DiscordBranch) {
        "stable" { return "Discord" }
        "ptb" { return "DiscordPTB" }
        "canary" { return "DiscordCanary" }
    }
}

function Stop-Discord {
    param([string]$DiscordBranch)

    $processName = Get-DiscordProcessName $DiscordBranch
    $processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)

    if ($processes.Count -eq 0) {
        return
    }

    Write-TechnicalLog "Closing $processName so the Vencord installer can patch it."
    $processes | Stop-Process -Force
}

function Test-VencordPatch {
    param(
        [string]$DiscordBranch,
        [string]$VencordDirectory
    )

    $discordRoot = Join-Path $env:LOCALAPPDATA (Get-DiscordRootName $DiscordBranch)
    if (-not (Test-Path -LiteralPath $discordRoot)) {
        throw "Discord $DiscordBranch was not found at '$discordRoot'."
    }

    $appAsar = Get-ChildItem -LiteralPath $discordRoot -Directory -Filter "app-*" |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Join-Path $_.FullName "resources\app.asar" } |
        Where-Object { Test-Path -LiteralPath $_ } |
        Select-Object -First 1

    if (-not $appAsar) {
        throw "Could not find Discord's app.asar for branch '$DiscordBranch'."
    }

    $patchText = Get-Content -LiteralPath $appAsar -Raw
    $expectedPatcher = (Join-Path $VencordDirectory "dist\patcher.js").Replace("\", "\\")

    if (-not $patchText.Contains($expectedPatcher)) {
        throw "Discord was not patched to use the expected Vencord build '$expectedPatcher'."
    }
}

function Write-UpdateLauncher {
    param(
        [string]$RootDirectory,
        [string]$DistributionDirectory
    )

    $sourceManager = Join-Path $DistributionDirectory "scripts\YuzuCordManager.ps1"
    if (-not (Test-Path -LiteralPath $sourceManager)) {
        return
    }

    $managedDirectory = Join-Path $RootDirectory "manager"
    if (-not (Test-Path -LiteralPath $managedDirectory)) {
        New-Item -ItemType Directory -Path $managedDirectory -Force | Out-Null
    }

    $managedScript = Join-Path $managedDirectory "YuzuCordManager.ps1"
    Copy-Item -LiteralPath $sourceManager -Destination $managedScript -Force

    $sourceLibrary = Join-Path $DistributionDirectory "scripts\lib"
    if (-not (Test-Path -LiteralPath $sourceLibrary -PathType Container)) {
        throw "The YuzuCord manager support library was not found at '$sourceLibrary'."
    }
    $managedLibrary = Join-Path $managedDirectory "lib"
    if (-not (Test-Path -LiteralPath $managedLibrary -PathType Container)) {
        New-Item -ItemType Directory -Path $managedLibrary -Force | Out-Null
    }
    Copy-Item -Path (Join-Path $sourceLibrary "*") -Destination $managedLibrary -Recurse -Force

    $launcherPath = Join-Path $RootDirectory "Update YuzuCord.cmd"

    $lines = @(
        "@echo off",
        "setlocal",
        "title YuzuCord - Mise a jour",
        "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0manager\YuzuCordManager.ps1`" -InstallRoot `"%~dp0.`" %*",
        "set `"EXIT_CODE=%ERRORLEVEL%`"",
        "if not defined YUZUCORD_NO_PAUSE pause",
        "exit /b %EXIT_CODE%"
    )

    [IO.File]::WriteAllLines($launcherPath, $lines, [Text.Encoding]::ASCII)

    foreach ($legacyPath in @(
        (Join-Path $RootDirectory "Update Yuzuctus Vencord.cmd"),
        (Join-Path $managedDirectory "YuzuctusVencordManager.ps1")
    )) {
        if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
            Remove-Item -LiteralPath $legacyPath -Force
        }
    }
}

function Write-State {
    param(
        [string]$RootDirectory,
        [string]$VencordDirectory,
        [string]$DistributionDirectory,
        [string]$DiscordBranch
    )

    $resolvedManifestPath = Join-Path $VencordDirectory "src\userplugins\.yuzuctus\resolved-plugins.json"
    if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
        throw "The resolved plugin manifest was not found at '$resolvedManifestPath'."
    }
    $resolvedPlugins = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
    if ([int]$resolvedPlugins.schemaVersion -ne 1 `
        -or [string]$resolvedPlugins.pluginsDigest -notmatch '^[0-9a-fA-F]{64}$') {
        throw "The resolved plugin manifest is invalid."
    }
    $pluginIds = @($resolvedPlugins.plugins | ForEach-Object { [string]$_.id })
    $state = [ordered]@{
        productId = "YuzuctusVencord"
        lastSuccessfulRun = [DateTime]::UtcNow.ToString("o")
        branch = $DiscordBranch
        vencordDirectory = $VencordDirectory
        distributionDirectory = $DistributionDirectory
        pluginIds = $pluginIds
        vencordCommit = Invoke-ExternalCapture $script:GitExecutable @("-C", $VencordDirectory, "rev-parse", "HEAD")
        distributionCommit = [string]$resolvedPlugins.distributionCommit
        pluginsDigest = ([string]$resolvedPlugins.pluginsDigest).ToLowerInvariant()
    }

    $statePath = Join-Path $RootDirectory "manager-state.json"
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Remove-BootstrapTools {
    if (-not $script:BootstrapDirectory -or -not (Test-Path -LiteralPath $script:BootstrapDirectory)) {
        return
    }

    if (-not $script:ResolvedInstallRoot) {
        throw "Refusing to clean temporary tools because the install root is unknown."
    }

    $resolvedRoot = [IO.Path]::GetFullPath($script:ResolvedInstallRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $resolvedBootstrap = [IO.Path]::GetFullPath($script:BootstrapDirectory).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
    $expectedBootstrap = Join-Path $resolvedRoot ".bootstrap"

    if (-not $resolvedBootstrap.Equals($expectedBootstrap, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove unexpected temporary directory '$resolvedBootstrap'."
    }

    Write-TechnicalLog "Removing temporary Git, Node.js and pnpm tools."
    Remove-Item -LiteralPath $resolvedBootstrap -Recurse -Force
}

function Main {
    $script:TuiStages = @(New-TuiStages)
    Write-Banner

    $resolvedRoot = [IO.Path]::GetFullPath($InstallRoot)
    $vencordDirectory = Join-Path $resolvedRoot "Vencord"
    $distributionDirectory = Join-Path $resolvedRoot "Distribution"
    $catalogPath = Join-Path $distributionDirectory "catalog\plugins.json"
    $bootstrapDirectory = Join-Path $resolvedRoot ".bootstrap"
    $logsDirectory = Join-Path $resolvedRoot "logs"
    $script:ResolvedInstallRoot = $resolvedRoot
    $script:BootstrapDirectory = $bootstrapDirectory

    if (-not (Test-Path -LiteralPath $resolvedRoot)) {
        New-Item -ItemType Directory -Path $resolvedRoot -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $logsDirectory)) {
        New-Item -ItemType Directory -Path $logsDirectory -Force | Out-Null
    }
    if (-not (Test-Path -LiteralPath $bootstrapDirectory)) {
        New-Item -ItemType Directory -Path $bootstrapDirectory -Force | Out-Null
    }

    $runId = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
    $script:LogPath = Join-Path $logsDirectory "manager-$runId.log"
    $script:TechnicalLogPath = Join-Path $logsDirectory "details-$runId.log"
    New-Item -ItemType File -Path $script:TechnicalLogPath -Force | Out-Null
    try {
        Start-Transcript -LiteralPath $script:LogPath -Force | Out-Null
        $script:TranscriptStarted = $true
    } catch {
        Write-TechnicalLog "The UI transcript could not be started: $($_.Exception.Message)"
    }

    Write-TechnicalLog "Install root: $resolvedRoot"
    Write-TechnicalLog "Discord branch: $Branch"
    Write-TechnicalLog "Vencord repository: $VencordRepository"
    Write-TechnicalLog "Distribution repository: $DistributionRepository"

    Write-Host "  $(Get-UiText "Installation folder:" "Dossier d'installation :") $resolvedRoot" -ForegroundColor DarkGray
    Write-Host "  $(Get-UiText "Discord version:" "Version de Discord :") $Branch" -ForegroundColor DarkGray
    Write-Host ""

    if (-not $NonInteractive) {
        Write-Host "  $(Get-UiText "Discord stays open while files are prepared." "Discord reste ouvert pendant la preparation des fichiers.")" -ForegroundColor White
        Write-Host "  $(Get-UiText "It will close only during the final installation and stay closed." "Il se fermera seulement pendant l'installation finale et restera ferme.")" -ForegroundColor White
        Write-Host ""
        $answer = Read-Host "  $(Get-UiText "Continue? [Y/n]" "Continuer ? [O/n]")"
        if ($answer -and $answer -notmatch "^(y|yes|o|oui)$") {
            Write-Host "  $(Get-UiText "Installation cancelled. Nothing was changed." "Installation annulee. Rien n'a ete modifie.")" -ForegroundColor Yellow
            Write-TechnicalLog "Installation cancelled by the user."
            return
        }
    }

    Initialize-LiveTui

    $stageTimer = Write-Step 1 7 `
        (Get-UiText "Preparing the installer" "Preparation de l'installateur") `
        (Get-UiText "Checking the tools needed for a safe installation." "Verification des outils necessaires a une installation sure.")
    Ensure-Git
    Complete-Step $stageTimer

    $stageTimer = Write-Step 2 7 `
        (Get-UiText "Preparing Vencord" "Preparation de Vencord") `
        (Get-UiText "Downloading or updating the official Vencord source code." "Telechargement ou mise a jour du code officiel de Vencord.")
    Update-Repository $VencordRepository $vencordDirectory "Vencord"
    $requirements = Get-VencordRequirements $vencordDirectory
    Complete-Step $stageTimer

    $stageTimer = Write-Step 3 7 `
        (Get-UiText "Preparing build tools" "Preparation des outils de compilation") `
        (Get-UiText "Reusing compatible tools or preparing temporary portable copies." "Reutilisation des outils compatibles ou preparation de copies portables temporaires.")
    Ensure-Node $requirements.NodeMajor
    $pnpmToolsDirectory = Join-Path $bootstrapDirectory "pnpm"
    $pnpm = Resolve-Pnpm $requirements.PnpmVersion $pnpmToolsDirectory
    Complete-Step $stageTimer

    $stageTimer = Write-Step 4 7 `
        (Get-UiText "Updating YuzuCord" "Mise a jour de YuzuCord") `
        (Get-UiText "Fetching the newest public distribution catalog." "Recuperation du catalogue public de la distribution.")
    Update-Repository $DistributionRepository $distributionDirectory "YuzuCord distribution"
    $catalogPath = Join-Path $distributionDirectory "catalog\plugins.json"
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        throw "The YuzuCord distribution does not contain '$catalogPath'."
    }
    Update-TuiActivity `
        (Get-UiText "Materializing catalog plugins..." "Preparation des plugins du catalogue...") `
        -Progress 0.72 `
        -Force
    Invoke-External (Join-Path $PSHOME "powershell.exe") @(
        "-NoLogo",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-File", (Join-Path $distributionDirectory "scripts\Materialize-Plugins.ps1"),
        "-CatalogPath", $catalogPath,
        "-SourceRoot", $distributionDirectory,
        "-VencordDirectory", $vencordDirectory
    )
    Complete-Step $stageTimer

    $stageTimer = Write-Step 5 7 `
        (Get-UiText "Preparing dependencies" "Preparation des dependances") `
        (Get-UiText "Checking the exact files required to build Vencord." "Verification des fichiers exacts necessaires a la compilation de Vencord.")
    Update-TuiActivity `
        (Get-UiText "Installing the exact Vencord dependencies..." "Installation des dependances exactes de Vencord...") `
        -Progress 0.08 `
        -Force
    Invoke-External $pnpm @("install", "--frozen-lockfile") $vencordDirectory
    Complete-Step $stageTimer

    $stageTimer = Write-Step 6 7 `
        (Get-UiText "Building the custom Discord mod" "Compilation du mod Discord personnalise") `
        (Get-UiText "Creating Vencord with catalog plugins included. This can take a moment." "Creation de Vencord avec les plugins du catalogue. Cette etape peut prendre un moment.")
    Update-TuiActivity `
        (Get-UiText "Compiling Vencord with catalog plugins..." "Compilation de Vencord avec les plugins du catalogue...") `
        -Progress 0.05 `
        -Force
    Invoke-External $pnpm @("build") $vencordDirectory

    $patcherPath = Join-Path $vencordDirectory "dist\patcher.js"
    $rendererPath = Join-Path $vencordDirectory "dist\renderer.js"
    if (-not (Test-Path -LiteralPath $patcherPath) -or -not (Test-Path -LiteralPath $rendererPath)) {
        throw "The build command completed but the expected Vencord files are missing."
    }
    Complete-Step $stageTimer

    $stageTimer = Write-Step 7 7 `
        (Get-UiText "Installing into Discord" "Installation dans Discord") `
        (Get-UiText "Discord closes only now and stays closed." "Discord se ferme seulement maintenant et reste ferme.")
    if ($SkipInject) {
        if ($script:TuiEnabled) {
            Update-TuiActivity `
                (Get-UiText "Discord modification skipped by command-line option." "Modification de Discord ignoree par option de ligne de commande.") `
                -Progress 0.75 `
                -Force
        } else {
            Write-Host "  $(Get-UiText "Discord modification skipped by command-line option." "Modification de Discord ignoree par option de ligne de commande.")" -ForegroundColor Yellow
        }
        Write-TechnicalLog "Discord injection skipped by command-line option."
    } else {
        Update-TuiActivity (Get-UiText "Closing Discord..." "Fermeture de Discord...") -Progress 0.12 -Force
        Stop-Discord $Branch
        Update-TuiActivity (Get-UiText "Installing Vencord into Discord..." "Installation de Vencord dans Discord...") -Progress 0.25 -Force
        Invoke-External $script:NodeExecutable @(
            "scripts\runInstaller.mjs",
            "--",
            "--install",
            "-branch", $Branch
        ) $vencordDirectory
        Test-VencordPatch $Branch $vencordDirectory

        Write-TechnicalLog "Discord remains closed after installation by design."
        Update-TuiActivity `
            (Get-UiText "Installation complete. Restart Discord yourself when ready." "Installation terminee. Relance Discord toi-meme quand tu es pret.") `
            -Progress 0.88 `
            -Force
    }

    $updateLauncher = Join-Path $resolvedRoot "Update YuzuCord.cmd"
    Update-TuiActivity (Get-UiText "Saving the update shortcut..." "Enregistrement du raccourci de mise a jour...") -Progress 0.92 -Force
    Write-UpdateLauncher $resolvedRoot $distributionDirectory
    Write-State $resolvedRoot $vencordDirectory $distributionDirectory $Branch
    Complete-Step $stageTimer

    $script:UpdateLauncherPath = $updateLauncher
    $script:InstalledToDiscord = -not $SkipInject
    $script:Completed = $true
}

$exitCode = 0
try {
    Main
} catch {
    $exitCode = 1
    Write-TechnicalLog "ERROR: $($_.Exception.ToString())"
    if ($script:TuiEnabled) {
        Set-LiveTuiFailure $_.Exception.Message
    } else {
        Write-Host ""
        Write-Host "  +----------------------------------------------------------+" -ForegroundColor Red
        Write-Host "  |  $(Get-UiText "INSTALLATION FAILED" "ECHEC DE L'INSTALLATION")".PadRight(59).Substring(0, 59) -NoNewline -ForegroundColor Red
        Write-Host "|" -ForegroundColor Red
        Write-Host "  +----------------------------------------------------------+" -ForegroundColor Red
        if ($script:CurrentStage) {
            Write-Host "  $(Get-UiText "Stage:" "Etape :") $script:CurrentStage" -ForegroundColor Yellow
        }
        Write-Host "  $(Get-UiText "Reason:" "Raison :") $($_.Exception.Message)" -ForegroundColor White
        Write-Host ""
        Write-Host "  $(Get-UiText "Discord was not closed unless the final installation stage had started." "Discord n'a pas ete ferme sauf si l'etape finale d'installation avait commence.")" -ForegroundColor DarkGray
        Write-Host "  $(Get-UiText "Diagnostic log:" "Journal de diagnostic :") $script:TechnicalLogPath" -ForegroundColor Yellow
    }
} finally {
    try {
        if ($script:TuiEnabled -and $script:Completed) {
            Update-TuiActivity (Get-UiText "Removing temporary build tools..." "Nettoyage des outils temporaires...") -Force
        }
        Remove-BootstrapTools
    } catch {
        $exitCode = 1
        Write-TechnicalLog "ERROR while removing temporary tools: $($_.Exception.ToString())"
        if ($script:TuiEnabled) {
            Set-LiveTuiFailure ((Get-UiText "Temporary-tool cleanup failed: " "Le nettoyage des outils temporaires a echoue : ") + $_.Exception.Message)
        } else {
            Write-Host "  $(Get-UiText "Temporary-tool cleanup failed:" "Le nettoyage des outils temporaires a echoue :") $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    $env:Path = $script:OriginalPath
    $ProgressPreference = $script:OriginalProgressPreference

    if ($script:TranscriptStarted) {
        Stop-Transcript | Out-Null
    }
}

if ($exitCode -eq 0 -and $script:Completed) {
    Write-FinalSuccess $script:UpdateLauncherPath $script:InstalledToDiscord
} elseif ($script:TuiInitialized) {
    Stop-LiveTui
}

exit $exitCode
