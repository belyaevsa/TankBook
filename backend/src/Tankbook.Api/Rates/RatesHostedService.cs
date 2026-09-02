using Microsoft.Extensions.Options;

namespace Tankbook.Api.Rates;

/// <summary>
/// The clock that drives the daily rates job (docs/SCHEMA.md "Reference data ->
/// Exchange rates"). Runs one pass per interval in a fresh DI scope, so the
/// scoped <see cref="RatesJobService"/> always sees its own connection.
/// Registered only outside test hosts (Program.cs), so L2 tests drive
/// <see cref="RatesJobService.RunAsync"/> directly instead of racing a timer.
/// </summary>
public sealed class RatesHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly RateOptions _options;
    private readonly ILogger<RatesHostedService> _logger;

    public RatesHostedService(
        IServiceScopeFactory scopeFactory,
        IOptions<RateOptions> options,
        ILogger<RatesHostedService> logger)
    {
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // ONE PASS AT STARTUP, before the timer (RV.7, 2026-09-03).
        //
        // `PeriodicTimer.WaitForNextTickAsync` waits a full interval before its
        // first tick, so with a 6-hour interval there was no pass for six hours
        // after a start - and every deploy restarts the process and resets the
        // clock. Deploy more often than six-hourly and the job NEVER runs, which
        // is what happened: `/v1/rates` served a correctly-shaped, permanently
        // empty pack in production, and nothing looked wrong because the
        // endpoint answered 200.
        //
        // The pass is idempotent (the job's own doc comment says the interval is
        // "a liveness knob, not a correctness one"), so running one extra time
        // at boot costs a query and removes the dependence on uptime.
        await RunOnePassAsync(stoppingToken);

        using var timer = new PeriodicTimer(_options.JobInterval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            await RunOnePassAsync(stoppingToken);
        }
    }

    /// <summary>
    /// One idempotent pass, in its own DI scope. Shared by the startup pass and
    /// the timer so the two cannot drift, and it never throws: a failed pass is
    /// logged and the next tick tries again, because a rates outage must not
    /// take the API down with it.
    /// </summary>
    internal async Task RunOnePassAsync(CancellationToken stoppingToken)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var job = scope.ServiceProvider.GetRequiredService<RatesJobService>();
            await job.RunAsync(stoppingToken);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            return;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Rates pass failed.");
        }
    }
}
