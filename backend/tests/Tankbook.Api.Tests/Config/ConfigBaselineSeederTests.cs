using Microsoft.Extensions.Logging.Abstractions;
using Npgsql;
using Tankbook.Api.Config;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// Migration 003 seeds the baseline config document with an EMPTY signature
/// (SQL cannot compute Ed25519); ConfigBaselineSeeder completes it at startup.
/// This handoff is what makes GET /v1/config serve a document clients can
/// verify, so it is tested against real Postgres.
/// </summary>
public class ConfigBaselineSeederTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public ConfigBaselineSeederTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task SeedAsync_SignsTheMigrationSeededBaseline()
    {
        await using var db = await NewMigratedDbAsync();

        // Migration 003 leaves version 1 unsigned.
        var before = await db.QuerySingleAsync<string>(
            "SELECT signature FROM config_documents WHERE version = 1");
        Assert.Equal(string.Empty, before);

        await ConfigBaselineSeeder.SeedAsync(
            db, ConfigTestData.Signer, new ConfigSchemaValidator(), NullLogger.Instance, CancellationToken.None);

        var (document, signature) = await db.QuerySingleAsync<(string, string)>(
            "SELECT document::text, signature FROM config_documents WHERE version = 1");
        Assert.False(string.IsNullOrWhiteSpace(signature));
        Assert.True(ConfigSigner.VerifyWithPublicKey(
            ConfigCanonicalizer.Canonicalize(document), signature, ConfigTestData.Signer.PublicKeyBase64));
    }

    [SkippableFact]
    public async Task SeedAsync_RunningTwice_IsANoOp()
    {
        await using var db = await NewMigratedDbAsync();

        await ConfigBaselineSeeder.SeedAsync(
            db, ConfigTestData.Signer, new ConfigSchemaValidator(), NullLogger.Instance, CancellationToken.None);
        var first = await db.QuerySingleAsync<string>(
            "SELECT signature FROM config_documents WHERE version = 1");

        await ConfigBaselineSeeder.SeedAsync(
            db, ConfigTestData.Signer, new ConfigSchemaValidator(), NullLogger.Instance, CancellationToken.None);
        var second = await db.QuerySingleAsync<string>(
            "SELECT signature FROM config_documents WHERE version = 1");

        Assert.Equal(first, second);
        Assert.NotEqual(string.Empty, second);
    }

    [SkippableFact]
    public async Task SeedAsync_WithNoConfiguredSigningKey_LeavesTheRowUnsigned()
    {
        await using var db = await NewMigratedDbAsync();

        await ConfigBaselineSeeder.SeedAsync(
            db, new ConfigSigner(null), new ConfigSchemaValidator(), NullLogger.Instance, CancellationToken.None);

        var signature = await db.QuerySingleAsync<string>(
            "SELECT signature FROM config_documents WHERE version = 1");
        Assert.Equal(string.Empty, signature);
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
