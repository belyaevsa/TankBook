using Npgsql;
using Xunit;

namespace Tankbook.Api.Tests;

/// <summary>
/// Per-test-class fixture providing a fresh, uniquely-named PostgreSQL database
/// inside the shared Testcontainers container. Test methods that need a real
/// database call <see cref="RequireAvailable"/> first so the suite skips (not
/// fails) when Docker is unavailable.
/// </summary>
public sealed class PostgresFixture : IAsyncLifetime
{
    private readonly bool _dockerAvailable;
    private string? _adminConnectionString;

    public PostgresFixture()
    {
        _dockerAvailable = PostgresContainer.IsDockerAvailable();
    }

    public Task InitializeAsync() => Task.CompletedTask;

    public Task DisposeAsync() => Task.CompletedTask;

    /// <summary>Skips the current test when no Docker daemon is reachable.</summary>
    public void RequireAvailable()
    {
        Skip.IfNot(_dockerAvailable, "Docker is not available; skipping the containerized PostgreSQL tests.");
    }

    /// <summary>
    /// Creates a brand-new database and returns an open-free connection to it,
    /// so every test starts from a clean slate. Connection pooling means the
    /// admin connection is reused for the CREATE DATABASE call.
    /// </summary>
    public async Task<NpgsqlConnection> CreateDatabaseAsync()
    {
        RequireAvailable();

        _adminConnectionString ??= (await PostgresContainer.GetAsync()).GetConnectionString();

        var name = "tankbook_test_" + Guid.NewGuid().ToString("N");
        await using (var admin = new NpgsqlConnection(_adminConnectionString))
        {
            await admin.OpenAsync();
            await using var command = admin.CreateCommand();
            command.CommandText = $"CREATE DATABASE \"{name}\"";
            await command.ExecuteNonQueryAsync();
        }

        var builder = new NpgsqlConnectionStringBuilder(_adminConnectionString)
        {
            Database = name,
            // Keep the password readable from ConnectionString after the
            // connection is opened, so tests can build worker connections
            // from it (Npgsql otherwise strips it once opened).
            PersistSecurityInfo = true,
        };
        return new NpgsqlConnection(builder.ConnectionString);
    }
}
