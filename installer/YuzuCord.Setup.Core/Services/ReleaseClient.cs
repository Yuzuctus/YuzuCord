using System.Diagnostics;
using System.Net.Http.Headers;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using YuzuCord.Setup.Core.Models;

namespace YuzuCord.Setup.Core.Services;

public sealed class ReleaseClient : IDisposable
{
    public const string ReleasesApiUrl =
        "https://api.github.com/repos/Yuzuctus/YuzuCord/releases?per_page=30";
    public const string OfficialInstallerUrl =
        "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe";
    public const string OfficialInstallerChecksumUrl =
        "https://github.com/Vencord/Installer/releases/latest/download/checksums.sha256";
    public const string OpenAsarReleaseApiUrl =
        "https://api.github.com/repos/GooseMod/OpenAsar/releases/tags/nightly";
    private const string ReleaseDownloadBaseUrl =
        "https://github.com/Yuzuctus/YuzuCord/releases/download";
    private static readonly string[] RequiredReleaseAssets =
    [
        "YuzuCordBundle.zip",
        "YuzuCordBundle.zip.sha256",
        "YuzuCordBundle.manifest.json",
    ];

    private readonly HttpClient _httpClient;
    private readonly string? _releaseTag;
    private string? _resolvedReleaseTag;

    public ReleaseClient(HttpMessageHandler? handler = null, string? releaseTag = null)
    {
        _httpClient = handler is null ? new HttpClient() : new HttpClient(handler);
        _httpClient.DefaultRequestHeaders.UserAgent.Add(
            new ProductInfoHeaderValue("YuzuCordSetup", "2.0"));
        _httpClient.Timeout = TimeSpan.FromMinutes(15);

        _releaseTag = NormalizeReleaseTag(releaseTag ?? ReadBuildReleaseTag());
    }

    public async Task<string> DownloadVerifiedBundleAsync(
        InstallerLayout layout,
        IProgress<InstallerProgress>? progress,
        CancellationToken cancellationToken)
    {
        layout.EnsureDirectories();
        var release = await ResolveReleaseAssetsAsync(cancellationToken);
        var bundlePath = Path.Combine(layout.Downloads, "YuzuCordBundle.zip");
        var checksum = ParseSha256(await GetRequiredReleaseTextAsync(
            release.ChecksumUrl,
            release.Tag,
            "YuzuCordBundle.zip.sha256",
            cancellationToken));

        await DownloadFileWithRetriesAsync(
            release.BundleUrl,
            bundlePath,
            "Téléchargement de YuzuCord",
            progress,
            cancellationToken,
            notFoundMessage: BuildMissingAssetMessage(release.Tag, "YuzuCordBundle.zip"));

        progress?.Report(new InstallerProgress(
            0.48,
            "Vérification du téléchargement",
            "Contrôle de l'intégrité SHA-256…",
            true));
        var actualChecksum = await ComputeSha256Async(bundlePath, cancellationToken);
        if (!actualChecksum.Equals(checksum, StringComparison.OrdinalIgnoreCase))
        {
            File.Delete(bundlePath);
            throw new InvalidDataException(
                $"Le fichier téléchargé est invalide. SHA-256 attendu {checksum}, obtenu {actualChecksum}.");
        }

        return bundlePath;
    }

