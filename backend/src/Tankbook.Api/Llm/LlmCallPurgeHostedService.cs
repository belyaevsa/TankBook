using Microsoft.Extensions.Options;

namespace Tankbook.Api.Llm;

/// <summary>
/// The clock that drives the call-ledger content purge (docs/SECURITY.md "LLM
/// call ledger"). Same pattern as the account and import purges: one pass per
/// interval in a fresh DI scope, registered only outside test hosts, so L2 tests
/// drive <see cref="LlmCallPurgeService.PurgeDueAsync"/> directly rather than
/// racing a timer.
/// </summary>
public sealed class LlmCallPurgeHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly LlmCallOptions _options;
    private readonly ILogger<LlmCallPurgeHostedService> _logger;

    public LlmCallPurgeHostedService(
        IServiceScopeFactory scopeFactory,
        IOptions<LlmCallOptions> options,
        ILogger<LlmCallPurgeHostedService> logger)
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
                var purge = scope.ServiceProvider.GetRequiredService<LlmCallPurgeService>();
                var purged = await purge.PurgeDueAsync(stoppingToken);

                if (purged > 0)
                {
                    _logger.LogInformation(
                        "LLM call-ledger purge pass completed: {Calls} calls had content removed.",
                        purged);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "LLM call-ledger purge pass failed.");
            }
        }
    }
}
