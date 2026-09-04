using Microsoft.Extensions.Options;

namespace Tankbook.Api.Llm;

/// <summary>
/// The timer that drives the ledger write queue's retry pass (docs/SECURITY.md
/// "The ledger write queue"). Same pattern as the purge jobs: one pass per
/// interval in a fresh DI scope, registered only outside test hosts, so L2 tests
/// drive <see cref="LlmLedgerRetryService.RetryDueAsync"/> directly rather than
/// racing a timer.
/// </summary>
public sealed class LlmLedgerRetryHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly LlmCallOptions _options;
    private readonly ILogger<LlmLedgerRetryHostedService> _logger;

    public LlmLedgerRetryHostedService(
        IServiceScopeFactory scopeFactory,
        IOptions<LlmCallOptions> options,
        ILogger<LlmLedgerRetryHostedService> logger)
    {
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(_options.RetryInterval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var retry = scope.ServiceProvider.GetRequiredService<LlmLedgerRetryService>();
                var result = await retry.RetryDueAsync(stoppingToken);

                if (result.Landed > 0 || result.Dropped > 0)
                {
                    _logger.LogInformation(
                        "Ledger retry pass completed: {Landed} rows landed, {Dropped} dropped.",
                        result.Landed,
                        result.Dropped);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ledger retry pass failed.");
            }
        }
    }
}