    public async Task<BundleManifest> GetLatestManifestAsync(
        CancellationToken cancellationToken)
    {
        var release = await ResolveReleaseAssetsAsync(cancellationToken);
        using var response = await GetRequiredReleaseResponseAsync(
            release.ManifestUrl,
            release.Tag,
            "YuzuCordBundle.manifest.json",
            cancellationToken);
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var manifest = await JsonSerializer.DeserializeAsync<BundleManifest>(
            stream,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true },
            cancellationToken)
            ?? throw new InvalidDataException("Le manifeste de la dernière release est illisible.");
        BundleManifestValidator.Validate(manifest);
        return manifest;
    }

    public async Task<string> DownloadOfficialInstallerAsync(
        InstallerLayout layout,
        IProgress<InstallerProgress>? progress,
        CancellationToken cancellationToken)
    {
        layout.EnsureDirectories();
        var installerPath = Path.Combine(layout.Downloads, "VencordInstallerCli.exe");
        var checksumFile = await _httpClient.GetStringAsync(
            OfficialInstallerChecksumUrl,
            cancellationToken);
        var expectedChecksum = ParseSha256ForFile(
            checksumFile,
            "VencordInstallerCli.exe");
        await DownloadFileWithRetriesAsync(
            OfficialInstallerUrl,
            installerPath,
            "Préparation de Vencord officiel",
            progress,
            cancellationToken);

        progress?.Report(new InstallerProgress(
            0.46,
            "Vérification de Vencord officiel",
            "Contrôle de l'intégrité SHA-256…",
            true));
        var actualChecksum = await ComputeSha256Async(installerPath, cancellationToken);
        if (!actualChecksum.Equals(expectedChecksum, StringComparison.OrdinalIgnoreCase))
        {
            File.Delete(installerPath);
            throw new InvalidDataException(
                "L'installateur officiel de Vencord ne correspond pas à son empreinte SHA-256 publiée.");
        }

        return installerPath;
    }

    public async Task<string> DownloadVerifiedOpenAsarAsync(
        InstallerLayout layout,
        IProgress<InstallerProgress>? progress,
        CancellationToken cancellationToken)
    {
        layout.EnsureDirectories();
        using var releaseResponse = await _httpClient.GetAsync(
            OpenAsarReleaseApiUrl,
            cancellationToken);
        releaseResponse.EnsureSuccessStatusCode();
        await using var releaseStream = await releaseResponse.Content.ReadAsStreamAsync(
            cancellationToken);
        var release = await JsonSerializer.DeserializeAsync<GitHubRelease>(
            releaseStream,
            cancellationToken: cancellationToken)
            ?? throw new InvalidDataException("La release OpenAsar officielle est illisible.");
        var asset = release.Assets?.FirstOrDefault(candidate =>
            string.Equals(candidate.Name, "app.asar", StringComparison.OrdinalIgnoreCase))
            ?? throw new InvalidDataException("La release OpenAsar ne contient pas app.asar.");
        var expectedChecksum = ParseGitHubDigest(asset.Digest);
        if (string.IsNullOrWhiteSpace(asset.DownloadUrl)
            || !Uri.TryCreate(asset.DownloadUrl, UriKind.Absolute, out var downloadUri)
            || !downloadUri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase)
            || !downloadUri.Host.Equals("github.com", StringComparison.OrdinalIgnoreCase)
            || !downloadUri.AbsolutePath.StartsWith(
                "/GooseMod/OpenAsar/releases/download/",
                StringComparison.OrdinalIgnoreCase))
        {
            throw new InvalidDataException("L'adresse de téléchargement OpenAsar n'est pas officielle.");
        }

        var openAsarPath = Path.Combine(layout.Downloads, "OpenAsar.app.asar");
        await DownloadFileWithRetriesAsync(
            asset.DownloadUrl,
            openAsarPath,
            "Téléchargement d'OpenAsar",
            progress,
            cancellationToken,
            startPercent: 0.5,
            endPercent: 0.58);

        progress?.Report(new InstallerProgress(
            0.59,
            "Vérification d'OpenAsar",
            "Contrôle de l'intégrité SHA-256…",
            true));
        var actualChecksum = await ComputeSha256Async(openAsarPath, cancellationToken);
        if (!actualChecksum.Equals(expectedChecksum, StringComparison.OrdinalIgnoreCase))
        {
            File.Delete(openAsarPath);
            throw new InvalidDataException(
                "OpenAsar ne correspond pas à l'empreinte SHA-256 publiée par GitHub.");
        }

        return openAsarPath;
    }

    public static string ParseSha256(string checksumFile)
    {
        var candidate = checksumFile
            .Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault();
        if (candidate is null
            || candidate.Length != 64
            || candidate.Any(character => !Uri.IsHexDigit(character)))
        {
            throw new InvalidDataException("Le fichier de contrôle SHA-256 est invalide.");
        }

        return candidate.ToLowerInvariant();
    }

    public static string ParseSha256ForFile(string checksumFile, string fileName)
    {
        foreach (var line in checksumFile.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = line.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 2) continue;

            var listedFile = parts[^1].TrimStart('*');
            if (listedFile.Equals(fileName, StringComparison.OrdinalIgnoreCase))
                return ParseSha256(parts[0]);
        }

        throw new InvalidDataException(
            $"Le fichier de contrôle ne contient pas d'empreinte pour {fileName}.");
    }

    public static string ParseGitHubDigest(string? digest)
    {
        const string prefix = "sha256:";
        if (digest is null || !digest.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("L'empreinte OpenAsar n'utilise pas SHA-256.");

        var hash = digest[prefix.Length..];
        if (hash.Length != 64 || hash.Any(character => !Uri.IsHexDigit(character)))
            throw new InvalidDataException("L'empreinte SHA-256 OpenAsar est invalide.");
        return hash.ToLowerInvariant();
    }

    private async Task DownloadFileWithRetriesAsync(
        string url,
        string destination,
        string stage,
        IProgress<InstallerProgress>? progress,
        CancellationToken cancellationToken,
        double startPercent = 0.08,
        double endPercent = 0.44,
        string? notFoundMessage = null)
    {
        Exception? lastError = null;
        for (var attempt = 1; attempt <= 3; attempt++)
        {
            try
            {
                await DownloadFileAsync(
                    url,
                    destination,
                    stage,
                    progress,
                    cancellationToken,
                    startPercent,
                    endPercent,
                    notFoundMessage);
                return;
            }
            catch (Exception error) when (error is not (OperationCanceledException or InvalidOperationException)
                                          && attempt < 3)
            {
                lastError = error;
                progress?.Report(new InstallerProgress(
                    startPercent,
                    stage,
                    $"Nouvelle tentative {attempt + 1}/3 après une interruption…",
                    true));
                await Task.Delay(TimeSpan.FromSeconds(attempt * 2), cancellationToken);
            }
        }

        throw new HttpRequestException("Le téléchargement a échoué après trois tentatives.", lastError);
    }

    private async Task DownloadFileAsync(
        string url,
        string destination,
        string stage,
        IProgress<InstallerProgress>? progress,
        CancellationToken cancellationToken,
        double startPercent,
        double endPercent,
        string? notFoundMessage)
    {
        var partPath = destination + ".part";
        if (File.Exists(partPath)) File.Delete(partPath);

        using var response = await _httpClient.GetAsync(
            url,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound
            && notFoundMessage is not null)
        {
            throw new InvalidOperationException(notFoundMessage);
        }
        response.EnsureSuccessStatusCode();

        var totalBytes = response.Content.Headers.ContentLength;
        await using (var source = await response.Content.ReadAsStreamAsync(cancellationToken))
        await using (var destinationStream = new FileStream(
                         partPath,
                         FileMode.Create,
                         FileAccess.Write,
                         FileShare.None,
                         bufferSize: 1024 * 128,
                         useAsync: true))
        {
            var buffer = new byte[1024 * 128];
            long downloaded = 0;
            var stopwatch = Stopwatch.StartNew();
            while (true)
            {
                var count = await source.ReadAsync(buffer, cancellationToken);
                if (count == 0) break;

                await destinationStream.WriteAsync(buffer.AsMemory(0, count), cancellationToken);
                downloaded += count;

                var ratio = totalBytes is > 0 ? (double)downloaded / totalBytes.Value : 0;
                var megabytes = downloaded / 1024d / 1024d;
                var speed = megabytes / Math.Max(stopwatch.Elapsed.TotalSeconds, 0.1);
                var totalLabel = totalBytes is > 0
                    ? $" / {totalBytes.Value / 1024d / 1024d:0.0} Mo"
                    : "";
                progress?.Report(new InstallerProgress(
                    startPercent + ratio * (endPercent - startPercent),
                    stage,
                    $"{megabytes:0.0}{totalLabel} · {speed:0.0} Mo/s",
                    totalBytes is null));
            }

            await destinationStream.FlushAsync(cancellationToken);
        }

        File.Move(partPath, destination, overwrite: true);
    }

    private static async Task<string> ComputeSha256Async(
        string path,
        CancellationToken cancellationToken)
    {
        await using var stream = File.OpenRead(path);
        var hash = await SHA256.HashDataAsync(stream, cancellationToken);
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    public void Dispose() => _httpClient.Dispose();

    private static string? ReadBuildReleaseTag()
    {
        return Assembly.GetEntryAssembly()?
            .GetCustomAttributes<AssemblyMetadataAttribute>()
            .FirstOrDefault(attribute => attribute.Key == "YuzuCordReleaseTag")?.Value
            ?? Assembly.GetEntryAssembly()?
                .GetCustomAttributes<AssemblyMetadataAttribute>()
                .FirstOrDefault(attribute => attribute.Key == "YuzuctusVencordReleaseTag")?.Value
            ?? Assembly.GetEntryAssembly()?
                .GetCustomAttributes<AssemblyMetadataAttribute>()
                .FirstOrDefault(attribute => attribute.Key == "RandomFavoritesReleaseTag")?.Value;
    }

    private async Task<ReleaseAssets> ResolveReleaseAssetsAsync(
        CancellationToken cancellationToken)
    {
        var selectedTag = _releaseTag ?? Volatile.Read(ref _resolvedReleaseTag);
        if (selectedTag is not null)
            return BuildReleaseAssets(selectedTag);

        using var response = await _httpClient.GetAsync(ReleasesApiUrl, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var releases = await JsonSerializer.DeserializeAsync<GitHubRelease[]>(
            stream,
            cancellationToken: cancellationToken)
            ?? throw new InvalidDataException("La liste des releases YuzuCord est illisible.");
        var compatibleRelease = releases.FirstOrDefault(release =>
            release.Draft != true
            && IsValidReleaseTag(release.TagName)
            && RequiredReleaseAssets.All(requiredAsset =>
                release.Assets?.Any(asset => string.Equals(
                    asset.Name,
                    requiredAsset,
                    StringComparison.OrdinalIgnoreCase)) == true));

        if (compatibleRelease?.TagName is not { } compatibleTag)
        {
            throw new InvalidOperationException(
                "Aucune release YuzuCord installable n'est disponible sur GitHub. "
                + "Télécharge une release contenant les fichiers YuzuCordBundle.");
        }

        selectedTag = Interlocked.CompareExchange(
            ref _resolvedReleaseTag,
            compatibleTag,
            comparand: null) ?? compatibleTag;
        return BuildReleaseAssets(selectedTag);
    }

    private async Task<string> GetRequiredReleaseTextAsync(
        string url,
        string releaseTag,
        string assetName,
        CancellationToken cancellationToken)
    {
        using var response = await GetRequiredReleaseResponseAsync(
            url,
            releaseTag,
            assetName,
            cancellationToken);
        return await response.Content.ReadAsStringAsync(cancellationToken);
    }

    private async Task<HttpResponseMessage> GetRequiredReleaseResponseAsync(
        string url,
        string releaseTag,
        string assetName,
        CancellationToken cancellationToken)
    {
        var response = await _httpClient.GetAsync(url, cancellationToken);
        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            response.Dispose();
            throw new InvalidOperationException(BuildMissingAssetMessage(releaseTag, assetName));
        }

        try
        {
            response.EnsureSuccessStatusCode();
            return response;
        }
        catch
        {
            response.Dispose();
            throw;
        }
    }

    private static string? NormalizeReleaseTag(string? releaseTag)
    {
        if (string.IsNullOrWhiteSpace(releaseTag)
            || releaseTag.Equals("latest", StringComparison.OrdinalIgnoreCase)
            || releaseTag.Equals("preview", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        if (!IsValidReleaseTag(releaseTag))
            throw new ArgumentException("Le tag de release YuzuCord est invalide.", nameof(releaseTag));

        return releaseTag;
    }

    private static bool IsValidReleaseTag(string? releaseTag) =>
        !string.IsNullOrWhiteSpace(releaseTag)
        && Regex.IsMatch(
            releaseTag,
            "^v(?:[0-9]+\\.[0-9]+\\.[0-9]+(?:-beta\\.[0-9]+)?|[0-9]+-beta[0-9]+)$");

    private static ReleaseAssets BuildReleaseAssets(string releaseTag) => new(
        releaseTag,
        BuildReleaseAssetUrl(releaseTag, "YuzuCordBundle.zip"),
        BuildReleaseAssetUrl(releaseTag, "YuzuCordBundle.zip.sha256"),
        BuildReleaseAssetUrl(releaseTag, "YuzuCordBundle.manifest.json"));

    private static string BuildReleaseAssetUrl(string releaseTag, string assetName) =>
        $"{ReleaseDownloadBaseUrl}/{releaseTag}/{assetName}";

    private static string BuildMissingAssetMessage(string releaseTag, string assetName) =>
        $"La release YuzuCord {releaseTag} est incomplète : {assetName} est introuvable. "
        + "Télécharge de nouveau l'installateur depuis la dernière release GitHub.";

    private sealed record ReleaseAssets(
        string Tag,
        string BundleUrl,
        string ChecksumUrl,
        string ManifestUrl);

    private sealed class GitHubRelease
    {
        [JsonPropertyName("tag_name")]
        public string? TagName { get; init; }

        [JsonPropertyName("draft")]
        public bool? Draft { get; init; }

        [JsonPropertyName("assets")]
        public GitHubAsset[]? Assets { get; init; } = [];
    }

    private sealed class GitHubAsset
    {
        [JsonPropertyName("name")]
        public string? Name { get; init; }

        [JsonPropertyName("browser_download_url")]
        public string? DownloadUrl { get; init; }

        [JsonPropertyName("digest")]
        public string? Digest { get; init; }
    }
}
