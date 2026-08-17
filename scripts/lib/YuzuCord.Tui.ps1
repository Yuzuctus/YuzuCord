# YuzuCord source-build manager: console UI and progress rendering.

function Get-UiText {
    param(
        [string]$English,
        [string]$French
    )

    if ($script:IsFrench) {
        return $French
    }

    return $English
}
function Format-Elapsed {
    param([TimeSpan]$Elapsed)

    if ($Elapsed.TotalHours -ge 1) {
        return "{0:00}:{1:00}:{2:00}" -f [int]$Elapsed.TotalHours, $Elapsed.Minutes, $Elapsed.Seconds
    }

    return "{0:00}:{1:00}" -f [int]$Elapsed.TotalMinutes, $Elapsed.Seconds
}

function Write-TechnicalLog {
    param([string]$Message)

    if (-not $script:TechnicalLogPath) {
        return
    }

    $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -LiteralPath $script:TechnicalLogPath -Value "[$timestamp] $Message" -Encoding UTF8
}

function New-TuiStages {
    return @(
        [PSCustomObject]@{
            Number = 1
            Title = Get-UiText "Preparing the installer" "Preparation de l'installateur"
            Explanation = Get-UiText "Checking the tools needed for a safe installation." "Verification des outils necessaires a une installation sure."
            Weight = 10
            State = "Pending"
            StartedAt = $null
            Timer = $null
            Elapsed = [TimeSpan]::Zero
        },
        [PSCustomObject]@{
            Number = 2
            Title = Get-UiText "Preparing Vencord" "Preparation de Vencord"
            Explanation = Get-UiText "Downloading or updating the official Vencord source code." "Telechargement ou mise a jour du code officiel de Vencord."
            Weight = 15
            State = "Pending"
            StartedAt = $null
            Timer = $null
            Elapsed = [TimeSpan]::Zero
        },
        [PSCustomObject]@{
            Number = 3
            Title = Get-UiText "Preparing build tools" "Preparation des outils de compilation"
            Explanation = Get-UiText "Reusing compatible tools or preparing temporary portable copies." "Reutilisation des outils compatibles ou preparation de copies portables temporaires."
            Weight = 15
            State = "Pending"
            StartedAt = $null
            Timer = $null
            Elapsed = [TimeSpan]::Zero
        },
        [PSCustomObject]@{
            Number = 4
            Title = Get-UiText "Updating YuzuCord" "Mise a jour de YuzuCord"
            Explanation = Get-UiText "Fetching the newest public distribution catalog." "Recuperation du catalogue public de la distribution."
            Weight = 10
            State = "Pending"
            StartedAt = $null
            Timer = $null
            Elapsed = [TimeSpan]::Zero
        },
        [PSCustomObject]@{
            Number = 5
            Title = Get-UiText "Preparing dependencies" "Preparation des dependances"
            Explanation = Get-UiText "Checking the exact files required to build Vencord." "Verification des fichiers exacts necessaires a la compilation de Vencord."
            Weight = 20
            State = "Pending"
            StartedAt = $null
            Timer = $null
            Elapsed = [TimeSpan]::Zero
        },
        [PSCustomObject]@{
            Number = 6
            Title = Get-UiText "Building the custom Discord mod" "Compilation du mod Discord personnalise"
            Explanation = Get-UiText "Creating Vencord with the catalog plugins included." "Creation de Vencord avec les plugins du catalogue."
            Weight = 20
            State = "Pending"
            StartedAt = $null
            Timer = $null
            Elapsed = [TimeSpan]::Zero
        },
        [PSCustomObject]@{
            Number = 7
            Title = Get-UiText "Installing into Discord" "Installation dans Discord"
            Explanation = Get-UiText "Discord closes only now and stays closed." "Discord se ferme seulement maintenant et reste ferme."
            Weight = 10
            State = "Pending"
            StartedAt = $null
            Timer = $null
            Elapsed = [TimeSpan]::Zero
        }
    )
}

function Limit-TuiText {
    param(
        [AllowNull()]
        [string]$Text,
        [int]$Width
    )

    if ($Width -le 0) {
        return ""
    }

    $singleLine = ([string]$Text) -replace "[\r\n]+", " "
    if ($singleLine.Length -le $Width) {
        return $singleLine
    }
    if ($Width -le 3) {
        return $singleLine.Substring(0, $Width)
    }

    return $singleLine.Substring(0, $Width - 3) + "..."
}

