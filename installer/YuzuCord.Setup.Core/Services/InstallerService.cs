using YuzuCord.Setup.Core.Models;

namespace YuzuCord.Setup.Core.Services;

public sealed class InstallerService : IDisposable
{
    public const string ProductId = YuzuCordProduct.PersistedId;
    public const string ProductName = YuzuCordProduct.Name;

    private readonly InstallerLayout _layout;
    private readonly ReleaseClient _releaseClient;
    private readonly BundlePayloadStore _bundleStore;
    private readonly DiscordInstallationService _discordService;
    private readonly string _logFile;

    public InstallerService(
        InstallerLayout? layout = null,
        ReleaseClient? releaseClient = null)
    {
        _layout = layout ?? InstallerLayout.ForCurrentUser();
        _releaseClient = releaseClient ?? new ReleaseClient();
        _layout.EnsureDirectories();
        _logFile = Path.Combine(_layout.Logs, $"setup-{DateTime.Now:yyyyMMdd-HHmmss}.log");
        _bundleStore = new BundlePayloadStore(_layout, WriteLog);
        _discordService = new DiscordInstallationService(WriteLog);
    }

    public event Action<string>? LogLine;

    public InstallerLayout Layout => _layout;

    public string CurrentLogFile => _logFile;

    public void WriteDiagnostic(string message) => WriteLog(message);

    public bool IsOpenAsarInstalled(DiscordInstallation discord) =>
        OpenAsarManager.IsInstalled(discord);

    public string? GetOpenAsarDigest(DiscordInstallation discord) =>
        OpenAsarManager.GetInstalledDigest(discord);

    public Task<BundleManifest> GetAvailableManifestAsync(
        CancellationToken cancellationToken) =>
        _releaseClient.GetLatestManifestAsync(cancellationToken);

    public BundleManifest? ReadInstalledManifest(InstallState? state) =>
        _bundleStore.ReadInstalledManifest(state);

    public bool IsInstallationHealthy(
        DiscordInstallation discord,
        InstallState? state,
        BundleManifest? manifest)
        => _bundleStore.IsInstallationHealthy(discord, state, manifest);

    public void StartDiscord(DiscordInstallation discord)
    {
        _discordService.Start(discord);
    }

    public IReadOnlyList<DiscordInstallation> DiscoverDiscordInstallations() =>
        _discordService.Discover(_layout);

    public static string GetVersionDirectoryName(BundleManifest manifest) =>
        BundlePayloadStore.GetVersionDirectoryName(manifest);

    public InstallState? ReadState() => _bundleStore.ReadState();

