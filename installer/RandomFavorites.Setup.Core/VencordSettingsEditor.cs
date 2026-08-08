using System.Text.Json;
using System.Text.Json.Nodes;

namespace RandomFavorites.Setup.Core;

public static class VencordSettingsEditor
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
    };

    public static string? RemovePluginSettings(
        string settingsFile,
        IEnumerable<string> settingsKeys,
        string backupPrefix)
    {
        if (!File.Exists(settingsFile)) return null;

        var keys = settingsKeys
            .Where(key => !string.IsNullOrWhiteSpace(key))
            .Distinct(StringComparer.Ordinal)
            .ToArray();
        if (keys.Length == 0) return null;

        var document = JsonNode.Parse(File.ReadAllText(settingsFile)) as JsonObject
            ?? throw new InvalidDataException("Vencord settings are not a JSON object.");
        if (document["plugins"] is not JsonObject plugins)
            return null;

        var removed = false;
        foreach (var key in keys)
            removed |= plugins.Remove(key);
        if (!removed)
        {
            return null;
        }

        var directory = Path.GetDirectoryName(settingsFile)
            ?? throw new InvalidOperationException("The Vencord settings path has no parent directory.");
        var backupPath = Path.Combine(
            directory,
            $"settings.before-{backupPrefix}-uninstall-{DateTime.UtcNow:yyyyMMdd-HHmmss}.json");
        File.Copy(settingsFile, backupPath, overwrite: false);

        var temporaryPath = settingsFile + ".tmp";
        File.WriteAllText(temporaryPath, document.ToJsonString(JsonOptions));
        File.Move(temporaryPath, settingsFile, overwrite: true);
        return backupPath;
    }

    public static string? RemoveRandomFavoritesSettings(string settingsFile) =>
        RemovePluginSettings(settingsFile, ["RandomFavorites"], "randomfavorites");
}
