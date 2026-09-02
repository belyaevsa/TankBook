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
        await RunAsync(_services, _logger, stoppingToken);
    }

    /// <summary>
    /// Applies pending migrations and completes the signed config baseline.
    /// </summary>
    /// <remarks>
    /// Shared by the startup hosted service and the explicit <c>--migrate</c>
    /// entry point, so the deploy-time step and the boot-time one cannot drift.
    /// The config baseline is part of this on purpose: migration 003 seeds the
    /// baseline document with an EMPTY signature because SQL cannot compute
    /// Ed25519, so a run that applied the schema and skipped this would leave
    /// GET /config serving a document no client can verify - a "successful"
    /// migration that quietly breaks remote config.
    /// </remarks>
    /// <returns>True when the schema is present and the baseline is signed.</returns>
    public static async Task<bool> RunAsync(
        IServiceProvider services,
        ILogger logger,
        CancellationToken stoppingToken)
    {
        var connectionString = services
            .GetRequiredService<IOptions<ConnectionStringsOptions>>()
            .Value.Postgres;

        if (string.IsNullOrWhiteSpace(connectionString))
        {
            logger.LogWarning("ConnectionStrings:Postgres is not configured; skipping database migrations.");
            return false;
        }

        var delay = TimeSpan.FromSeconds(1);
        for (var attempt = 1; attempt <= MaxAttempts && !stoppingToken.IsCancellationRequested; attempt++)
        {
            try
            {
                await using var connection = new NpgsqlConnection(connectionString);
                await connection.OpenAsync(stoppingToken);
                await SchemaMigrator.ApplyPendingAsync(connection, stoppingToken, logger);
                // Migration 003 seeds the baseline config document with an empty
                // signature (SQL cannot compute Ed25519); complete it here, with
                // the configured signing key, so GET /config serves a document
                // clients can verify (docs/CONFIG.md signed payload).
                await Tankbook.Api.Config.ConfigBaselineSeeder.SeedAsync(
                    connection,
                    services.GetRequiredService<Tankbook.Api.Config.ConfigSigner>(),
                    services.GetRequiredService<Tankbook.Api.Config.ConfigSchemaValidator>(),
                    logger,
                    stoppingToken);
                logger.LogInformation("Database migrations applied.");
                return true;
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return false;
            }
            catch (Exception ex)
            {
                logger.LogWarning(
                    "Database migration attempt {Attempt}/{MaxAttempts} failed ({Reason}); retrying in {Delay}.",
                    attempt, MaxAttempts, ex.Message, delay);
                try
                {
                    await Task.Delay(delay, stoppingToken);
                }
                catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
                {
                    return false;
                }
                delay = TimeSpan.FromSeconds(Math.Min(delay.TotalSeconds * 2, MaxRetryDelay.TotalSeconds));
            }
        }

        logger.LogError("Database migrations did not apply after {MaxAttempts} attempts.", MaxAttempts);
        return false;
    }
}
