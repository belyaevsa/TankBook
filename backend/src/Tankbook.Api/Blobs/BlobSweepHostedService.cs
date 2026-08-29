using Microsoft.Extensions.Options;

namespace Tankbook.Api.Blobs;

/// <summary>
/// The clock that drives the orphan sweep job (docs/PRACTICES.md S11, PR.18).
/// Same pattern as the account and import purges: one pass per interval in a
/// fresh DI scope, registered only outside test hosts (Program.cs), so L2 tests
/// drive <see cref="BlobSweepService.SweepAllAsync"/> directly instead of racing
/// a timer.
/// </summary>
public sealed class BlobSweepHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly BlobOptions _options;
    private readonly ILogger<BlobSweepHostedService> _logger;

    public BlobSweepHostedService(
        IServiceScopeFactory scopeFactory,
        IOptions<BlobOptions> options,
        ILogger<BlobSweepHostedService> logger)
    {
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(_options.SweepInterval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var sweep = scope.ServiceProvider.GetRequiredService<BlobSweepService>();
                var swept = await sweep.SweepAllAsync(stoppingToken);

                if (swept > 0)
                {
                    _logger.LogInformation(
                        "Blob sweep pass completed: {Blobs} orphaned blobs removed.",
                        swept);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Blob sweep pass failed.");
            }
        }
    }
}
