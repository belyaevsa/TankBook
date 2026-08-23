using System.Data;
using System.Data.Common;
using System.Reflection;
using Dapper;
using Microsoft.Extensions.Logging;

namespace Tankbook.Api.Data;

/// <summary>
/// Applies plain, numbered SQL migrations embedded in this assembly
/// (Migrations/*.up.sql / *.down.sql), recording applied versions in the
/// <c>schema_migrations</c> table. Idempotent: re-running skips already-applied
/// migrations. Rollback runs the .down files in reverse version order and
/// forgets the applied versions.
/// </summary>
public static class SchemaMigrator
{
    private const string MigrationsPrefix = "Tankbook.Api.Migrations.";
    private const string UpSuffix = ".up.sql";
    private const string DownSuffix = ".down.sql";

    private static readonly Assembly Assembly = typeof(SchemaMigrator).Assembly;

    /// <summary>Applies every pending .up.sql migration, in version order.</summary>
    public static async Task ApplyPendingAsync(
        DbConnection connection,
        CancellationToken cancellationToken = default,
        ILogger? logger = null)
    {
        await EnsureSchemaMigrationsTableAsync(connection, cancellationToken);
        var applied = await GetAppliedVersionsAsync(connection, cancellationToken);

        foreach (var migration in Discover(UpSuffix).Where(m => !applied.Contains(m.Version)).OrderBy(m => m.Version))
        {
            var stopwatch = System.Diagnostics.Stopwatch.StartNew();
            var sql = await ReadResourceAsync(migration.ResourceName, cancellationToken);
            // Migration 002 carries a seed marker for the payload schema registry;
            // materialize it here so applying the migration populates the registry.
            sql = PayloadSchemaSeeder.Materialize(sql);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            await connection.ExecuteAsync(sql, transaction: transaction);
            await connection.ExecuteAsync(
                "INSERT INTO schema_migrations (version, name) VALUES (@version, @name)",
                new { migration.Version, migration.Name },
                transaction);
            await transaction.CommitAsync(cancellationToken);
            stopwatch.Stop();

            if (logger is not null)
            {
                Tankbook.Api.Logging.TankbookLog.MigrationDdl(logger, migration.Version, "up", stopwatch.Elapsed);
            }
        }
    }

    /// <summary>Runs the .down.sql for every applied migration, newest first.</summary>
    public static async Task RollbackAsync(
        DbConnection connection,
        CancellationToken cancellationToken = default,
        ILogger? logger = null)
    {
        await EnsureSchemaMigrationsTableAsync(connection, cancellationToken);
        var applied = await GetAppliedVersionsAsync(connection, cancellationToken);

        foreach (var migration in Discover(DownSuffix).Where(m => applied.Contains(m.Version)).OrderByDescending(m => m.Version))
        {
            var stopwatch = System.Diagnostics.Stopwatch.StartNew();
            var sql = await ReadResourceAsync(migration.ResourceName, cancellationToken);
            await using var transaction = await connection.BeginTransactionAsync(cancellationToken);
            await connection.ExecuteAsync(sql, transaction: transaction);
            await connection.ExecuteAsync(
                "DELETE FROM schema_migrations WHERE version = @version",
                new { migration.Version },
                transaction);
            await transaction.CommitAsync(cancellationToken);
            stopwatch.Stop();

            if (logger is not null)
            {
                Tankbook.Api.Logging.TankbookLog.MigrationDdl(logger, migration.Version, "down", stopwatch.Elapsed);
            }
        }
    }

    private static async Task EnsureSchemaMigrationsTableAsync(DbConnection connection, CancellationToken cancellationToken)
    {
        const string sql = """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version    text PRIMARY KEY,
                name       text NOT NULL,
                applied_at timestamptz NOT NULL DEFAULT now()
            );
            """;
        await connection.ExecuteAsync(sql);
    }

    private static async Task<HashSet<string>> GetAppliedVersionsAsync(DbConnection connection, CancellationToken cancellationToken)
    {
        var versions = await connection.QueryAsync<string>("SELECT version FROM schema_migrations");
        return versions.ToHashSet(StringComparer.Ordinal);
    }

    private static IEnumerable<MigrationFile> Discover(string suffix)
    {
        var resources = Assembly.GetManifestResourceNames()
            .Where(name => name.StartsWith(MigrationsPrefix, StringComparison.Ordinal) &&
                           name.EndsWith(suffix, StringComparison.Ordinal));

        foreach (var name in resources)
        {
            var stem = name[MigrationsPrefix.Length..^suffix.Length];
            var version = stem.Split('_', 2)[0];
            yield return new MigrationFile(version, stem, name);
        }
    }

    private static async Task<string> ReadResourceAsync(string resourceName, CancellationToken cancellationToken)
    {
        await using var stream = Assembly.GetManifestResourceStream(resourceName)
            ?? throw new InvalidOperationException($"Missing embedded migration resource '{resourceName}'.");
        using var reader = new StreamReader(stream);
        return await reader.ReadToEndAsync(cancellationToken);
    }

    private sealed record MigrationFile(string Version, string Name, string ResourceName);
}
