using System.Diagnostics;
using Testcontainers.PostgreSql;
using Xunit;

namespace Tankbook.Api.Tests;

/// <summary>
/// Starts a single PostgreSQL container shared by the whole test session
/// (lazily, on first use). When Docker is unavailable the tests that need a
/// real database SKIP with a clear message instead of failing, so the suite
/// still runs on machines without a Docker daemon.
/// </summary>
public static class PostgresContainer
{
    private static readonly Lazy<Task<PostgreSqlContainer>> Lazy = new(StartAsync);

    public static bool IsDockerAvailable()
    {
        try
        {
            var psi = new ProcessStartInfo("docker", "info")
            {
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
            };
            using var process = Process.Start(psi);
            if (process is null)
            {
                return false;
            }

            if (!process.WaitForExit(TimeSpan.FromSeconds(10)))
            {
                process.Kill(entireProcessTree: true);
                return false;
            }

            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>Skips the current test when no Docker daemon is reachable.</summary>
    public static void RequireDocker()
    {
        Skip.IfNot(IsDockerAvailable(), "Docker is not available; skipping the containerized PostgreSQL tests.");
    }

    /// <summary>Returns the shared container, starting it on first use.</summary>
    public static Task<PostgreSqlContainer> GetAsync()
    {
        RequireDocker();
        return Lazy.Value;
    }

    private static async Task<PostgreSqlContainer> StartAsync()
    {
        var container = new PostgreSqlBuilder("postgres:17-alpine")
            .WithDatabase("postgres")
            .WithUsername("postgres")
            .WithPassword("postgres")
            .Build();

        await container.StartAsync();
        return container;
    }
}
