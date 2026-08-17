using System.Security.Cryptography;
using System.Text;
using YuzuCord.Setup.Core.Models;

namespace YuzuCord.Setup.Core;

public enum OpenAsarChange
{
    None,
    Installed,
    Updated,
    Removed,
}

public static class OpenAsarManager
{
    private const string BackupFileName = "app.asar.backup";
    private const string BackupOwnershipFileName = "app.asar.backup.yuzucord";
    private const string BackupOwnershipHeader = "YuzuCord OpenAsar backup v1";
    private const int ScanBufferSize = 64 * 1024;
    private static readonly byte[] Signature = Encoding.ASCII.GetBytes("OpenAsar");
    private static readonly byte[] ManagedPatcherSignature = Encoding.ASCII.GetBytes(
        YuzuCordProduct.PersistedId);
    private static readonly byte[] PatcherSignature = Encoding.ASCII.GetBytes("patcher.js");
    private static readonly byte[] RequireSignature = Encoding.ASCII.GetBytes("require(");

    public static bool IsInstalled(DiscordInstallation discord)
    {
        try
        {
            return ContainsSignature(FindActiveAsar(discord));
        }
        catch (FileNotFoundException)
        {
            return false;
        }
        catch (DirectoryNotFoundException)
        {
            return false;
        }
    }

    public static OpenAsarChange InstallOrUpdate(
        DiscordInstallation discord,
        string verifiedOpenAsar)
    {
        if (!File.Exists(verifiedOpenAsar))
            throw new FileNotFoundException("Le fichier OpenAsar vérifié est introuvable.", verifiedOpenAsar);
        if (!ContainsSignature(verifiedOpenAsar))
            throw new InvalidDataException("Le fichier téléchargé ne contient pas une archive OpenAsar reconnaissable.");

        var activeAsar = FindActiveAsar(discord);
        if (ContainsSignature(activeAsar))
        {
            if (FilesHaveSameSha256(activeAsar, verifiedOpenAsar))
                return OpenAsarChange.None;

            Update(activeAsar, verifiedOpenAsar);
            return OpenAsarChange.Updated;
        }

        Install(activeAsar, verifiedOpenAsar);
        return OpenAsarChange.Installed;
    }

    public static OpenAsarChange ApplyPreference(
        DiscordInstallation discord,
        bool enabled,
        string? verifiedOpenAsar = null)
    {
        if (enabled)
        {
            if (string.IsNullOrWhiteSpace(verifiedOpenAsar))
            {
                throw new ArgumentException(
                    "Le fichier OpenAsar vérifié est requis pour l'activer.",
                    nameof(verifiedOpenAsar));
            }

            return InstallOrUpdate(discord, verifiedOpenAsar);
        }

        if (!IsInstalled(discord)) return OpenAsarChange.None;

        Uninstall(discord);
        return OpenAsarChange.Removed;
    }

    public static string? GetInstalledDigest(DiscordInstallation discord)
    {
        try
        {
            var activeAsar = FindActiveAsar(discord);
            if (!ContainsSignature(activeAsar)) return null;

            using var stream = File.OpenRead(activeAsar);
            return "sha256:" + Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        }
        catch (FileNotFoundException)
        {
            return null;
        }
        catch (DirectoryNotFoundException)
        {
            return null;
        }
    }

