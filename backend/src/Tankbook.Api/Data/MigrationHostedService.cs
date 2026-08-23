using Microsoft.Extensions.Options;
using Npgsql;
using Tankbook.Api.Options;

namespace Tankbook.Api.Data;

/// <summary>
/// Applies pending SQL migrations at startup. Skips quietly when
/// ConnectionStrings:Postgres is not configured; otherwise retries with capped
/// exponential backoff so the API can start before the database is reachable.
/// Migrations are idempotent (see SchemaMigrator), so a restart never re-applies.
/// </summary>
public sealed class MigrationHostedService : BackgroundService
{
    private static readonly TimeSpan MaxRetryDelay = TimeSpan.FromSeconds(30);
    private const int MaxAttempts = 30;

    private readonly IServiceProvider _services;
    private readonly ILogger<MigrationHostedService> _logger;

    public MigrationHostedService(IServiceProvider services, ILogger<MigrationHostedService> logger)
    {
        _services = services;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var connectionString = _services
            .GetRequiredService<IOptions<ConnectionStringsOptions>>()
            .Value.Postgres;

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            _logger.LogWarning("ConnectionStrings:Postgres is not configured; skipping database migrations.");
            return;
        }

        var delay = TimeSpan.FromSeconds(1);
        for (var attempt = 1; attempt <= MaxAttempts && !stoppingToken.IsCancellationRequested; attempt++)
        {
            try
            {
                await using var connection = new NpgsqlConnection(connectionString);
                await connection.OpenAsync(stoppingToken);
                await SchemaMigrator.ApplyPendingAsync(connection, stoppingToken, _logger);
                // Migration 003 seeds the baseline config document with an empty
                // signature (SQL cannot compute Ed25519); complete it here, with
                // the configured signing key, so GET /config serves a document
                // clients can verify (docs/CONFIG.md signed payload).
                await Tankbook.Api.Config.ConfigBaselineSeeder.SeedAsync(
                    connection,
                    _services.GetRequiredService<Tankbook.Api.Config.ConfigSigner>(),
                    _services.GetRequiredService<Tankbook.Api.Config.ConfigSchemaValidator>(),
                    _logger,
                    stoppingToken);
                _logger.LogInformation("Database migrations applied.");
                return;
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception ex)
            {
                _logger.LogWarning(
                    "Database migration attempt {Attempt}/{MaxAttempts} failed ({Reason}); retrying in {Delay}.",
                    attempt, MaxAttempts, ex.Message, delay);
                try
                {
                    await Task.Delay(delay, stoppingToken);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
                {
                    return;
                }
                delay = TimeSpan.FromSeconds(Math.Min(delay.TotalSeconds * 2, MaxRetryDelay.TotalSeconds));
            }
        }

        _logger.LogError("Database migrations did not apply after {MaxAttempts} attempts; the API will run without a schema.", MaxAttempts);
    }
}
