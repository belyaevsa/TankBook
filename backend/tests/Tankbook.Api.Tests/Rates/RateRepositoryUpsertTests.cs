using Npgsql;
using Tankbook.Api.Data;
using Tankbook.Api.Rates;

namespace Tankbook.Api.Tests.Rates;

/// <summary>
/// L2 tests for the RV.36 upsert rule (docs/SCHEMA.md "Reference data ->
/// Exchange rates"): a published row may supersede a <c>:carried-forward</c>
/// placeholder for the same (date, base, quote), but a published row never
/// overwrites another published row and a carried row never overwrites another
/// carried row. These three are one rule, not three - any one alone is not the
/// append-only guarantee, and a fix that lets anything overwrite anything passes
/// the positive case while silently destroying it. Runs against real Postgres
/// via Testcontainers, driving <see cref="RateRepository.UpsertAsync"/> directly.
/// </summary>
public class RateRepositoryUpsertTests : IClassFixture<PostgresFixture>
{
    private static readonly DateOnly Day = new(2026, 9, 3);

    private readonly PostgresFixture _fixture;

    public RateRepositoryUpsertTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static RateRepositoryUpsertTests()
    {
        DapperTypeHandlers.Register();
    }

    [SkippableFact]
    public async Task PublishedRow_SupersedesACarriedForwardPlaceholder_ForTheSameSlot()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();
        var repository = new RateRepository(db);

        await repository.UpsertAsync(
            new RateInsert(Day, "EUR", "USD", 1.10m, RateSources.Carried(RateSources.Ecb)),
            CancellationToken.None);
        await repository.UpsertAsync(
            new RateInsert(Day, "EUR", "USD", 1.15m, RateSources.Ecb),
            CancellationToken.None);

        var row = await ReadSingleAsync(db, Day, "EUR", "USD");
        Assert.Equal(1.15m, row.Rate);
        Assert.Equal(RateSources.Ecb, row.Source);
        Assert.False(RateSources.IsCarried(row.Source));
        Assert.False(row.Deleted);
    }

    [SkippableFact]
    public async Task PublishedRow_DoesNotOverwriteAnotherPublishedRow()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();
        var repository = new RateRepository(db);

        await repository.UpsertAsync(
            new RateInsert(Day, "EUR", "USD", 1.10m, RateSources.Ecb),
            CancellationToken.None);
        await repository.UpsertAsync(
            new RateInsert(Day, "EUR", "USD", 1.15m, RateSources.Ecb),
            CancellationToken.None);

        var row = await ReadSingleAsync(db, Day, "EUR", "USD");
        Assert.Equal(1.10m, row.Rate);
        Assert.Equal(RateSources.Ecb, row.Source);
        Assert.False(row.Deleted);
    }

    [SkippableFact]
    public async Task CarriedRow_DoesNotOverwriteAnotherCarriedRow()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();
        var repository = new RateRepository(db);

        await repository.UpsertAsync(
            new RateInsert(Day, "EUR", "USD", 1.10m, RateSources.Carried(RateSources.Ecb)),
            CancellationToken.None);
        await repository.UpsertAsync(
            new RateInsert(Day, "EUR", "USD", 1.15m, RateSources.Carried(RateSources.Ecb)),
            CancellationToken.None);

        var row = await ReadSingleAsync(db, Day, "EUR", "USD");
        Assert.Equal(1.10m, row.Rate);
        Assert.True(RateSources.IsCarried(row.Source));
        Assert.False(row.Deleted);
    }

    private async Task<NpgsqlConnection> OpenDatabaseAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    private static async Task<DbRate> ReadSingleAsync(NpgsqlConnection db, DateOnly date, string baseCurrency, string quote)
    {
        var rows = await db.QueryAsync<DbRate>(
            """
            SELECT date AS Date, base AS Base, quote AS Quote, rate AS Rate, source AS Source,
                   deleted_at IS NOT NULL AS Deleted
            FROM exchange_rates
            WHERE date = @Date AND base = @Base AND quote = @Quote AND deleted_at IS NULL
            """,
            new { Date = date, Base = baseCurrency, Quote = quote });
        return Assert.Single(rows.ToList());
    }

    private sealed record DbRate(DateOnly Date, string Base, string Quote, decimal Rate, string Source, bool Deleted);
}
