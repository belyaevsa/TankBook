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
        using var timer = new PeriodicTimer(_options.JobInterval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
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
}
