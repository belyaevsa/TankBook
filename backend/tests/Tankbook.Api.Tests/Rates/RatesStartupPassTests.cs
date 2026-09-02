using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging.Abstractions;
using Npgsql;
using Tankbook.Api.Data;
using Tankbook.Api.Rates;
using Xunit;

namespace Tankbook.Api.Tests.Rates;

/// <summary>
/// The rates job runs once at STARTUP, not only on the timer (RV.7).
/// </summary>
/// <remarks>
/// `PeriodicTimer.WaitForNextTickAsync` waits a full interval before its first
/// tick, so with the default 6-hour interval there was no pass for six hours
/// after a start - and every deploy restarts the process and resets that clock.
/// Deploying more often than six-hourly meant the job NEVER ran, which is what
/// production showed: `/v1/rates` served a correctly-shaped, permanently empty
/// pack, and nothing looked wrong because the endpoint answered 200.
///
/// The test drives the hosted service with a LONG interval on purpose. If the
/// startup pass were removed, no tick could arrive within the test's lifetime,
/// so this fails by timing out on the assertion rather than passing by accident
/// on a fast timer.
/// </remarks>
public class RatesStartupPassTests : IClassFixture<PostgresFixture>
{
    private readonly PostgresFixture _fixture;

    public RatesStartupPassTests(PostgresFixture fixture) => _fixture = fixture;

    [SkippableFact]
    public async Task TheJobRunsOnceAtStartupWithoutWaitingForATick()
    {
        _fixture.RequireAvailable();
        await using var db = await _fixture.CreateDatabaseAsync();
        await db.OpenAsync();
        await SchemaMigrator.ApplyPendingAsync(db);

        var feed = new RecordingRateFeed(RateSources.Ecb);
        var calls = 0;
        feed.SetHandler((_, _) =>
        {
            calls++;
            return [new RateQuote("USD", 1.10m)];
        });
        var clock = new MutableTimeProvider(new DateTimeOffset(2026, 9, 2, 12, 0, 0, TimeSpan.Zero));

        var services = new ServiceCollection();
        services.AddScoped(_ => new RateRepository(db));
        services.AddScoped<IRateFeed>(_ => feed);
        services.AddScoped(sp => new RatesJobService(
            sp.GetRequiredService<RateRepository>(),
            [feed],
            Microsoft.Extensions.Options.Options.Create(new RateOptions { BaseCurrencies = ["EUR"] }),
            NullLogger<RatesJobService>.Instance,
            clock));
        var provider = services.BuildServiceProvider();

        // A 24-hour interval: nothing can tick during this test.
        var hosted = new RatesHostedService(
            provider.GetRequiredService<IServiceScopeFactory>(),
            Microsoft.Extensions.Options.Options.Create(new RateOptions { JobIntervalMinutes = 24 * 60, BaseCurrencies = ["EUR"] }),
            NullLogger<RatesHostedService>.Instance);

        // Drive the SERVICE, not the pass. Calling RunOnePassAsync directly
        // would only prove that method works - and it did: with the startup call
        // deleted from ExecuteAsync, that version of this test still passed. A
        // test that cannot fail for the reason it exists is worse than none,
        // because it looks like the gap is closed.
        //
        // StartAsync runs ExecuteAsync. The interval is 24 hours, so no tick can
        // arrive; if the startup pass is removed, the feed is never reached and
        // this fails.
        await hosted.StartAsync(CancellationToken.None);
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (calls == 0 && DateTime.UtcNow < deadline)
        {
            await Task.Delay(50);
        }
        await hosted.StopAsync(CancellationToken.None);

        // The claim under test is that a pass HAPPENS without waiting out an
        // interval - reaching the feed proves that, and it is the whole of RV.7.
        // What the pass then writes (publication, weekend carry-forward,
        // append-only corrections) is RatesJobTests' subject and is covered
        // there; asserting it again here would couple this test to the job's
        // date arithmetic for no extra coverage.
        Assert.True(calls > 0, "the startup pass never reached the feed - the job only runs on the timer");
    }
}
