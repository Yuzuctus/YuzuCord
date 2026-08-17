namespace YuzuCord.Setup.Core;

/// <summary>
/// Stable product identifiers shared by the installer components.
/// </summary>
public static class YuzuCordProduct
{
    public const string Name = "YuzuCord";

    // This value and the data directory are persisted by released installers.
    // Keep them stable so existing installations remain updateable in place.
    public const string PersistedId = "YuzuctusVencord";
    public const string DataDirectoryName = PersistedId;

    public const string LegacyRandomFavoritesId = "RandomFavorites";
    public const string LegacyRandomFavoritesDataDirectoryName = "RandomFavorites";
    public const string LegacyManagerDataDirectoryName = "RandomFavoritesVencord";
}
