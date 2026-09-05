using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;
using Npgsql;
using Tankbook.Api.Data;
using Tankbook.Api.Rates;

namespace Tankbook.Api.Tests.Rates;

/// <summary>
/// RV.60: does the rate backfill actually drain? The production log shows two
/// passes five minutes apart reading `rates.backfill Processed=50 Published=0
/// CarriedForward=0 SourcesFailed=0 Answered=50` - the steady-state signature
/// RV.50 existed to remove, but also exactly what a large backlog of genuinely
/// unfillable dates looks like while it drains 50 at a time. The log alone cannot
/// tell the two apart; the queue table can. These tests seed a backlog and assert
/// the PENDING COUNT at each pass (never `Published` - a pass that publishes
/// nothing but correctly answers rows is doing its job), against real Postgres
/// via Testcontainers. The feed is a recording double; the repository, the
/// upsert, the answer markers and the settle are all real (docs/TESTING.md
/// "mock the boundary").
/// </summary>
public class RateBackfillDrainTests : IClassFixture<PostgresFixture>
{
    private const string Base = "EUR";

    private readonly PostgresFixture _fixture;

    public RateBackfillDrainTests(PostgresFixture fixture)
    {
        _fixture = fixture;
    }

    static RateBackfillDrainTests()
    {
        DapperTypeHandlers.Register();
    }

    [SkippableFact]
    public async Task ALargeBacklogOfUnfillableDates_DrainsPassOverPass_UntilTheQueueReachesZero()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // The production shape that produced the RV.60 log pair: one feed family
        // (cis) already published a live row for every date, the other (ecb)
        // structurally answers empty for every date and has no earlier anchor
        // anywhere (RV.50). Each queued date therefore resolves to exactly one
        // answered row - Processed = Answered = 50 on every full pass, Published =
        // 0 - and that is precisely the signature the log showed twice while it
        // could not say whether the queue was draining. Here the COUNT is queried
        // directly, not inferred from the pass result.
        var first = new DateOnly(2026, 1, 1);
        var last = first.AddDays(119); // 120 dates - 2 full batches of 50 plus a 20-date tail

        var ecb = new RecordingRateFeed(RateSources.Ecb); // answers empty: structurally cannot fill a past date
        var cis = new RecordingRateFeed(RateSources.Cis); // covered for every date below, so never asked
        var backfill = BuildBackfill(db, cis, ecb);

        await SeedPublishedAsync(db, first, last, RateSources.Cis);

        // The pack trigger queues the whole span (RV.32: the request is the demand).
        Assert.Equal(120, await backfill.RecordRequestAsync(first, last, Base, CancellationToken.None));

        // Pass 1 - the log line RV.60 saw, verbatim, and the queue drops by a full batch.
        var pass1 = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(50, pass1.Processed);
        Assert.Equal(0, pass1.Published);
        Assert.Equal(0, pass1.CarriedForward);
        Assert.Equal(0, pass1.SourcesFailed);
        Assert.Equal(50, pass1.Answered);
        Assert.Equal(70, await CountAsync(db, "rate_backfill"));

        // Pass 2 - identical again, and the queue keeps dropping.
        var pass2 = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(50, pass2.Processed);
        Assert.Equal(0, pass2.Published);
        Assert.Equal(50, pass2.Answered);
        Assert.Equal(20, await CountAsync(db, "rate_backfill"));

        // Pass 3 - the tail, smaller than the batch, and the queue reaches ZERO.
        var pass3 = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(20, pass3.Processed);
        Assert.Equal(20, pass3.Answered);
        Assert.Equal(0, await CountAsync(db, "rate_backfill"));