function Get-TuiFriendlyPath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    $resolvedLocalAppData = [IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd("\")
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    if ($resolvedPath.StartsWith($resolvedLocalAppData + "\", [StringComparison]::OrdinalIgnoreCase)) {
        return "%LOCALAPPDATA%" + $resolvedPath.Substring($resolvedLocalAppData.Length)
    }

    return $resolvedPath
}

function Format-TuiColumns {
    param(
        [string]$Left,
        [string]$Right,
        [int]$Width
    )

    if ($Width -le 0) {
        return ""
    }

    $safeRight = Limit-TuiText $Right $Width
    $leftWidth = $Width - $safeRight.Length
    if ($safeRight.Length -gt 0) {
        $leftWidth--
    }

    $safeLeft = Limit-TuiText $Left ([Math]::Max(0, $leftWidth))
    $spacing = [Math]::Max(0, $Width - $safeLeft.Length - $safeRight.Length)
    return $safeLeft + (" " * $spacing) + $safeRight
}

function Format-TuiBoxLine {
    param(
        [string]$Text,
        [int]$Width
    )

    $innerWidth = [Math]::Max(0, $Width - 4)
    $content = (Limit-TuiText $Text $innerWidth).PadRight($innerWidth)
    return "| $content |"
}

function Get-TuiWidth {
    $availableWidth = [Math]::Max(1, [Console]::BufferWidth - 1)
    return [Math]::Min(96, $availableWidth)
}

function Write-TuiLine {
    param(
        [int]$Row,
        [string]$Text,
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    $bufferWidth = [Math]::Max(1, [Console]::BufferWidth - 1)
    $line = (Limit-TuiText $Text $bufferWidth).PadRight($bufferWidth)

    [Console]::SetCursorPosition(0, $script:TuiTop + $Row)
    [Console]::ForegroundColor = $Color
    [Console]::BackgroundColor = [ConsoleColor]::Black
    [Console]::Write($line)
}

function Get-TuiOverallProgress {
    $progress = 0.0

    foreach ($stage in $script:TuiStages) {
        if ($stage.State -eq "Completed") {
            $progress += [double]$stage.Weight
        } elseif ($stage.State -eq "Active" -or $stage.State -eq "Failed") {
            $progress += [double]$stage.Weight * $script:TuiStageProgress
        }
    }

    return [Math]::Max(0.0, [Math]::Min(100.0, $progress))
}

function Render-LiveTui {
    param([switch]$Force)

    if (-not $script:TuiEnabled -or -not $script:TuiInitialized) {
        return
    }

    $now = [DateTime]::Now
    if (-not $Force -and ($now - $script:TuiLastRender).TotalMilliseconds -lt 180) {
        return
    }
    $script:TuiLastRender = $now

    try {
        $width = Get-TuiWidth
        $innerWidth = [Math]::Max(1, $width - 4)
        $border = "+" + ("-" * [Math]::Max(0, $width - 2)) + "+"
        $outcomeLabel = switch ($script:TuiOutcome) {
            "success" { Get-UiText "COMPLETED" "TERMINEE" }
            "error" { Get-UiText "FAILED" "ECHEC" }
            default { Get-UiText "INSTALLATION" "INSTALLATION" }
        }
        $borderColor = switch ($script:TuiOutcome) {
            "success" { [ConsoleColor]::Green }
            "error" { [ConsoleColor]::Red }
            default { [ConsoleColor]::DarkCyan }
        }

        $header = Format-TuiColumns "YUZUCORD" $outcomeLabel $innerWidth
        $subtitle = Format-TuiColumns `
            (Get-UiText "Vencord installation and update" "Installation et mise a jour de Vencord") `
            ("Discord " + $Branch) `
            $innerWidth

        Write-TuiLine 0 $border $borderColor
        Write-TuiLine -Row 1 -Text (Format-TuiBoxLine $header $width) -Color Cyan
        Write-TuiLine -Row 2 -Text (Format-TuiBoxLine $subtitle $width) -Color DarkGray
        Write-TuiLine 3 $border $borderColor
        Write-TuiLine 4 ""
        Write-TuiLine -Row 5 -Text ("  " + (Get-UiText "OVERALL PROGRESS" "PROGRESSION GLOBALE")) -Color White

        $overallProgress = Get-TuiOverallProgress
        $overallPercent = [int][Math]::Floor($overallProgress)
        $barWidth = [Math]::Max(16, [Math]::Min(52, $width - 27))
        $filled = [Math]::Min($barWidth, [int][Math]::Floor(($overallProgress / 100.0) * $barWidth))
        $bar = ("#" * $filled) + ("-" * ($barWidth - $filled))
        $totalElapsed = Format-Elapsed $script:RunTimer.Elapsed
        $progressLine = "  [{0}] {1,3}%   {2} {3}" -f `
            $bar,
            $overallPercent,
            (Get-UiText "Total" "Total"),
            $totalElapsed
        Write-TuiLine -Row 6 -Text $progressLine -Color Cyan
        Write-TuiLine 7 ""

        for ($index = 0; $index -lt $script:TuiStages.Count; $index++) {
            $stage = $script:TuiStages[$index]
            $elapsed = $stage.Elapsed
            if ($stage.State -eq "Active" -and $null -ne $stage.Timer) {
                $elapsed = $stage.Timer.Elapsed
            }

            $icon = "[ ]"
            $right = ""
            $color = [ConsoleColor]::DarkGray

            switch ($stage.State) {
                "Active" {
                    $icon = "[>]"
                    $right = "{0,3}%  {1}" -f ([int][Math]::Floor($script:TuiStageProgress * 100)), (Format-Elapsed $elapsed)
                    $color = [ConsoleColor]::White
                }
                "Completed" {
                    $icon = "[OK]"
                    $right = Format-Elapsed $elapsed
                    $color = [ConsoleColor]::Green
                }
                "Failed" {
                    $icon = "[!!]"
                    $right = Format-Elapsed $elapsed
                    $color = [ConsoleColor]::Red
                }
            }

            $left = "  $icon $($stage.Number). $($stage.Title)"
            $stageLine = Format-TuiColumns $left $right $width
            Write-TuiLine (8 + $index) $stageLine $color
        }

        Write-TuiLine 15 ""
        $activityHeading = switch ($script:TuiOutcome) {
            "success" { Get-UiText "RESULT" "RESULTAT" }
            "error" { Get-UiText "ERROR" "ERREUR" }
            default { Get-UiText "CURRENT ACTIVITY" "ACTIVITE EN COURS" }
        }
        Write-TuiLine -Row 16 -Text ("  " + $activityHeading) -Color White
        $detail = if ([string]::IsNullOrWhiteSpace($script:TuiDetail)) {
            Get-UiText "Starting..." "Demarrage..."
        } else {
            $script:TuiDetail
        }
        $detailColor = if ($script:TuiOutcome -eq "error") {
            [ConsoleColor]::Red
        } else {
            [ConsoleColor]::Cyan
        }
        Write-TuiLine 17 ("  > " + $detail) $detailColor

        if ($script:TuiOutcome -eq "success") {
            $liveLine = Format-TuiColumns `
                ("  [OK] " + (Get-UiText "You can close this window." "Tu peux fermer cette fenetre.")) `
                ((Get-UiText "Total" "Total") + " " + (Format-Elapsed $script:RunTimer.Elapsed)) `
                $width
            Write-TuiLine -Row 18 -Text $liveLine -Color Green
        } elseif ($script:TuiOutcome -eq "error") {
            $liveLine = Format-TuiColumns `
                ("  [!!] " + (Get-UiText "Installation stopped." "Installation interrompue.")) `
                ("$(Get-UiText "Step" "Etape") $script:TuiCurrentStage/$($script:TuiStages.Count)") `
                $width
            Write-TuiLine -Row 18 -Text $liveLine -Color Red
        } else {
            $spinnerFrames = @("|", "/", "-", "\")
            $spinner = $spinnerFrames[$script:TuiSpinnerIndex % $spinnerFrames.Count]
            $stageCounter = if ($script:TuiCurrentStage -gt 0) {
                "$(Get-UiText "Step" "Etape") $script:TuiCurrentStage/$($script:TuiStages.Count)"
            } else {
                Get-UiText "Initialising" "Initialisation"
            }
            $liveLine = Format-TuiColumns ("  $spinner  " + (Get-UiText "Please wait" "Patiente...")) $stageCounter $width
            Write-TuiLine -Row 18 -Text $liveLine -Color DarkGray
        }
        Write-TuiLine 19 ""

        $footer = switch ($script:TuiOutcome) {
            "success" {
                if ($script:InstalledToDiscord) {
                    Get-UiText "Discord is ready with YuzuCord." "Discord est pret avec YuzuCord."
                } else {
                    Get-UiText "Build ready. Discord was not modified." "Compilation prete. Discord n'a pas ete modifie."
                }
            }
            "error" {
                Get-UiText "See the diagnostic log below. Discord was only closed during the final stage." "Consulte le journal ci-dessous. Discord est ferme uniquement a la derniere etape."
            }
            default {
                Get-UiText "Discord stays open until the final installation stage." "Discord reste ouvert jusqu'a l'installation finale."
            }
        }
        $footerColor = if ($script:TuiOutcome -eq "error") {
            [ConsoleColor]::Yellow
        } else {
            [ConsoleColor]::DarkGray
        }
        Write-TuiLine 20 ("  " + $footer) $footerColor

        $lastLine = if ($script:TuiOutcome -eq "success" -and $script:UpdateLauncherPath) {
            (Get-UiText "Update: " "MAJ : ") + (Get-TuiFriendlyPath $script:UpdateLauncherPath)
        } else {
            (Get-UiText "Log: " "Log : ") + (Get-TuiFriendlyPath $script:TechnicalLogPath)
        }
        Write-TuiLine -Row 21 -Text ("  " + $lastLine) -Color DarkGray
        Write-TuiLine 22 $border $borderColor
    } catch {
        Write-TechnicalLog "Live TUI rendering failed: $($_.Exception.Message)"
        $script:TuiEnabled = $false
        try {
            [Console]::CursorVisible = $script:TuiOriginalCursorVisible
            [Console]::ForegroundColor = $script:TuiOriginalForegroundColor
            [Console]::BackgroundColor = $script:TuiOriginalBackgroundColor
        } catch {
            # The console is no longer available.
        }
    }
}

function Initialize-LiveTui {
    if ($ShowDetails) {
        return
    }

    try {
        if ([Console]::IsOutputRedirected -or $Host.Name -ne "ConsoleHost" -or [Console]::BufferWidth -lt 70) {
            return
        }

        $script:TuiOriginalCursorVisible = [Console]::CursorVisible
        $script:TuiOriginalForegroundColor = [Console]::ForegroundColor
        $script:TuiOriginalBackgroundColor = [Console]::BackgroundColor
        Clear-Host
        $script:TuiTop = [Console]::CursorTop

        $requiredBufferHeight = $script:TuiTop + $script:TuiHeight + 2
        if ([Console]::BufferHeight -lt $requiredBufferHeight) {
            [Console]::BufferHeight = $requiredBufferHeight
        }

        [Console]::CursorVisible = $false
        $script:TuiEnabled = $true
        $script:TuiInitialized = $true
        Render-LiveTui -Force
    } catch {
        $script:TuiEnabled = $false
        $script:TuiInitialized = $false
        Write-TechnicalLog "Live TUI is unavailable: $($_.Exception.Message)"
    }
}

function Stop-LiveTui {
    if (-not $script:TuiInitialized) {
        return
    }

    try {
        if ($script:TuiEnabled) {
            Render-LiveTui -Force
        }
        $targetRow = [Math]::Min([Console]::BufferHeight - 1, $script:TuiTop + $script:TuiHeight)
        [Console]::SetCursorPosition(0, $targetRow)
        [Console]::ForegroundColor = $script:TuiOriginalForegroundColor
        [Console]::BackgroundColor = $script:TuiOriginalBackgroundColor
        [Console]::CursorVisible = $script:TuiOriginalCursorVisible
        [Console]::WriteLine("")
    } catch {
        Write-TechnicalLog "Could not restore the console after the live TUI: $($_.Exception.Message)"
    } finally {
        $script:TuiEnabled = $false
        $script:TuiInitialized = $false
    }
}

function Update-TuiActivity {
    param(
        [AllowNull()]
        [string]$Detail,
        [double]$Progress = -1,
        [switch]$Force
    )

    if (-not [string]::IsNullOrWhiteSpace($Detail)) {
        $script:TuiDetail = $Detail
    }

    if ($script:TuiCurrentStage -gt 0) {
        if ($Progress -ge 0) {
            $script:TuiStageProgress = [Math]::Max(
                $script:TuiStageProgress,
                [Math]::Min(0.95, $Progress)
            )
        } elseif ($script:TuiStageProgress -lt 0.90) {
            $remaining = 0.90 - $script:TuiStageProgress
            $script:TuiStageProgress += [Math]::Max(0.001, $remaining * 0.02)
        }
    }

    $script:TuiSpinnerIndex++
    Render-LiveTui -Force:$Force
}

function Write-Banner {
    Write-Host ""
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host "  |                        YUZUCORD                           |" -ForegroundColor Cyan
    $subtitle = Get-UiText "Custom Vencord installation and update" "Installation et mise a jour de Vencord personnalise"
    $subtitleLine = ("  |  " + $subtitle).PadRight(61).Substring(0, 61)
    Write-Host $subtitleLine -NoNewline -ForegroundColor White
    Write-Host "|" -ForegroundColor DarkCyan
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step {
    param(
        [int]$Number,
        [int]$Total,
        [string]$Message,
        [string]$Explanation
    )

    $timer = [Diagnostics.Stopwatch]::StartNew()
    Write-TechnicalLog "STAGE $Number/$Total - $Message - $Explanation"
    $script:CurrentStage = $Message
    $script:TuiCurrentStage = $Number
    $script:TuiStageProgress = 0.02
    $script:TuiDetail = $Explanation

    if ($script:TuiEnabled -and $Number -le $script:TuiStages.Count) {
        $stage = $script:TuiStages[$Number - 1]
        $stage.State = "Active"
        $stage.StartedAt = [DateTime]::Now
        $stage.Timer = $timer
        Update-TuiActivity $Explanation -Progress 0.02 -Force
    } else {
        $percent = [Math]::Floor((($Number - 1) / $Total) * 100)
        $filled = [Math]::Floor((($Number - 1) / $Total) * 24)
        $bar = ("#" * $filled).PadRight(24, "-")

        Write-Host ""
        Write-Host "  [$bar] $percent%  $(Get-UiText "Step" "Etape") $Number/$Total" -ForegroundColor Cyan
        Write-Host "  $Message" -ForegroundColor White
        Write-Host "  $Explanation" -ForegroundColor DarkGray
    }

    return $timer
}

function Complete-Step {
    param([Diagnostics.Stopwatch]$Timer)

    $Timer.Stop()
    if ($script:TuiEnabled -and $script:TuiCurrentStage -gt 0) {
        $stage = $script:TuiStages[$script:TuiCurrentStage - 1]
        $stage.State = "Completed"
        $stage.Elapsed = $Timer.Elapsed
        $script:TuiStageProgress = 1.0
        Render-LiveTui -Force
    } else {
        Write-Host "  [OK] $(Get-UiText "Completed in" "Termine en") $(Format-Elapsed $Timer.Elapsed)" -ForegroundColor Green
    }
}

function Set-LiveTuiFailure {
    param([string]$Message)

    $script:TuiOutcome = "error"
    $script:TuiDetail = (Get-UiText "Error: " "Erreur : ") + $Message

    if ($script:TuiCurrentStage -gt 0 -and $script:TuiCurrentStage -le $script:TuiStages.Count) {
        $stage = $script:TuiStages[$script:TuiCurrentStage - 1]
        $stage.State = "Failed"
        if ($null -ne $stage.Timer) {
            $stage.Elapsed = $stage.Timer.Elapsed
        }
    }

    Render-LiveTui -Force
}

function Write-FinalSuccess {
    param(
        [string]$UpdateLauncher,
        [bool]$InstalledToDiscord
    )

    if ($script:TuiEnabled) {
        $script:TuiOutcome = "success"
        $script:TuiDetail = if ($InstalledToDiscord) {
            Get-UiText "Installation completed. Discord remains closed." "Installation terminee. Discord reste ferme."
        } else {
            Get-UiText "Build completed. Discord was not modified." "Compilation terminee. Discord n'a pas ete modifie."
        }
        $script:UpdateLauncherPath = $UpdateLauncher
        Render-LiveTui -Force
        Stop-LiveTui
        return
    }

    Write-Host ""
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Green
    Write-Host "  |  $(Get-UiText "INSTALLATION COMPLETED" "INSTALLATION TERMINEE")".PadRight(59).Substring(0, 59) -NoNewline -ForegroundColor Green
    Write-Host "|" -ForegroundColor Green
    Write-Host "  +----------------------------------------------------------+" -ForegroundColor Green
    if ($InstalledToDiscord) {
        Write-Host "  $(Get-UiText "Discord is ready with YuzuCord." "Discord est pret avec YuzuCord.")" -ForegroundColor White
    } else {
        Write-Host "  $(Get-UiText "The build is ready. Discord was not modified." "La compilation est prete. Discord n'a pas ete modifie.")" -ForegroundColor White
    }
    Write-Host "  $(Get-UiText "Total time:" "Temps total :") $(Format-Elapsed $script:RunTimer.Elapsed)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  $(Get-UiText "For future updates, double-click:" "Pour les prochaines mises a jour, double-clique :")" -ForegroundColor White
    Write-Host "  $UpdateLauncher" -ForegroundColor Cyan
    if ($script:TechnicalLogPath) {
        Write-Host ""
        Write-Host "  $(Get-UiText "Diagnostic log:" "Journal de diagnostic :") $script:TechnicalLogPath" -ForegroundColor DarkGray
    }
}
