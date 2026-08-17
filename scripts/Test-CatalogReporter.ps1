[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CatalogPath,

    [Parameter(Mandatory = $true)]
    [string]$ReporterPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedCatalogPath = (Resolve-Path -LiteralPath $CatalogPath).Path
$resolvedReporterPath = (Resolve-Path -LiteralPath $ReporterPath).Path
$catalog = Get-Content -LiteralPath $resolvedCatalogPath -Raw | ConvertFrom-Json
$catalogPluginNames = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

foreach ($plugin in $catalog.plugins) {
    foreach ($name in @($plugin.id, $plugin.displayName, $plugin.settingsKey)) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            [void]$catalogPluginNames.Add($name)
        }
    }
}

$ErrorActionPreference = "Continue"
try {
    $reportLines = @(& node $resolvedReporterPath 2>&1 | ForEach-Object {
        $line = $_.ToString()
        Write-Host $line
        $line
    })
    $reporterExitCode = $LASTEXITCODE
} finally {
    $ErrorActionPreference = "Stop"
}
$reportText = $reportLines -join "`n"

if ($reporterExitCode -eq 0) {
    exit 0
}

if (-not ($reportLines -contains "# Vencord Report")) {
    throw "The Vencord reporter failed before producing its report."
}

$section = ""
$catalogFailures = [System.Collections.Generic.List[string]]::new()
$unscopedFailures = [System.Collections.Generic.List[string]]::new()
$upstreamFailures = [System.Collections.Generic.List[string]]::new()

foreach ($line in $reportLines) {
    if ($line -match '^## (?<section>.+)$') {
        $section = $Matches.section
        continue
    }

    if ($line -notmatch '^- (?<failure>.+)$') {
        continue
    }

    $failure = $Matches.failure
    switch ($section) {
        "Bad Patches" {
            $pluginName = ($failure -replace ' \(.+\)$', '').Trim()
            if ($catalogPluginNames.Contains($pluginName)) {
                $catalogFailures.Add("${pluginName}: incompatible Discord patch")
            } else {
                $upstreamFailures.Add("${pluginName}: incompatible official Vencord patch")
            }
        }
        "Bad Starts" {
            $pluginName = $failure.Trim()
            if ($catalogPluginNames.Contains($pluginName)) {
                $catalogFailures.Add("${pluginName}: failed to start")
            } else {
                $upstreamFailures.Add("${pluginName}: official Vencord plugin failed to start")
            }
        }
        "Bad Webpack Finds" {
            $unscopedFailures.Add("Missing Webpack find: $failure")
        }
    }
}

$discordErrorsMatch = [regex]::Match(
    $reportText,
    '(?ms)^## Discord Errors\s*(?<body>.*?)(?=^## )'
)
if ($discordErrorsMatch.Success) {
    $discordErrorBody = $discordErrorsMatch.Groups["body"].Value.Trim()
    if (-not [string]::IsNullOrWhiteSpace($discordErrorBody)) {
        $discordErrorEntries = [regex]::Matches(
            $discordErrorBody,
            '(?ms)^- ```\s*(?<message>.*?)^\s*```\s*$'
        )

        if ($discordErrorEntries.Count -eq 0) {
            $unscopedFailures.Add("Unparseable Discord reporter error")
        } else {
            foreach ($entry in $discordErrorEntries) {
                $message = $entry.Groups["message"].Value.Trim()
                if ($message -match 'Could not complete Remote Auth login') {
                    Write-Warning "Ignoring the expected headless Discord Remote Auth retry."
                    continue
                }

                $unscopedFailures.Add("Unexpected Discord error: $message")
            }
        }
    }
}

if ($catalogFailures.Count -gt 0 -or $unscopedFailures.Count -gt 0) {
    $failures = @($catalogFailures) + @($unscopedFailures)
    throw "YuzuCord catalog validation failed:`n- $($failures -join "`n- ")"
}

if ($upstreamFailures.Count -eq 0) {
    throw "The Vencord reporter failed without a classifiable error."
}

Write-Warning (
    "The reporter found only incompatibilities in official Vencord plugins. " +
    "YuzuCord catalog plugins passed:`n- " +
    ($upstreamFailures -join "`n- ")
)
exit 0