        // Every date resolved to a stored answered marker - the queue is empty and
        // the work is not lost, it is remembered as answered-empty (RV.50).
        Assert.Equal(120, await CountAsync(db, "rate_backfill_answered"));
    }

    [SkippableFact]
    public async Task AnAnsweredEmptyRow_IsNeverRetriedByLaterPassesOrRequests()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // A date no feed can fill: the feed answers empty, no document anywhere.
        var feed = new RecordingRateFeed(RateSources.Cis);
        feed.SetHandler((_, _) => []);
        var backfill = BuildBackfill(db, feed);

        var day = new DateOnly(2026, 9, 2);

        // The pack enqueues it once and the first pass answers it empty.
        Assert.Equal(1, await backfill.RecordRequestAsync(day, day, Base, CancellationToken.None));
        var first = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(1, first.Answered);
        Assert.Equal(0, await CountAsync(db, "rate_backfill"));

        // Five more passes with no demand: the row does NOT reappear - the backfill
        // never re-enqueues on its own, so there is no self-sustaining retry loop.
        for (var pass = 0; pass < 5; pass++)
        {
            var result = await backfill.ProcessPendingAsync(CancellationToken.None);
            Assert.Equal(0, result.Processed);
            Assert.Equal(0, await CountAsync(db, "rate_backfill"));
        }

        // And a device re-asking for the SAME date (its next refresh) is answered
        // from the marker: nothing is enqueued, the row is not retried.
        Assert.Equal(0, await backfill.RecordRequestAsync(day, day, Base, CancellationToken.None));
        Assert.Equal(0, await CountAsync(db, "rate_backfill"));

        // The defined terminal outcome: a stored answered marker that survives.
        Assert.Equal(1, await CountAsync(db, "rate_backfill_answered"));
    }

    [SkippableFact]
    public async Task AFeedThatThrows_IsNotAnswered_AndItsDateIsRetriedOnTheNextDemand()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // The other failure shape: the feed throws (down/error). It is deliberately
        // NOT answered-empty - answering it would hide the outage (RV.15) - and the
        // pass settles the date without a marker, so the next pack request for it
        // enqueues it again. The retry is bounded by demand, not by a count.
        var feed = new RecordingRateFeed(RateSources.Cis);
        feed.SetHandler((_, _) => throw new InvalidOperationException("feed down"));
        var backfill = BuildBackfill(db, feed);

        var day = new DateOnly(2026, 9, 2);
        Assert.Equal(1, await backfill.RecordRequestAsync(day, day, Base, CancellationToken.None));

        var failing = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(1, failing.Processed);
        Assert.Equal(1, failing.SourcesFailed);
        Assert.Equal(0, failing.Answered);
        Assert.Equal(0, failing.Published);
        // Settled but not answered: gone from the queue, remembered nowhere.
        Assert.Equal(0, await CountAsync(db, "rate_backfill"));
        Assert.Equal(0, await CountAsync(db, "rate_backfill_answered"));

        // A second pass on the backfill's own clock does NOT retry it (no demand).
        var idle = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(0, idle.Processed);

        // The next device request for the date re-enqueues it (not answered-empty).
        Assert.Equal(1, await backfill.RecordRequestAsync(day, day, Base, CancellationToken.None));

        // The feed recovers; the retry publishes instead of answering empty.
        feed.SetHandler((_, _) => [new RateQuote("RUB", 90.0m)]);
        var recovered = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(1, recovered.Published);
        Assert.Equal(0, recovered.SourcesFailed);
        Assert.Equal(0, await CountAsync(db, "rate_backfill"));

        var rows = await ReadRatesAsync(db, Base);
        Assert.Contains(rows, r => r.Date == day && r.Quote == "RUB" && r.Rate == 90.0m && r.Source == RateSources.Cis);
    }

    [SkippableFact]
    public async Task ABacklogLargerThanTheBatchCap_TakesExactlyTheExpectedNumberOfPasses()
    {
        _fixture.RequireAvailable();
        await using var db = await OpenDatabaseAsync();

        // Pins the batch cap: a backlog larger than BackfillBatchSize is fetched in
        // capped oldest-first chunks, a partial remainder clears on the final pass,
        // and a pass after that is idle. A future change that silently stalls the
        // queue (or that ignores the cap and drains everything in one burst) moves
        // these numbers and this test goes red.
        var feed = new RecordingRateFeed(RateSources.Cis);
        feed.SetHandler((_, _) => []);
        var backfill = BuildBackfill(db, batchSize: 20, feed);

        var first = new DateOnly(2026, 5, 1);
        var last = first.AddDays(54); // 55 dates = 2 x 20 + a 15-date remainder
        Assert.Equal(55, await backfill.RecordRequestAsync(first, last, Base, CancellationToken.None));

        var pass1 = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(20, pass1.Processed);
        Assert.Equal(35, await CountAsync(db, "rate_backfill"));

        var pass2 = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(20, pass2.Processed);
        Assert.Equal(15, await CountAsync(db, "rate_backfill"));

        // The remainder - smaller than the cap - clears on the final pass.
        var pass3 = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(15, pass3.Processed);
        Assert.Equal(0, await CountAsync(db, "rate_backfill"));

        var pass4 = await backfill.ProcessPendingAsync(CancellationToken.None);
        Assert.Equal(0, pass4.Processed);
        Assert.Equal(55, await CountAsync(db, "rate_backfill_answered"));
    }

    private async Task<NpgsqlConnection> OpenDatabaseAsync()
    {
        var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);
        return db;
    }

    private static RateBackfillService BuildBackfill(NpgsqlConnection db, params IRateFeed[] feeds)
        => BuildBackfill(db, batchSize: 50, feeds);

    private static RateBackfillService BuildBackfill(NpgsqlConnection db, int batchSize, params IRateFeed[] feeds)
    {
        var repository = new RateRepository(db);
        var options = Microsoft.Extensions.Options.Options.Create(new RateOptions
        {
            BaseCurrencies = [Base],
            CarryBackWindowDays = 14,
            BackfillBatchSize = batchSize,
        });
        return new RateBackfillService(repository, feeds, options, NullLogger<RateBackfillService>.Instance);
    }

    private static async Task SeedPublishedAsync(NpgsqlConnection db, DateOnly from, DateOnly to, string source)
    {
        var repository = new RateRepository(db);
        for (var day = from; day <= to; day = day.AddDays(1))
        {
            await repository.UpsertAsync(new RateInsert(day, Base, "RUB", 90.0m, source), CancellationToken.None);
        }
    }

    private static async Task<int> CountAsync(NpgsqlConnection db, string table)
        => await db.QuerySingleAsync<int>($"SELECT count(*) FROM {table}");

    private static async Task<List<DbRate>> ReadRatesAsync(NpgsqlConnection db, string baseCurrency)
    {
        var rows = await db.QueryAsync<DbRate>(
            """
            SELECT date AS Date, base AS Base, quote AS Quote, rate AS Rate, source AS Source,
                   deleted_at IS NOT NULL AS Deleted
            FROM exchange_rates
            WHERE base = @Base
            ORDER BY date, quote
            """,
            new { Base = baseCurrency });
        return rows.ToList();
    }

    private sealed record DbRate(DateOnly Date, string Base, string Quote, decimal Rate, string Source, bool Deleted);
}
