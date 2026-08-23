using Microsoft.Extensions.Logging;
using Npgsql;
using Tankbook.Api.Config;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// Selection behaviour for GET /v1/config (docs/CONFIG.md "Delivery"): serve the
/// highest published version whose notAfter is still in the future; if none is
/// valid, serve the latest anyway and log at WARN (clients reject an expired
/// document and fall back to bundled defaults, which is the designed behaviour).
/// The rows live in Postgres, so these run against a real database.
/// </summary>
public class ConfigExpirySelectionTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public ConfigExpirySelectionTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task ExpiredHigherVersion_ValidLowerVersion_ServesTheValidLowerVersion()
    {
        await using var db = await NewMigratedDbAsync();
        var logger = new CaptureLogger<ConfigReadService>();
        await ClearDocumentsAsync(db);

        // v2 is expired, v1 is still valid.
        await InsertDocumentAsync(db, version: 2, notAfterOffset: TimeSpan.FromDays(-1), publishedOffset: TimeSpan.FromDays(-1));
        await InsertDocumentAsync(db, version: 1, notAfterOffset: TimeSpan.FromDays(10), publishedOffset: TimeSpan.FromDays(-1));

        var service = new ConfigReadService(new ConfigRepository(db), logger);
        var served = await service.GetForServingAsync(CancellationToken.None);

        Assert.NotNull(served);
        Assert.Equal(1, served.Version);
        // No WARN: a valid document was found.
        Assert.False(logger.Any(LogLevel.Warning, "config.expired.fallback"));
    }

    [SkippableFact]
    public async Task AllVersionsExpired_ServesTheLatestAndLogsAtWarning()
    {
        await using var db = await NewMigratedDbAsync();
        var logger = new CaptureLogger<ConfigReadService>();
        await ClearDocumentsAsync(db);

        await InsertDocumentAsync(db, version: 2, notAfterOffset: TimeSpan.FromDays(-2), publishedOffset: TimeSpan.FromDays(-3));
        await InsertDocumentAsync(db, version: 1, notAfterOffset: TimeSpan.FromDays(-1), publishedOffset: TimeSpan.FromDays(-3));

        var service = new ConfigReadService(new ConfigRepository(db), logger);
        var served = await service.GetForServingAsync(CancellationToken.None);

        // The latest is served anyway, and the WARN case is exercised.
        Assert.NotNull(served);
        Assert.Equal(2, served.Version);
        Assert.True(logger.Any(LogLevel.Warning, "config.expired.fallback"));
    }

    [SkippableFact]
    public async Task HighestVersion_NotYetPublished_IsNotSelectedOverAValidOlderOne()
    {
        await using var db = await NewMigratedDbAsync();
        var logger = new CaptureLogger<ConfigReadService>();
        await ClearDocumentsAsync(db);

        // v2 is future-published (published_at in the future), v1 is valid now.
        await InsertDocumentAsync(db, version: 2, notAfterOffset: TimeSpan.FromDays(30), publishedOffset: TimeSpan.FromDays(1));
        await InsertDocumentAsync(db, version: 1, notAfterOffset: TimeSpan.FromDays(10), publishedOffset: TimeSpan.FromDays(-1));

        var service = new ConfigReadService(new ConfigRepository(db), logger);
        var served = await service.GetForServingAsync(CancellationToken.None);

        Assert.NotNull(served);
        Assert.Equal(1, served.Version);
        Assert.False(logger.Any(LogLevel.Warning, "config.expired.fallback"));
    }

    [SkippableFact]
    public async Task EmptyTable_ReturnsNull()
    {
        await using var db = await NewMigratedDbAsync();
        var logger = new CaptureLogger<ConfigReadService>();
        await ClearDocumentsAsync(db);

        await db.ExecuteAsync("DELETE FROM config_documents");

        var service = new ConfigReadService(new ConfigRepository(db), logger);
        var served = await service.GetForServingAsync(CancellationToken.None);

        Assert.Null(served);
    }

    private static async Task ClearDocumentsAsync(NpgsqlConnection db)
        => await db.ExecuteAsync("DELETE FROM config_documents");

    private static async Task InsertDocumentAsync(
        NpgsqlConnection db,
        int version,
        TimeSpan notAfterOffset,
        TimeSpan publishedOffset)
    {
        var document = "{\"version\":" + version.ToString(System.Globalization.CultureInfo.InvariantCulture) + "}";
        await db.ExecuteAsync(
            """
            INSERT INTO config_documents (version, document, signature, issued_at, not_after, published_at)
            VALUES (@Version, @Document::jsonb, '', now() - interval '30 days', now() + @NotAfterOffset, now() + @PublishedOffset)
            """,
            new
            {
                Version = version,
                Document = document,
                NotAfterOffset = notAfterOffset,
                PublishedOffset = publishedOffset,
            });
    }

    private async Task<NpgsqlConnection> NewMigratedDbAsync()
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }
}
