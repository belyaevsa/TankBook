using Microsoft.Extensions.Options;

namespace Tankbook.Api.Rates;

/// <summary>
/// The clock that drives the demand-driven rates backfill (docs/SCHEMA.md
/// "Reference data -> Exchange rates"). Runs one pass at startup and then per
/// interval, each in a fresh DI scope. Registered only outside test hosts, so L2
/// tests drive <see cref="RateBackfillService.ProcessPendingAsync"/> directly
/// rather than racing a timer. A failed pass is logged and the next tick tries
/// again - a rates outage must not take the API down with it.
/// </summary>
public sealed class RateBackfillHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly RateOptions _options;
    private readonly ILogger<RateBackfillHostedService> _logger;

    public RateBackfillHostedService(
        IServiceScopeFactory scopeFactory,
        IOptions<RateOptions> options,
        ILogger<RateBackfillHostedService> logger)
    {
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        // One pass at startup, like the daily job (RV.7): a queue recorded before
        // the process started must be serviced without waiting out an interval.
        await RunOnePassAsync(stoppingToken);

        using var timer = new PeriodicTimer(_options.BackfillInterval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            await RunOnePassAsync(stoppingToken);
        }
    }

    internal async Task RunOnePassAsync(CancellationToken stoppingToken)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var backfill = scope.ServiceProvider.GetRequiredService<RateBackfillService>();
            await backfill.ProcessPendingAsync(stoppingToken);
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            return;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Rates backfill pass failed.");
        }
    }
}
