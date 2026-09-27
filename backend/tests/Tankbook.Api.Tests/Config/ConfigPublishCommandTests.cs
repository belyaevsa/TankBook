using Microsoft.Extensions.DependencyInjection;
using Npgsql;
using Tankbook.Api.Config;
using Tankbook.Api.Data;

namespace Tankbook.Api.Tests.Config;

/// <summary>
/// The operator's publish command (<c>--publish-config &lt;file&gt;</c>, PU.96):
/// the exit code is what a script or a person at the host acts on, so each
/// outcome is pinned to one - published 0, refused 1, no readable file 2 - with
/// the table checked behind it. Real Postgres, as the service's own tests.
/// </summary>
public class ConfigPublishCommandTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public ConfigPublishCommandTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    [SkippableFact]
    public async Task AValidNewerDocument_IsPublishedSigned_AndExitsZero()
    {
        await using var db = await NewMigratedDbAsync();
        var path = WriteDocument(ConfigTestData.Document(version: 2));
        var output = new StringWriter();

        var code = await ConfigPublishCommand.RunAsync(Services(db), path, output, new StringWriter(), CancellationToken.None);

        Assert.Equal(0, code);
        Assert.Contains("published config version 2", output.ToString(), StringComparison.Ordinal);
        var (document, signature) = await db.QuerySingleAsync<(string, string)>(
            "SELECT document::text, signature FROM config_documents WHERE version = 2");
        Assert.True(ConfigSigner.VerifyWithPublicKey(
            ConfigCanonicalizer.Canonicalize(document), signature, ConfigTestData.Signer.PublicKeyBase64));
    }

    [SkippableFact]
    public async Task ALowerVersion_IsRefused_ExitsOne_AndLeavesTheTable()
    {
        await using var db = await NewMigratedDbAsync();
        var services = Services(db);
        Assert.Equal(0, await ConfigPublishCommand.RunAsync(
            services, WriteDocument(ConfigTestData.Document(version: 3)), new StringWriter(), new StringWriter(),
            CancellationToken.None));
        var error = new StringWriter();

        var code = await ConfigPublishCommand.RunAsync(
            services, WriteDocument(ConfigTestData.Document(version: 2)), new StringWriter(), error, CancellationToken.None);

        Assert.Equal(1, code);
        Assert.Contains(nameof(ConfigPublishErrorKind.VersionNotMonotonic), error.ToString(), StringComparison.Ordinal);
        Assert.Equal(2, await db.QuerySingleAsync<int>("SELECT count(*) FROM config_documents"));
    }

    [SkippableFact]
    public async Task AMalformedDocument_IsRefusedBeforeSigning_AndExitsOne()
    {
        await using var db = await NewMigratedDbAsync();
        var invalid = ConfigTestData.Document(version: 2)
            .Replace("\"tier2OnDeviceLLM\":true,", "", StringComparison.Ordinal);
        var error = new StringWriter();

        var code = await ConfigPublishCommand.RunAsync(
            Services(db), WriteDocument(invalid), new StringWriter(), error, CancellationToken.None);

        Assert.Equal(1, code);
        Assert.Contains(nameof(ConfigPublishErrorKind.SchemaValidationFailed), error.ToString(), StringComparison.Ordinal);
        Assert.Equal(1, await db.QuerySingleAsync<int>("SELECT count(*) FROM config_documents"));
    }

    [SkippableFact]
    public async Task NoPathOrAnUnreadableFile_IsAUsageError()
    {
        await using var db = await NewMigratedDbAsync();
        var services = Services(db);

        Assert.Equal(ConfigPublishCommand.UsageError, await ConfigPublishCommand.RunAsync(
            services, null, new StringWriter(), new StringWriter(), CancellationToken.None));
        Assert.Equal(ConfigPublishCommand.UsageError, await ConfigPublishCommand.RunAsync(
            services, Path.Combine(Path.GetTempPath(), $"missing-{Guid.NewGuid():N}.json"),
            new StringWriter(), new StringWriter(), CancellationToken.None));
        Assert.Equal(1, await db.QuerySingleAsync<int>("SELECT count(*) FROM config_documents"));
    }

    [Fact]
    public void TheFlagTakesTheNextArgumentAsThePath()
    {
        Assert.True(ConfigPublishCommand.IsRequested(["--publish-config", "doc.json"], out var path));
        Assert.Equal("doc.json", path);
        Assert.True(ConfigPublishCommand.IsRequested(["--publish-config"], out var none));
        Assert.Null(none);
        Assert.False(ConfigPublishCommand.IsRequested(["--migrate"], out _));
    }

    private static IServiceProvider Services(NpgsqlConnection db)
    {
        var services = new ServiceCollection();
        services.AddLogging();
        services.AddSingleton<System.Data.IDbConnection>(db);
        services.AddScoped<ConfigRepository>();
        services.AddSingleton<ConfigSchemaValidator>();
        services.AddSingleton(ConfigTestData.Signer);
        services.AddScoped<ConfigPublishService>();
        return services.BuildServiceProvider();
    }

    private static string WriteDocument(string json)
    {
        var path = Path.Combine(Path.GetTempPath(), $"config-{Guid.NewGuid():N}.json");
        File.WriteAllText(path, json);
        return path;
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
