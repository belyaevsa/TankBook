using Microsoft.Extensions.Options;

namespace Tankbook.Api.Import;

/// <summary>
/// The clock that drives the import purge job (docs/SECURITY.md "Import files at
/// rest"). Same pattern as the account purge: one pass per interval in a fresh
/// DI scope, registered only outside test hosts (Program.cs), so L2 tests drive
/// <see cref="ImportPurgeService.PurgeDueImportsAsync"/> directly instead of
/// racing a timer.
/// </summary>
public sealed class ImportPurgeHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ImportOptions _options;
    private readonly ILogger<ImportPurgeHostedService> _logger;

    public ImportPurgeHostedService(
        IServiceScopeFactory scopeFactory,
        IOptions<ImportOptions> options,
        ILogger<ImportPurgeHostedService> logger)
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
                var purge = scope.ServiceProvider.GetRequiredService<ImportPurgeService>();
                var purged = await purge.PurgeDueImportsAsync(stoppingToken);

                if (purged > 0)
                {
                    _logger.LogInformation(
                        "Import purge pass completed: {Imports} stored parses purged.",
                        purged);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Import purge pass failed.");
            }
        }
    }
}
