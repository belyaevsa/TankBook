using Npgsql;
using Tankbook.Api.Config;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// The publish path (docs/CONFIG.md version monotonicity + schema gate at
/// publish time). The database IS the subject here - the version primary key and
/// the "highest version" read are SQL - so these run against real Postgres via
/// Testcontainers (docs/TESTING.md standing rule).
/// </summary>
public class ConfigPublishServiceTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public ConfigPublishServiceTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task Publish_Version2AfterSeededVersion1_SucceedsAndSigns()
    {
        await using var db = await NewMigratedDbAsync();
        var service = NewPublishService(db);

        var result = await service.PublishAsync(ConfigTestData.Document(version: 2), CancellationToken.None);

        Assert.True(result.IsSuccess, result.Error.Detail);

        var rows = await db.QueryAsync<(int Version, string Signature)>("SELECT version, signature FROM config_documents ORDER BY version");
        var list = rows.ToList();
        Assert.Equal(2, list.Count);
        Assert.Equal(new[] { 1, 2 }, list.Select(r => r.Version).ToArray());

        // The published document is really signed: its signature verifies over
        // the canonical bytes with the published public key.
        var doc2 = await db.QuerySingleAsync<string>(
            "SELECT document::text FROM config_documents WHERE version = 2");
        Assert.True(ConfigSigner.VerifyWithPublicKey(
            ConfigCanonicalizer.Canonicalize(doc2), list[1].Signature, ConfigTestData.Signer.PublicKeyBase64));
    }

    [SkippableFact]
    public async Task Publish_SameVersionAgain_IsRefusedTyped_AndLeavesTheTableUnchanged()
    {
        await using var db = await NewMigratedDbAsync();
        var service = NewPublishService(db);

        var first = await service.PublishAsync(ConfigTestData.Document(version: 2), CancellationToken.None);
        Assert.True(first.IsSuccess);

        var again = await service.PublishAsync(ConfigTestData.Document(version: 2), CancellationToken.None);

        Assert.False(again.IsSuccess);
        Assert.Equal(ConfigPublishErrorKind.VersionNotMonotonic, again.Error.Kind);
        Assert.Contains("not higher", again.Error.Detail, StringComparison.OrdinalIgnoreCase);

        var count = await db.QuerySingleAsync<int>("SELECT count(*) FROM config_documents");
        Assert.Equal(2, count);
    }

    [SkippableFact]
    public async Task Publish_OlderVersionAfterHigher_IsRefused()
    {
        await using var db = await NewMigratedDbAsync();
        var service = NewPublishService(db);

        await service.PublishAsync(ConfigTestData.Document(version: 2), CancellationToken.None);
        var older = await service.PublishAsync(ConfigTestData.Document(version: 1), CancellationToken.None);

        Assert.False(older.IsSuccess);
        Assert.Equal(ConfigPublishErrorKind.VersionNotMonotonic, older.Error.Kind);
    }

    [SkippableFact]
    public async Task Publish_InvalidDocument_IsRefusedBeforeSigning_AndLeavesTheTableUnchanged()
    {
        await using var db = await NewMigratedDbAsync();
        var service = NewPublishService(db);

        // Missing a required field (tier2OnDeviceLLM).
        var invalid = ConfigTestData.Document(version: 2)
            .Replace("\"tier2OnDeviceLLM\":true,", "", StringComparison.Ordinal);

        var result = await service.PublishAsync(invalid, CancellationToken.None);

        Assert.False(result.IsSuccess);
        Assert.Equal(ConfigPublishErrorKind.SchemaValidationFailed, result.Error.Kind);

        var count = await db.QuerySingleAsync<int>("SELECT count(*) FROM config_documents");
        Assert.Equal(1, count);
    }

    [SkippableFact]
    public async Task Publish_NotJson_IsRefusedAsInvalidDocument()
    {
        await using var db = await NewMigratedDbAsync();
        var service = NewPublishService(db);

        var result = await service.PublishAsync("this is not json", CancellationToken.None);

        Assert.False(result.IsSuccess);
        Assert.Equal(ConfigPublishErrorKind.InvalidDocument, result.Error.Kind);
    }

    [SkippableFact]
    public async Task Publish_WithoutConfiguredSigningKey_IsRefusedTyped()
    {
        await using var db = await NewMigratedDbAsync();
        var service = new ConfigPublishService(
            new ConfigRepository(db),
            new ConfigSchemaValidator(),
            new ConfigSigner(null),
            Microsoft.Extensions.Logging.Abstractions.NullLogger<ConfigPublishService>.Instance);

        var result = await service.PublishAsync(ConfigTestData.Document(version: 2), CancellationToken.None);

        Assert.False(result.IsSuccess);
        Assert.Equal(ConfigPublishErrorKind.SigningKeyNotConfigured, result.Error.Kind);

        var count = await db.QuerySingleAsync<int>("SELECT count(*) FROM config_documents");
        Assert.Equal(1, count);
    }

    private ConfigPublishService NewPublishService(NpgsqlConnection db)
        => new(
            new ConfigRepository(db),
            new ConfigSchemaValidator(),
            ConfigTestData.Signer,
            Microsoft.Extensions.Logging.Abstractions.NullLogger<ConfigPublishService>.Instance);

    private async Task<NpgsqlConnection> NewMigratedDbAsync()
    {
        _fixture.RequireAvailable();
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }
}
