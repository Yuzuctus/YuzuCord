using System.Text.RegularExpressions;
using RandomFavorites.Setup.Core.Models;

namespace RandomFavorites.Setup.Core;

public static class BundleManifestValidator
{
    public const int CurrentSchemaVersion = 2;

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
                || !string.Equals(manifest.ProductName, "Yuzuctus Vencord", StringComparison.Ordinal)
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
                    || string.IsNullOrWhiteSpace(plugin.Repository)
                    || !Regex.IsMatch(plugin.Commit, "^[0-9a-fA-F]{40}$")
                    || string.IsNullOrWhiteSpace(plugin.Entrypoint)
                    || plugin.Files is null
                    || plugin.Files.Length == 0
                    || string.IsNullOrWhiteSpace(plugin.License)
                    || !ids.Add(plugin.Id))
                {
                    throw new InvalidDataException("La liste des plugins du manifeste est invalide.");
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