    public async Task<InstallResult> InstallOrUpdateAsync(
        DiscordInstallation discord,
        bool installOpenAsar,
        IProgress<InstallerProgress>? progress,
        CancellationToken cancellationToken)
    {
        var previousState = ReadState();
        string? stagedDirectory = null;
        string? openAsarPath = null;
        var openAsarChange = OpenAsarChange.None;

        try
        {
            WriteLog($"Installation demandée pour {discord.DisplayName}.");
            var bundlePath = await _releaseClient.DownloadVerifiedBundleAsync(
                _layout,
                progress,
                cancellationToken);
            if (installOpenAsar)
            {
                openAsarPath = await _releaseClient.DownloadVerifiedOpenAsarAsync(
                    _layout,
                    progress,
                    cancellationToken);
            }

            progress?.Report(new InstallerProgress(
                openAsarPath is null ? 0.52 : 0.62,
                "Préparation de YuzuCord",
                "Extraction sécurisée de la version compilée…",
                true));
            stagedDirectory = Path.Combine(_layout.Versions, $".staging-{Guid.NewGuid():N}");
            var manifest = await _bundleStore.ExtractAndValidateAsync(
                bundlePath,
                stagedDirectory,
                cancellationToken);
            var finalDirectory = _bundleStore.ActivateStagedVersion(
                stagedDirectory,
                manifest,
                previousState);
            stagedDirectory = null;

            progress?.Report(new InstallerProgress(
                0.68,
                "Installation dans Discord",
                "Discord va être fermé pendant l'installation."));
            await _discordService.StopAsync(discord, cancellationToken);
            WriteLog("Discord fermé pour appliquer l'installation.");

            try
            {
                await _discordService.RunInstallerAsync(
                    Path.Combine(finalDirectory, "tools", "VencordInstallerCli.exe"),
                    "--repair",
                    discord,
                    finalDirectory,
                    cancellationToken);
                DiscordInstallationService.ValidatePatch(
                    discord,
                    Path.Combine(finalDirectory, "dist", "patcher.js"));

                if (openAsarPath is not null)
                {
                    progress?.Report(new InstallerProgress(
                        0.88,
                        "Actualisation d'OpenAsar",
                        "Comparaison avec la version installée…",
                        true));
                    openAsarChange = OpenAsarManager.ApplyPreference(
                        discord,
                        enabled: true,
                        verifiedOpenAsar: openAsarPath);
                    if (!IsOpenAsarInstalled(discord))
                        throw new InvalidDataException("OpenAsar n'a pas pu être validé après son installation.");
                    WriteLog(openAsarChange switch
                    {
                        OpenAsarChange.Installed => "OpenAsar installé et validé avec succès.",
                        OpenAsarChange.Updated => "OpenAsar mis à jour et validé avec succès.",
                        _ => "OpenAsar utilise déjà la dernière release officielle.",
                    });
                }
                else if (IsOpenAsarInstalled(discord))
                {
                    progress?.Report(new InstallerProgress(
                        0.88,
                        "Application des préférences",
                        "Retrait d'OpenAsar…",
                        true));
                    openAsarChange = OpenAsarManager.ApplyPreference(
                        discord,
                        enabled: false);
                    if (IsOpenAsarInstalled(discord))
                        throw new InvalidDataException("OpenAsar n'a pas pu être retiré.");
                    WriteLog("OpenAsar retiré selon la préférence choisie.");
                }
            }
            catch (Exception installError)
            {
                WriteLog($"La nouvelle version n'a pas pu être activée : {installError.Message}");
                if (openAsarChange == OpenAsarChange.Installed)
                {
                    try
                    {
                        OpenAsarManager.Uninstall(discord);
                        WriteLog("OpenAsar a été restauré après l'échec de l'installation.");
                    }
                    catch (Exception openAsarRollbackError)
                    {
                        WriteLog($"La restauration d'OpenAsar a échoué : {openAsarRollbackError.Message}");
                    }
                }

                if (previousState is not null
                    && Directory.Exists(previousState.ActiveVersionDirectory)
                    && File.Exists(Path.Combine(
                        previousState.ActiveVersionDirectory,
                        "tools",
                        "VencordInstallerCli.exe")))
                {
                    WriteLog("Tentative de restauration de la dernière version fonctionnelle.");
                    try
                    {
                        await _discordService.RunInstallerAsync(
                            Path.Combine(
                                previousState.ActiveVersionDirectory,
                                "tools",
                                "VencordInstallerCli.exe"),
                            "--repair",
                            discord,
                            previousState.ActiveVersionDirectory,
                            cancellationToken);
                        _bundleStore.WriteState(previousState);
                        WriteLog("La version précédente a été restaurée.");
                    }
                    catch (Exception rollbackError)
                    {
                        throw new AggregateException(
                            "L'installation et la restauration ont échoué.",
                            installError,
                            rollbackError);
                    }
                }

                throw;
            }

            var state = new InstallState
            {
                ProductId = manifest.ProductId,
                Version = manifest.Version,
                PluginsDigest = manifest.PluginsDigest,
                Branch = discord.Branch,
                ActiveVersionDirectory = finalDirectory,
                InstalledAtUtc = DateTimeOffset.UtcNow,
            };
            _bundleStore.WriteState(state);
            _bundleStore.PruneInactiveVersions(finalDirectory);
            progress?.Report(new InstallerProgress(
                1,
                "Installation terminée",
                installOpenAsar
                    ? $"YuzuCord {manifest.Version} est prêt et OpenAsar est à jour."
                    : $"YuzuCord {manifest.Version} est prêt."));
            WriteLog($"YuzuCord {manifest.Version} installé avec succès.");
            return new InstallResult(
                true,
                "YuzuCord est installé",
                installOpenAsar
                    ? $"YuzuCord {manifest.Version} et OpenAsar sont prêts."
                    : $"YuzuCord {manifest.Version} est prêt.",
                manifest.Version);
        }
        catch (OperationCanceledException)
        {
            WriteLog("Opération annulée.");
            throw;
        }
        catch (Exception error)
        {
            WriteLog($"Échec : {error.Message}");
            return new InstallResult(false, "L'installation a échoué", error.Message);
        }
        finally
        {
            if (stagedDirectory is not null && Directory.Exists(stagedDirectory))
                _bundleStore.DeleteDirectory(stagedDirectory, _layout.Versions);
        }
    }