    private static void Install(string activeAsar, string verifiedOpenAsar)
    {
        var resources = Path.GetDirectoryName(activeAsar)!;
        var backup = Path.Combine(resources, BackupFileName);
        var backupOwnership = Path.Combine(resources, BackupOwnershipFileName);
        if (File.Exists(backup))
        {
            if (IsYuzuCordPatcher(backup))
            {
                File.Delete(backup);
                DeleteIfExists(backupOwnership);
            }
            else if (IsOwnedBackup(backup, backupOwnership))
            {
                RefreshOwnedBackup(activeAsar, backup, backupOwnership);
            }
            else if (FilesHaveSameSha256(activeAsar, backup)
                     && !IsYuzuCordPatcher(activeAsar))
            {
                WriteBackupOwnership(backup, backupOwnership);
            }
            else
            {
                throw new InvalidOperationException(
                    "Une sauvegarde app.asar.backup inconnue existe déjà. Elle est conservée pour éviter toute perte.");
            }
        }

        var staged = Path.Combine(resources, $".yuzucord-openasar-{Guid.NewGuid():N}.tmp");
        var previous = Path.Combine(resources, $".yuzucord-openasar-previous-{Guid.NewGuid():N}.tmp");
        File.Copy(verifiedOpenAsar, staged, overwrite: false);
        var originalMoved = false;
        var previousMoved = false;
        try
        {
            if (File.Exists(backup))
            {
                File.Move(activeAsar, previous);
                previousMoved = true;
            }
            else
            {
                File.Move(activeAsar, backup);
                originalMoved = true;
                WriteBackupOwnership(backup, backupOwnership);
            }

            File.Move(staged, activeAsar);
        }
        catch
        {
            if (previousMoved && File.Exists(previous))
                File.Move(previous, activeAsar, overwrite: true);
            else if (originalMoved && File.Exists(backup))
            {
                File.Move(backup, activeAsar, overwrite: true);
                DeleteIfExists(backupOwnership);
            }

            throw;
        }
        finally
        {
            if (File.Exists(staged)) File.Delete(staged);
        }

        DeleteIfExists(previous);
    }

    private static void Update(string activeAsar, string verifiedOpenAsar)
    {
        var resources = Path.GetDirectoryName(activeAsar)!;
        if (!File.Exists(Path.Combine(resources, BackupFileName))
            && !File.Exists(Path.Combine(resources, "app.asar.original")))
        {
            throw new InvalidOperationException(
                "La sauvegarde Discord d'origine est absente. OpenAsar ne sera pas mis à jour tant qu'une réinstallation de Discord ne l'aura pas restaurée.");
        }

        var staged = Path.Combine(resources, $".yuzucord-openasar-update-{Guid.NewGuid():N}.tmp");
        var previous = Path.Combine(resources, $".yuzucord-openasar-previous-{Guid.NewGuid():N}.tmp");
        File.Copy(verifiedOpenAsar, staged, overwrite: false);

        try
        {
            File.Move(activeAsar, previous);
            try
            {
                File.Move(staged, activeAsar);
            }
            catch
            {
                File.Move(previous, activeAsar, overwrite: true);
                throw;
            }
        }
        finally
        {
            if (File.Exists(staged)) File.Delete(staged);
        }

        try
        {
            File.Delete(previous);
        }
        catch (IOException)
        {
            // The verified update is active and the Discord backup is intact.
        }
        catch (UnauthorizedAccessException)
        {
            // The verified update is active and the Discord backup is intact.
        }
    }

    public static void Uninstall(DiscordInstallation discord)
    {
        var activeAsar = FindActiveAsar(discord);
        if (!ContainsSignature(activeAsar)) return;

        var resources = Path.GetDirectoryName(activeAsar)!;
        var backup = new[]
        {
            Path.Combine(resources, BackupFileName),
            Path.Combine(resources, "app.asar.original"),
        }.FirstOrDefault(File.Exists)
            ?? throw new InvalidOperationException(
                "La sauvegarde Discord d'origine est absente. Réinstalle Discord pour restaurer son app.asar officiel.");
        var replaced = Path.Combine(resources, $".yuzucord-openasar-remove-{Guid.NewGuid():N}.tmp");

        try
        {
            File.Move(activeAsar, replaced);
            File.Move(backup, activeAsar);
        }
        catch
        {
            if (File.Exists(replaced) && !File.Exists(activeAsar))
                File.Move(replaced, activeAsar);
            throw;
        }

        try
        {
            File.Delete(replaced);
        }
        catch (IOException)
        {
            // Discord's original archive is already restored. A locked temporary
            // OpenAsar copy is harmless and can be cleaned by a later repair.
        }

        DeleteIfExists(Path.Combine(resources, BackupOwnershipFileName));
    }

