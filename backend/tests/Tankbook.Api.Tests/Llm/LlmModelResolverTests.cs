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
        await db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'ghost-model')");

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

        // No llm_settings row at all - the compiled default is the only model.
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
        await db.ExecuteAsync("INSERT INTO llm_settings (kind, model_id) VALUES ('receipt', 'vision-receipt'), ('pump', 'vision-pump')");

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
