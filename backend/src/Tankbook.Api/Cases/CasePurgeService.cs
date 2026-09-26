using Microsoft.Extensions.Options;

namespace Tankbook.Api.Cases;

/// <summary>
/// The 30-day case purge (hard rule 9: cases are kept 30 days). Deletes cases
/// past the retention cutoff - parts and index row - and nothing inside the
/// window. The timer lives in <see cref="CasePurgeHostedService"/>, registered
/// only outside test hosts; L2 tests call <see cref="PurgeDueCasesAsync"/>.
/// </summary>
public sealed class CasePurgeService
{
    private readonly CaseService _service;
    private readonly CaseOptions _options;
    private readonly TimeProvider _time;

    public CasePurgeService(CaseService service, IOptions<CaseOptions> options, TimeProvider time)
    {
        _service = service;
        _options = options.Value;
        _time = time;
    }

    public Task<int> PurgeDueCasesAsync(CancellationToken cancellationToken)
        => _service.PurgeDueAsync(_time.GetUtcNow() - _options.RetentionPeriod, cancellationToken);
}

/// <summary>The clock that drives the case purge: one pass per interval in a fresh DI scope.</summary>
public sealed class CasePurgeHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly CaseOptions _options;
    private readonly ILogger<CasePurgeHostedService> _logger;

    public CasePurgeHostedService(IServiceScopeFactory scopeFactory, IOptions<CaseOptions> options,
                                  ILogger<CasePurgeHostedService> logger)
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
                await scope.ServiceProvider.GetRequiredService<CasePurgeService>().PurgeDueCasesAsync(stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Case purge pass failed.");
            }
        }
    }
}
