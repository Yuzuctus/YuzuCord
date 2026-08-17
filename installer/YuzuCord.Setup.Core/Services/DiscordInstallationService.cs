using System.Diagnostics;
using System.Text;
using YuzuCord.Setup.Core.Models;

namespace YuzuCord.Setup.Core.Services;

internal sealed class DiscordInstallationService(Action<string> writeLog)
{
    public IReadOnlyList<DiscordInstallation> Discover(InstallerLayout layout)
    {
        var candidates = new[]
        {
            new DiscordInstallation(
                DiscordBranch.Stable,
                "Discord Stable",
                Path.Combine(layout.LocalAppData, "Discord"),
                "Discord",
                "Discord.exe"),
            new DiscordInstallation(
                DiscordBranch.Ptb,
                "Discord PTB",
                Path.Combine(layout.LocalAppData, "DiscordPTB"),
                "DiscordPTB",
                "DiscordPTB.exe"),
            new DiscordInstallation(
                DiscordBranch.Canary,
                "Discord Canary",
                Path.Combine(layout.LocalAppData, "DiscordCanary"),
                "DiscordCanary",
                "DiscordCanary.exe"),
        };

        return candidates.Where(candidate => Directory.Exists(candidate.RootPath)).ToArray();
    }

    public void Start(DiscordInstallation discord)
    {
        DiscordLauncher.Start(discord);
        writeLog($"{discord.DisplayName} relancé à la demande de l'utilisateur.");
    }

    public async Task RunInstallerAsync(
        string executable,
        string operation,
        DiscordInstallation discord,
        string? customDataDirectory,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(executable))
            throw new FileNotFoundException("L'installateur CLI de Vencord est absent.", executable);

        var startInfo = new ProcessStartInfo
        {
            FileName = executable,
            Arguments = $"{operation} --branch {discord.CliBranch}",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8,
            WorkingDirectory = Path.GetDirectoryName(executable)!,
        };
        if (customDataDirectory is not null)
        {
            startInfo.Environment["VENCORD_USER_DATA_DIR"] = customDataDirectory;
            startInfo.Environment["VENCORD_DEV_INSTALL"] = "1";
        }

        using var process = new Process { StartInfo = startInfo };
        process.OutputDataReceived += (_, eventArgs) =>
        {
            if (!string.IsNullOrWhiteSpace(eventArgs.Data)) writeLog(eventArgs.Data);
        };
        process.ErrorDataReceived += (_, eventArgs) =>
        {
            if (!string.IsNullOrWhiteSpace(eventArgs.Data)) writeLog(eventArgs.Data);
        };

        writeLog($"VencordInstallerCli {operation} --branch {discord.CliBranch}");
        if (!process.Start())
            throw new InvalidOperationException("Impossible de démarrer l'installateur Vencord.");
        await process.StandardInput.WriteLineAsync();
        process.StandardInput.Close();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        try
        {
            await process.WaitForExitAsync(cancellationToken);
        }
        catch (OperationCanceledException)
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
                await process.WaitForExitAsync(CancellationToken.None);
            }

            throw;
        }

        if (process.ExitCode != 0)
            throw new InvalidOperationException(
                $"L'installateur Vencord s'est arrêté avec le code {process.ExitCode}.");
    }

    public async Task StopAsync(
        DiscordInstallation discord,
        CancellationToken cancellationToken)
    {
        var processes = Process.GetProcessesByName(discord.ProcessName);
        foreach (var process in processes)
        {
            using (process)
            {
                try
                {
                    if (process.CloseMainWindow())
                    {
                        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                            cancellationToken);
                        timeout.CancelAfter(TimeSpan.FromSeconds(5));
                        try
                        {
                            await process.WaitForExitAsync(timeout.Token);
                            continue;
                        }
                        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                        {
                            // Discord did not close gracefully; force-close only this known process.
                        }
                    }

                    process.Kill(entireProcessTree: true);
                    await process.WaitForExitAsync(cancellationToken);
                }
                catch (InvalidOperationException)
                {
                    // Process exited between discovery and shutdown.
                }
            }
        }
    }

    public static void ValidatePatch(
        DiscordInstallation discord,
        string expectedPatcher)
    {
        var appAsar = Directory
            .EnumerateDirectories(discord.RootPath, "app-*")
            .OrderByDescending(Directory.GetLastWriteTimeUtc)
            .Select(directory => Path.Combine(directory, "resources", "app.asar"))
            .FirstOrDefault(File.Exists)
            ?? throw new FileNotFoundException("Le fichier app.asar de Discord est introuvable.");
        var patch = File.ReadAllText(appAsar);
        var escapedPatcher = expectedPatcher.Replace("\\", "\\\\", StringComparison.Ordinal);
        if (!patch.Contains(expectedPatcher, StringComparison.OrdinalIgnoreCase)
            && !patch.Contains(escapedPatcher, StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException(
                "Discord n'a pas été relié à la version YuzuCord attendue.");
        }
    }
}