    private static void RefreshOwnedBackup(
        string activeAsar,
        string backup,
        string backupOwnership)
    {
        if (FilesHaveSameSha256(activeAsar, backup)) return;
        if (IsYuzuCordPatcher(activeAsar))
        {
            throw new InvalidOperationException(
                "Le chargeur YuzuCord est encore actif à la place de l'archive Discord d'origine.");
        }

        var staged = backup + $".refresh-{Guid.NewGuid():N}.tmp";
        try
        {
            File.Copy(activeAsar, staged, overwrite: false);
            File.Move(staged, backup, overwrite: true);
            WriteBackupOwnership(backup, backupOwnership);
        }
        finally
        {
            DeleteIfExists(staged);
        }
    }

    private static bool IsOwnedBackup(string backup, string ownershipFile)
    {
        if (!File.Exists(ownershipFile)) return false;

        try
        {
            var lines = File.ReadAllLines(ownershipFile);
            return lines.Length == 2
                && lines[0] == BackupOwnershipHeader
                && lines[1].Equals(GetSha256(backup), StringComparison.OrdinalIgnoreCase);
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }

    private static void WriteBackupOwnership(string backup, string ownershipFile)
    {
        var staged = ownershipFile + $".{Guid.NewGuid():N}.tmp";
        try
        {
            File.WriteAllLines(staged, [BackupOwnershipHeader, GetSha256(backup)]);
            File.Move(staged, ownershipFile, overwrite: true);
        }
        finally
        {
            DeleteIfExists(staged);
        }
    }

    private static bool IsYuzuCordPatcher(string path)
    {
        var info = new FileInfo(path);
        if (!info.Exists || info.Length > ScanBufferSize) return false;

        var bytes = File.ReadAllBytes(path).AsSpan();
        return bytes.IndexOf(RequireSignature) >= 0
            && bytes.IndexOf(ManagedPatcherSignature) >= 0
            && bytes.IndexOf(PatcherSignature) >= 0;
    }

    private static void DeleteIfExists(string path)
    {
        if (File.Exists(path)) File.Delete(path);
    }

    private static string FindActiveAsar(DiscordInstallation discord)
    {
        if (!Directory.Exists(discord.RootPath))
            throw new DirectoryNotFoundException($"Discord est introuvable dans {discord.RootPath}.");

        var resources = Directory
            .EnumerateDirectories(discord.RootPath, "app-*")
            .OrderByDescending(Directory.GetLastWriteTimeUtc)
            .Select(directory => Path.Combine(directory, "resources"))
            .FirstOrDefault(Directory.Exists)
            ?? throw new DirectoryNotFoundException("Le dossier resources de Discord est introuvable.");

        foreach (var fileName in new[] { "_app.asar", "app.asar" })
        {
            var candidate = Path.Combine(resources, fileName);
            if (File.Exists(candidate)) return candidate;
        }

        throw new FileNotFoundException("Le fichier app.asar de Discord est introuvable.");
    }

    private static bool ContainsSignature(string path)
    {
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            ScanBufferSize,
            FileOptions.SequentialScan);
        var buffer = new byte[ScanBufferSize + Signature.Length - 1];
        var retained = 0;

        while (true)
        {
            var read = stream.Read(buffer, retained, ScanBufferSize);
            if (read == 0) return false;

            var available = retained + read;
            if (buffer.AsSpan(0, available).IndexOf(Signature) >= 0) return true;

            retained = Math.Min(Signature.Length - 1, available);
            buffer.AsSpan(available - retained, retained).CopyTo(buffer);
        }
    }

    private static bool FilesHaveSameSha256(string first, string second)
    {
        var firstHash = Convert.FromHexString(GetSha256(first));
        var secondHash = Convert.FromHexString(GetSha256(second));
        return CryptographicOperations.FixedTimeEquals(firstHash, secondHash);
    }

    private static string GetSha256(string path)
    {
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }
}
