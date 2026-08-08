using System.Text.RegularExpressions;
using RandomFavorites.Setup.Core.Models;

namespace RandomFavorites.Setup.Core;

public static class BundleManifestValidator
{
    public const int CurrentSchemaVersion = 3;

    private static bool IsSafeRelativePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || Path.IsPathRooted(path)) return false;

        return !path
            .Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries)
            .Any(segment => segment is "." or "..");
    }

    private static bool IsHttpsRepository(string value) =>
        Uri.TryCreate(value, UriKind.Absolute, out var uri)
        && string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase);

    public static void Validate(BundleManifest manifest)
    {
        ArgumentNullException.ThrowIfNull(manifest);

        if (manifest.SchemaVersion is < 1 or > CurrentSchemaVersion)
            throw new InvalidDataException("La version de schema du manifeste est invalide.");
        if (!Regex.IsMatch(
                manifest.Version,
                "^v(?:[0-9]+\\.[0-9]+\\.[0-9]+(?:-beta\\.[0-9]+)?|[0-9]+-beta[0-9]+)$"))
            throw new InvalidDataException("La version du manifeste est invalide.");
        if (!Regex.IsMatch(manifest.VencordCommit, "^[0-9a-fA-F]{40}$"))
        {
            throw new InvalidDataException("L'identifiant de source Vencord du manifeste est invalide.");
        }

        if (manifest.SchemaVersion == 1)
        {
            if (!Regex.IsMatch(manifest.PluginCommit, "^[0-9a-fA-F]{40}$"))
                throw new InvalidDataException("L'identifiant de source du plugin du manifeste est invalide.");
        }
        else
        {
            if (!string.Equals(manifest.ProductId, "YuzuctusVencord", StringComparison.Ordinal)
                || manifest.ProductName is not ("YuzuCord" or "Yuzuctus Vencord")
                || !Regex.IsMatch(manifest.DistributionCommit, "^[0-9a-fA-F]{40}$")
                || !Regex.IsMatch(manifest.PluginsDigest, "^[0-9a-fA-F]{64}$")
                || manifest.Plugins is null
                || manifest.Plugins.Length == 0)
            {
                throw new InvalidDataException("L'identite de distribution du manifeste est invalide.");
            }

            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (var plugin in manifest.Plugins)
            {
                if (!Regex.IsMatch(plugin.Id, "^[a-z][A-Za-z0-9]*$")
                    || string.IsNullOrWhiteSpace(plugin.DisplayName)
                    || !IsHttpsRepository(plugin.Repository)
                    || !Regex.IsMatch(plugin.Commit, "^[0-9a-fA-F]{40}$")
                    || !IsSafeRelativePath(plugin.Entrypoint)
                    || plugin.Files is null
                    || plugin.Files.Length == 0
                    || plugin.Files.Any(file => !IsSafeRelativePath(file))
                    || !IsSafeRelativePath(plugin.LicenseFile)
                    || string.IsNullOrWhiteSpace(plugin.License)
                    || !ids.Add(plugin.Id))
                {
                    throw new InvalidDataException("La liste des plugins du manifeste est invalide.");
                }

                if (manifest.SchemaVersion >= 3
                    && (manifest.CatalogSchemaVersion != 2
                        || plugin.SourceType is not ("local" or "git")
                        || !Regex.IsMatch(plugin.SourceDigest, "^[0-9a-fA-F]{64}$")
                        || plugin.Provenance is not ("yuzuctus" or "thirdParty")
                        || plugin.DistributionTags is null
                        || plugin.DistributionTags.Length != 1
                        || !string.Equals(
                            plugin.DistributionTags[0],
                            plugin.Provenance == "yuzuctus" ? "YuzuMod" : "ThirdParty",
                            StringComparison.Ordinal)
                        || plugin.Dependencies is null
                        || plugin.Conflicts is null
                        || plugin.Dependencies.Any(dependency =>
                            dependency == plugin.Id
                            || !Regex.IsMatch(dependency, "^[a-z][A-Za-z0-9]*$"))
                        || plugin.Conflicts.Any(conflict =>
                            conflict == plugin.Id
                            || !Regex.IsMatch(conflict, "^[a-z][A-Za-z0-9]*$"))))
                {
                    throw new InvalidDataException("La provenance des plugins du manifeste est invalide.");
                }
            }

            if (manifest.SchemaVersion >= 3)
            {
                foreach (var plugin in manifest.Plugins)
                {
                    if (plugin.Dependencies.Any(dependency => !ids.Contains(dependency))
                        || plugin.Conflicts.Any(ids.Contains))
                    {
                        throw new InvalidDataException("Les dépendances des plugins du manifeste sont invalides.");
                    }
                }
            }
        }

        if (!Regex.IsMatch(manifest.OpenAsarDigest, "^sha256:[0-9a-fA-F]{64}$")
            || manifest.OpenAsarPublishedAtUtc == default)
        {
            throw new InvalidDataException("La release OpenAsar du manifeste est invalide.");
        }
    }
}
