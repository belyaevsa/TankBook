using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Npgsql;
using Tankbook.Api.Data;
using Tankbook.Api.Llm;

namespace Tankbook.Api.Tests.Llm;

/// <summary>
/// L2 tests for the model-choice resolution (migration 014, RV.34) against real
/// Postgres via Testcontainers. The resolver must degrade, never throw: a
/// missing setting row or an unknown model id falls back to the compiled
/// default and logs the fallback at Warning, so one bad DB row cannot take
/// cloud extraction down for everyone. Per-kind resolution keeps receipt and
/// pump display on their own models.
/// </summary>
public class LlmModelResolverTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public LlmModelResolverTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static LlmModelResolverTests()
    {
        DapperTypeHandlers.Register();
    }

    [SkippableFact]
    public async Task UnknownModelId_FallsBackToCompiledDefault_AndLogsWarning()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);

        await SeedModelAsync(db, "compiled-default", "default-vendor", 0.0000025m, 0.00001m);
        await db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'ghost-model') ON CONFLICT (kind) DO UPDATE SET model_id = EXCLUDED.model_id");

        var (resolver, writer) = BuildResolver(db, "compiled-default");
        var choice = await resolver.ResolveAsync("receipt", CancellationToken.None);

        // The unknown id did not throw; it resolved to the compiled default.
        Assert.Equal("compiled-default", choice.ModelId);
        Assert.Equal("default-vendor", choice.Vendor);
        Assert.True(choice.IsFallback);

        // And the fallback is visible: a Warning line naming the reason.
        Assert.Contains(writer.Lines, l =>
            l.Contains("llm.model_fallback", StringComparison.Ordinal) &&
            l.Contains("\"level\":\"Warning\"", StringComparison.Ordinal) &&
            l.Contains("unknown_model", StringComparison.Ordinal));
    }

    [SkippableFact]
    public async Task MissingSettingRow_FallsBackToCompiledDefault_ExtractionStillWorks()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);

        // No llm_settings row for this kind - the compiled default is the only
        // model. Migration 018 ships a production baseline row for every kind,
        // so this test must DELETE it to reach the state it is about: "the
        // operator has not chosen a model". Relying on an empty table would be
        // testing a state that no longer ships.
        await db.ExecuteAsync("DELETE FROM llm_settings WHERE kind = 'receipt'");
        await SeedModelAsync(db, "compiled-default", "default-vendor", 0.0000025m, 0.00001m);

        var (resolver, writer) = BuildResolver(db, "compiled-default");
        var choice = await resolver.ResolveAsync("receipt", CancellationToken.None);

        // A usable choice came back (priced, named), so extraction proceeds.
        Assert.Equal("compiled-default", choice.ModelId);
        Assert.Equal(0.0000025m, choice.InputPricePerToken);
        Assert.True(choice.IsFallback);

        Assert.Contains(writer.Lines, l =>
            l.Contains("llm.model_fallback", StringComparison.Ordinal) &&
            l.Contains("\"level\":\"Warning\"", StringComparison.Ordinal) &&
            l.Contains("no_setting", StringComparison.Ordinal));
    }

    [SkippableFact]
    public async Task PerKindResolution_DiffersBetweenReceiptAndPump()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);

        await SeedModelAsync(db, "vision-receipt", "vendor-a", 0.0000025m, 0.00001m);
        await SeedModelAsync(db, "vision-pump", "vendor-b", 0.000003m, 0.000012m);
        await db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'vision-receipt'), ('pump', 'vision-pump') ON CONFLICT (kind) DO UPDATE SET model_id = EXCLUDED.model_id");

        var (resolver, _) = BuildResolver(db, "compiled-default");

        var receipt = await resolver.ResolveAsync("receipt", CancellationToken.None);
        var pump = await resolver.ResolveAsync("pump", CancellationToken.None);

        // Each kind resolves to its own model - not a shared global scalar.
        Assert.Equal("vision-receipt", receipt.ModelId);
        Assert.Equal("vendor-a", receipt.Vendor);
        Assert.False(receipt.IsFallback);
        Assert.Equal("vision-pump", pump.ModelId);
        Assert.Equal("vendor-b", pump.Vendor);
        Assert.False(pump.IsFallback);
        Assert.NotEqual(receipt.ModelId, pump.ModelId);
    }

    /// The 018 seed is only useful if it actually RESOLVES - a seeded row that
    /// the resolver never reaches is a comment with a database bill. Every
    /// extraction kind must land on the vision model (they all send an image, so
    /// a text model physically cannot serve them), and the prices must be the
    /// published OpenRouter rates rather than zero, because RV.33's ledger
    /// multiplies them: a zero here is a cost column that silently reads $0 for
    /// every call ever made.
    [SkippableTheory]
    [InlineData("receipt")]
    [InlineData("pump")]
    [InlineData("chargeScreenshot")]
    [InlineData("invoice")]
    public async Task TheSeededBaseline_ResolvesEveryKindToThePricedVisionModel(string kind)
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);

        // Nothing seeded by the test: this is migration 018's own baseline.
        var (resolver, _) = BuildResolver(db, "compiled-default");
        var choice = await resolver.ResolveAsync(kind, CancellationToken.None);

        Assert.Equal("deepseek-v4-flash-vision-exp", choice.ModelId);
        Assert.Equal("deepseek", choice.Vendor);
        Assert.False(choice.IsFallback, $"{kind} must resolve from the seed, not fall back");

        // The published OpenRouter rates, per token: $0.22 / $0.66 per 1M.
        Assert.Equal(0.0000002200m, choice.InputPricePerToken);
        Assert.Equal(0.0000006600m, choice.OutputPricePerToken);
    }

    private static Task SeedModelAsync(NpgsqlConnection db, string modelId, string vendor, decimal inputPrice, decimal outputPrice)
        => db.ExecuteAsync(
            """
            INSERT INTO llm_models (model_id, vendor, input_price, output_price, currency, context_window, supports_thinking, effective_from)
            VALUES (@model, @vendor, @input, @output, 'USD', 128000, false, '2026-09-01')
            """,
            new { model = modelId, vendor, input = inputPrice, output = outputPrice });

    private static (LlmModelResolver Resolver, InMemoryLogWriter Writer) BuildResolver(
        NpgsqlConnection db,
        string compiledModelId)
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var logger = services.GetRequiredService<ILogger<LlmModelResolver>>();
        var options = Microsoft.Extensions.Options.Options.Create(new LlmGatewayOptions { ModelId = compiledModelId });

        var repository = new LlmModelRepository(db);
        var resolver = new LlmModelResolver(repository, options, logger, new MutableTimeProvider(new DateTimeOffset(2026, 9, 3, 12, 0, 0, TimeSpan.Zero)));
        return (resolver, writer);
    }
}
