using System.Text.Json.Serialization;

namespace RandomFavorites.Setup.Core.Models;

public enum DiscordBranch
{
    Stable,
    Ptb,
    Canary,
}

public enum UninstallMode
{
    ManagedPluginsOnly,
    VencordKeepData,
    VencordRemoveData,
}

public sealed record DiscordInstallation(
    DiscordBranch Branch,
    string DisplayName,
    string RootPath,
    string ProcessName,
    string ExecutableName)
{
    public string CliBranch => Branch switch
    {
        DiscordBranch.Stable => "stable",
        DiscordBranch.Ptb => "ptb",
        DiscordBranch.Canary => "canary",
        _ => throw new ArgumentOutOfRangeException(nameof(Branch)),
    };
}

public sealed record InstallerProgress(
    double Percent,
    string Stage,
    string Detail,
    bool IsIndeterminate = false);

public sealed class PluginManifest
{
    public string Id { get; init; } = "";

    public string DisplayName { get; init; } = "";

    public string Repository { get; init; } = "";

    public string Commit { get; init; } = "";

    // Present only in legacy schema-2 manifests.
    public string SourcePath { get; init; } = "";

    public string SourceType { get; init; } = "";

    public string SourceDigest { get; init; } = "";

    public string Entrypoint { get; init; } = "";

    public string[] Files { get; init; } = [];

    public string SettingsKey { get; init; } = "";

    public string Provenance { get; init; } = "";

    public string[] DistributionTags { get; init; } = [];

    public string[] Dependencies { get; init; } = [];

    public string[] Conflicts { get; init; } = [];

    public string License { get; init; } = "";

    public string LicenseFile { get; init; } = "";

    public string Maintainer { get; init; } = "";

    public string Status { get; init; } = "";
}

public sealed class BundleManifest
{
    public int SchemaVersion { get; init; } = 1;

    public string ProductId { get; init; } = "YuzuctusVencord";

    public string ProductName { get; init; } = "YuzuCord";

    public string Version { get; init; } = "";

    public string VencordRepository { get; init; } = "";

    public string VencordCommit { get; init; } = "";

    public string DistributionCommit { get; init; } = "";

    public int CatalogSchemaVersion { get; init; }

    // Kept so manifests from the first mono-plugin releases remain readable.
    public string PluginCommit { get; init; } = "";

    public string PluginsDigest { get; init; } = "";

    public PluginManifest[] Plugins { get; init; } = [];

    public string OpenAsarDigest { get; init; } = "";

    public DateTimeOffset OpenAsarPublishedAtUtc { get; init; }

    public DateTimeOffset BuiltAtUtc { get; init; }

    public string[] RequiredFiles { get; init; } = [];
}

public sealed class InstallState
{
    public string ProductId { get; init; } = "";

    public string Version { get; init; } = "";

    public string PluginsDigest { get; init; } = "";

    [JsonConverter(typeof(JsonStringEnumConverter))]
    public DiscordBranch Branch { get; init; }

    public string ActiveVersionDirectory { get; init; } = "";

    public DateTimeOffset InstalledAtUtc { get; init; }
}

public sealed record InstallResult(
    bool Success,
    string Title,
    string Message,
    string? Version = null);
