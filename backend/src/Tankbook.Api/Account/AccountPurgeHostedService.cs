using Microsoft.Extensions.Options;

namespace Tankbook.Api.Account;

/// <summary>
/// The clock that drives the account purge job (docs/SYNC.md "Offline & failure
/// behavior"). It runs one pass per interval in a fresh DI scope, so the scoped
/// AccountPurgeService always sees its own connection. Registered only outside
/// test hosts (Program.cs), so L2 tests drive
/// <see cref="AccountPurgeService.PurgeDueAccountsAsync"/> directly instead of
/// racing a timer.
/// </summary>
public sealed class AccountPurgeHostedService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly AccountOptions _options;
    private readonly ILogger<AccountPurgeHostedService> _logger;

    public AccountPurgeHostedService(
        IServiceScopeFactory scopeFactory,
        IOptions<AccountOptions> options,
        ILogger<AccountPurgeHostedService> logger)
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
                var purge = scope.ServiceProvider.GetRequiredService<AccountPurgeService>();
                var result = await purge.PurgeDueAccountsAsync(stoppingToken);

                if (result.AccountsPurged > 0)
                {
                    _logger.LogInformation(
                        "Account purge pass completed: {Accounts} accounts, {Records} records, {Blobs} blobs.",
                        result.AccountsPurged,
                        result.RecordsPurged,
                        result.BlobsPurged);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Account purge pass failed.");
            }
        }
    }
}
