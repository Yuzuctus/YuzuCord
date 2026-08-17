using System.IO.Compression;
using System.Text.Json;
using System.Text.Json.Serialization;
using YuzuCord.Setup.Core.Models;

namespace YuzuCord.Setup.Core.Services;

internal sealed class BundlePayloadStore(
    InstallerLayout layout,
    Action<string> writeLog)
{
    private const int MaximumBundleEntries = 2048;
    private const long MaximumExtractedBundleBytes = 512L * 1024 * 1024;
    private static readonly string[] RequiredBundleFiles =
    [
        "dist/patcher.js",
        "dist/preload.js",
        "dist/renderer.js",
        "dist/renderer.css",
        "tools/VencordInstallerCli.exe",
    ];

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public BundleManifest? ReadInstalledManifest(InstallState? state)
    {
        if (state is null) return null;

        try
        {
            layout.EnsureSafeDeleteTarget(state.ActiveVersionDirectory, layout.Versions);
            var path = Path.Combine(state.ActiveVersionDirectory, "manifest.json");
            if (!File.Exists(path)) return null;
            var manifest = JsonSerializer.Deserialize<BundleManifest>(
                File.ReadAllText(path),
                JsonOptions);
            if (manifest is null) return null;
            BundleManifestValidator.Validate(manifest);
            return manifest;
        }
        catch (Exception error)
        {
            writeLog($"Manifeste installé illisible : {error.Message}");
            return null;
        }
    }

    public bool IsInstallationHealthy(
        DiscordInstallation discord,
        InstallState? state,
        BundleManifest? manifest)
    {
        if (state is null || manifest is null || state.Branch != discord.Branch)
            return false;

        try
        {
            layout.EnsureSafeDeleteTarget(state.ActiveVersionDirectory, layout.Versions);
            var patcher = Path.Combine(state.ActiveVersionDirectory, "dist", "patcher.js");
            var installer = Path.Combine(
                state.ActiveVersionDirectory,
                "tools",
                "VencordInstallerCli.exe");
            if (!File.Exists(patcher) || !File.Exists(installer)) return false;
            foreach (var requiredFile in RequiredBundleFiles
                         .Concat(manifest.RequiredFiles ?? [])
                         .Distinct(StringComparer.OrdinalIgnoreCase))
            {
                var resolved = Path.GetFullPath(Path.Combine(state.ActiveVersionDirectory, requiredFile));
                var versionRoot = Path.GetFullPath(state.ActiveVersionDirectory).TrimEnd(
                    Path.DirectorySeparatorChar,
                    Path.AltDirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if (!resolved.StartsWith(versionRoot, StringComparison.OrdinalIgnoreCase)
                    || !File.Exists(resolved))
                {
                    return false;
                }
            }
            DiscordInstallationService.ValidatePatch(discord, patcher);
            return true;
        }
        catch (Exception error)
        {
            writeLog($"Installation à réparer : {error.Message}");
            return false;
        }
    }

    public static string GetVersionDirectoryName(BundleManifest manifest)
    {
        var safeVersion = string.Concat(
            manifest.Version.Select(character =>
                Path.GetInvalidFileNameChars().Contains(character) ? '-' : character));
        var pluginIdentity = string.IsNullOrWhiteSpace(manifest.PluginsDigest)
            ? manifest.PluginCommit
            : manifest.PluginsDigest;
        var pluginSuffix = pluginIdentity[..Math.Min(8, pluginIdentity.Length)];
        var vencordSuffix = manifest.VencordCommit[..Math.Min(8, manifest.VencordCommit.Length)];

        return string.Join(
            "-",
            new[] { safeVersion, pluginSuffix, vencordSuffix }
                .Where(part => !string.IsNullOrWhiteSpace(part)));
    }

    public InstallState? ReadState()
    {
        if (!File.Exists(layout.StateFile))
            return TryMigrateLegacyState();

        try
        {
            var state = JsonSerializer.Deserialize<InstallState>(
                File.ReadAllText(layout.StateFile),
                JsonOptions);
            if (state is null) return null;
            if (!Enum.IsDefined(state.Branch))
                throw new InvalidDataException("La version de Discord enregistrée est invalide.");

            layout.EnsureSafeDeleteTarget(state.ActiveVersionDirectory, layout.Versions);
            return state;
        }
        catch (Exception error)
        {
            writeLog($"État local illisible, une réparation complète sera proposée : {error.Message}");
            return null;
        }
    }

    public async Task<BundleManifest> ExtractAndValidateAsync(
        string bundlePath,
        string destination,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(destination);
        var root = Path.GetFullPath(destination).TrimEnd(Path.DirectorySeparatorChar)
            + Path.DirectorySeparatorChar;

        using var archive = ZipFile.OpenRead(bundlePath);
        if (archive.Entries.Count > MaximumBundleEntries
            || archive.Entries.Sum(entry => entry.Length) > MaximumExtractedBundleBytes)
        {
            throw new InvalidDataException("Le bundle dépasse les limites de sécurité autorisées.");
        }

        foreach (var entry in archive.Entries)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var target = Path.GetFullPath(Path.Combine(destination, entry.FullName));
            if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException($"Entrée ZIP dangereuse refusée : {entry.FullName}");

            if (string.IsNullOrEmpty(entry.Name))
            {
                Directory.CreateDirectory(target);
                continue;
            }

            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            await using var source = entry.Open();
            await using var output = new FileStream(
                target,
                FileMode.Create,
                FileAccess.Write,
                FileShare.None,
                1024 * 128,
                useAsync: true);
            await source.CopyToAsync(output, cancellationToken);
        }

        var manifestPath = Path.Combine(destination, "manifest.json");
        if (!File.Exists(manifestPath))
            throw new InvalidDataException("Le bundle ne contient pas manifest.json.");
        var manifest = JsonSerializer.Deserialize<BundleManifest>(
            await File.ReadAllTextAsync(manifestPath, cancellationToken),
            JsonOptions)
            ?? throw new InvalidDataException("Le manifeste du bundle est invalide.");
        BundleManifestValidator.Validate(manifest);

        foreach (var requiredFile in RequiredBundleFiles
                     .Concat(manifest.RequiredFiles ?? [])
                     .Distinct(StringComparer.OrdinalIgnoreCase))
        {
            var resolved = Path.GetFullPath(Path.Combine(destination, requiredFile));
            if (!resolved.StartsWith(root, StringComparison.OrdinalIgnoreCase)
                || !File.Exists(resolved))
            {
                throw new InvalidDataException($"Fichier obligatoire absent du bundle : {requiredFile}");
            }
        }

        return manifest;
    }

    public string ActivateStagedVersion(
        string stagedDirectory,
        BundleManifest manifest,
        InstallState? currentState)
    {
        var directoryName = GetVersionDirectoryName(manifest);
        var finalDirectory = Path.Combine(layout.Versions, directoryName);

        if (Directory.Exists(finalDirectory))
        {
            if (currentState is not null
                && Path.GetFullPath(currentState.ActiveVersionDirectory)
                    .Equals(Path.GetFullPath(finalDirectory), StringComparison.OrdinalIgnoreCase))
            {
                DeleteDirectory(stagedDirectory, layout.Versions);
                return finalDirectory;
            }

            DeleteDirectory(finalDirectory, layout.Versions);
        }

        Directory.Move(stagedDirectory, finalDirectory);
        return finalDirectory;
    }

    public void WriteState(InstallState state)
    {
        layout.EnsureDirectories();
        var temporary = layout.StateFile + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(state, JsonOptions));
        File.Move(temporary, layout.StateFile, overwrite: true);
    }

    public void RemoveCustomPayload()
    {
        if (Directory.Exists(layout.Versions))
        {
            layout.EnsureSafeDeleteTarget(layout.Versions, layout.Root);
            Directory.Delete(layout.Versions, recursive: true);
        }

        if (File.Exists(layout.StateFile)) File.Delete(layout.StateFile);
        writeLog("Fichiers compilés YuzuCord supprimés.");
    }

    public void PruneInactiveVersions(string activeDirectory)
    {
        if (!Directory.Exists(layout.Versions)) return;

        var resolvedActive = Path.GetFullPath(activeDirectory);
        foreach (var directory in Directory.EnumerateDirectories(layout.Versions))
        {
            if (Path.GetFullPath(directory).Equals(
                    resolvedActive,
                    StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            try
            {
                DeleteDirectory(directory, layout.Versions);
            }
            catch (Exception error)
            {
                writeLog($"Ancienne version conservée car son nettoyage a échoué : {error.Message}");
            }
        }
    }

    public void DeleteDirectory(string target, string allowedRoot)
    {
        layout.EnsureSafeDeleteTarget(target, allowedRoot);
        Directory.Delete(target, recursive: true);
    }

    private InstallState? TryMigrateLegacyState()
    {
        var legacyStateFile = Path.Combine(layout.LegacyRoot, "state.json");
        var legacyVersions = Path.Combine(layout.LegacyRoot, "versions");
        if (!File.Exists(legacyStateFile)) return null;

        try
        {
            var legacyState = JsonSerializer.Deserialize<InstallState>(
                File.ReadAllText(legacyStateFile),
                JsonOptions);
            if (legacyState is null || !Enum.IsDefined(legacyState.Branch))
                return null;

            layout.EnsureSafeDeleteTarget(legacyState.ActiveVersionDirectory, legacyVersions);
            if (!Directory.Exists(legacyState.ActiveVersionDirectory)) return null;

            var versionName = Path.GetFileName(
                Path.GetFullPath(legacyState.ActiveVersionDirectory)
                    .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
            if (string.IsNullOrWhiteSpace(versionName)) return null;

            layout.EnsureDirectories();
            var migratedDirectory = Path.Combine(layout.Versions, versionName);
            if (Directory.Exists(migratedDirectory)) return null;
            Directory.Move(legacyState.ActiveVersionDirectory, migratedDirectory);

            var migratedState = new InstallState
            {
                ProductId = string.IsNullOrWhiteSpace(legacyState.ProductId)
                    ? YuzuCordProduct.LegacyRandomFavoritesId
                    : legacyState.ProductId,
                Version = legacyState.Version,
                PluginsDigest = legacyState.PluginsDigest,
                Branch = legacyState.Branch,
                ActiveVersionDirectory = migratedDirectory,
                InstalledAtUtc = legacyState.InstalledAtUtc,
            };
            WriteState(migratedState);
            File.Move(legacyStateFile, legacyStateFile + ".migrated", overwrite: true);
            writeLog("Ancienne installation RandomFavorites migree vers YuzuCord.");
            return migratedState;
        }
        catch (Exception error)
        {
            writeLog($"Migration de l'ancienne installation ignoree : {error.Message}");
            return null;
        }
    }
}