    public Task<InstallResult> RepairAsync(
        DiscordInstallation discord,
        bool installOpenAsar,
        IProgress<InstallerProgress>? progress,
        CancellationToken cancellationToken)
    {
        WriteLog("Réparation demandée : le bundle de la release sélectionnée sera vérifié puis réappliqué.");
        return InstallOrUpdateAsync(discord, installOpenAsar, progress, cancellationToken);
    }

    public async Task<InstallResult> UninstallAsync(
        DiscordInstallation discord,
        UninstallMode mode,
        bool removeManagedPluginSettings,
        bool removeOpenAsar,
        IProgress<InstallerProgress>? progress,
        CancellationToken cancellationToken)
    {
        try
        {
            WriteLog($"Désinstallation demandée : {mode}.");
            var openAsarWasInstalled = IsOpenAsarInstalled(discord);
            var openAsarRemoved = false;
            var installedManifest = ReadInstalledManifest(ReadState());
            var officialInstaller = await _releaseClient.DownloadOfficialInstallerAsync(
                _layout,
                progress,
                cancellationToken);

            progress?.Report(new InstallerProgress(
                0.5,
                "Préparation de la désinstallation",
                "Discord va être fermé pendant la désinstallation."));
            await _discordService.StopAsync(discord, cancellationToken);
            WriteLog("Discord fermé pour appliquer la désinstallation.");

            if (mode == UninstallMode.ManagedPluginsOnly)
            {
                progress?.Report(new InstallerProgress(
                    0.64,
                    "Conservation de Vencord",
                    "Retrait de la distribution YuzuCord…",
                    true));
                await _discordService.RunInstallerAsync(
                    officialInstaller,
                    "--repair",
                    discord,
                    customDataDirectory: null,
                    cancellationToken);

                if (removeOpenAsar && openAsarWasInstalled)
                {
                    progress?.Report(new InstallerProgress(
                        0.86,
                        "Restauration de Discord",
                        "Retrait d'OpenAsar…",
                        true));
                    OpenAsarManager.Uninstall(discord);
                    openAsarRemoved = true;
                    WriteLog("OpenAsar retiré ; l'archive Discord d'origine a été restaurée.");
                }

                if (removeManagedPluginSettings)
                {
                    var settingsKeys = installedManifest?.Plugins
                        .Select(plugin => plugin.SettingsKey)
                        .Where(key => !string.IsNullOrWhiteSpace(key))
                        .ToArray() ?? [];
                    if (settingsKeys.Length == 0)
                        settingsKeys = ["RandomFavorites"];
                    var backup = VencordSettingsEditor.RemovePluginSettings(
                        _layout.VencordSettingsFile,
                        settingsKeys,
                        "yuzuctus-vencord");
                    if (backup is not null)
                        WriteLog($"Réglages des plugins gérés retirés. Sauvegarde : {backup}");
                }

                _bundleStore.RemoveCustomPayload();
                var openAsarKept = openAsarWasInstalled && !openAsarRemoved;
                progress?.Report(new InstallerProgress(
                    1,
                    "YuzuCord est désinstallé",
                    openAsarRemoved
                        ? "Vencord officiel est conservé et OpenAsar a été retiré."
                        : openAsarKept
                            ? "Vencord officiel et OpenAsar sont conservés."
                            : "Vencord officiel est conservé."));
                return new InstallResult(
                    true,
                    "YuzuCord est désinstallé",
                    openAsarRemoved
                        ? "Vencord officiel et les autres plugins/réglages sont conservés. OpenAsar a été retiré."
                        : openAsarKept
                            ? "Vencord officiel, OpenAsar et les autres plugins/réglages sont conservés."
                            : "Vencord officiel et les autres plugins/réglages sont conservés.");
            }

            progress?.Report(new InstallerProgress(
                0.64,
                "Désinstallation de Vencord",
                "Restauration de Discord d'origine…",
                true));
            await _discordService.RunInstallerAsync(
                officialInstaller,
                "--uninstall",
                discord,
                customDataDirectory: null,
                cancellationToken);

            if (removeOpenAsar && openAsarWasInstalled)
            {
                progress?.Report(new InstallerProgress(
                    0.86,
                    "Restauration de Discord",
                    "Retrait d'OpenAsar…",
                    true));
                OpenAsarManager.Uninstall(discord);
                openAsarRemoved = true;
                WriteLog("OpenAsar retiré ; l'archive Discord d'origine a été restaurée.");
            }

            _bundleStore.RemoveCustomPayload();

            if (mode == UninstallMode.VencordRemoveData && Directory.Exists(_layout.VencordData))
            {
                _layout.EnsureSafeDeleteTarget(_layout.VencordData, _layout.RoamingAppData);
                Directory.Delete(_layout.VencordData, recursive: true);
                WriteLog($"Données Vencord supprimées : {_layout.VencordData}");
            }

            progress?.Report(new InstallerProgress(
                1,
                "Vencord est désinstallé",
                BuildVencordUninstallDetail(mode, openAsarWasInstalled && !openAsarRemoved)));
            return new InstallResult(
                true,
                "Vencord est désinstallé",
                BuildVencordUninstallMessage(mode, openAsarWasInstalled && !openAsarRemoved));
        }
        catch (OperationCanceledException)
        {
            WriteLog("Désinstallation annulée.");
            throw;
        }
        catch (Exception error)
        {
            WriteLog($"Échec de la désinstallation : {error}");
            return new InstallResult(false, "La désinstallation a échoué", error.Message);
        }
    }

    private static string BuildVencordUninstallDetail(UninstallMode mode, bool openAsarKept)
    {
        var data = mode == UninstallMode.VencordKeepData
            ? "Les réglages locaux ont été conservés."
            : "Les réglages et thèmes locaux ont été supprimés.";
        var openAsar = openAsarKept ? " OpenAsar est conservé." : "";
        return $"{data}{openAsar}";
    }

    private static string BuildVencordUninstallMessage(UninstallMode mode, bool openAsarKept)
    {
        var result = mode == UninstallMode.VencordKeepData
            ? "Vencord a été retiré et tes réglages restent disponibles pour une future réinstallation."
            : "Vencord et ses données locales ont été supprimés.";
        var openAsar = openAsarKept
            ? " OpenAsar reste installé."
            : " Discord utilise de nouveau son archive d'origine.";
        return $"{result}{openAsar}";
    }

    private void WriteLog(string message)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {message}";
        LogLine?.Invoke(line);
        try
        {
            File.AppendAllText(_logFile, line + Environment.NewLine);
        }
        catch
        {
            // Logging must never make installation fail.
        }
    }

    public void Dispose() => _releaseClient.Dispose();
}
