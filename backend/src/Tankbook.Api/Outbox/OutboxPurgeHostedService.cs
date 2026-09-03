using Microsoft.Extensions.Options;

namespace Tankbook.Api.Outbox;

/// <summary>
/// The clock that drives the delivery-outbox retention purge (docs/SECURITY.md
/// "The delivery outbox"). Same pattern as the account, import and call-ledger
/// purges: one pass per interval in a fresh DI scope, registered only outside
/// test hosts, so L2 tests drive <see cref="OutboxService.PurgeDueAsync"/>
/// directly rather than racing a timer.
/// </summary>
public sealed class OutboxPurgeHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly OutboxOptions _options;
    private readonly ILogger<OutboxPurgeHostedService> _logger;

    public OutboxPurgeHostedService(
        IServiceScopeFactory scopeFactory,
        IOptions<OutboxOptions> options,
        ILogger<OutboxPurgeHostedService> logger)
    {
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(_options.PurgeInterval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var service = scope.ServiceProvider.GetRequiredService<OutboxService>();
                var purged = await service.PurgeDueAsync(stoppingToken);

                if (purged > 0)
                {
                    _logger.LogInformation(
                        "Delivery-outbox purge pass completed: {Rows} rows removed.",
                        purged);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Delivery-outbox purge pass failed.");
            }
        }
    }
}
