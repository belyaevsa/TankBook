using System.Text.RegularExpressions;
using Dapper;
using Microsoft.Extensions.Configuration;
using Tankbook.Admin.Data;
using Npgsql;
using Testcontainers.PostgreSql;

namespace Tankbook.Admin.Tests;

/// <summary>
/// One Postgres for the suite, built the way production is: the API's own migrations
/// (read from <c>backend/</c> as files - no project reference), then the viewer's
/// <c>roles.sql</c>, then the viewer's schema through its write role.
/// </summary>
public sealed partial class AdminDatabase : IAsyncLifetime
{
    [GeneratedRegex(@"\{\{PAYLOAD_SCHEMAS_[A-Z_]+\}\}")]
    private static partial Regex PayloadSeedPlaceholder();

    public const string ReadOnlyPassword = "ro-test";
    public const string WritePassword = "rw-test";

    private readonly PostgreSqlContainer _container = new PostgreSqlBuilder("postgres:16-alpine").Build();

    public string Superuser => _container.GetConnectionString();
    public string ApiRead => Role("tankbook_admin_ro", ReadOnlyPassword);
    public string AdminWrite => Role("tankbook_admin_rw", WritePassword);

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        await using var c = new NpgsqlConnection(Superuser);
        await c.OpenAsync();
        foreach (var file in Directory.GetFiles(Path.Combine(RepoRoot, "backend/src/Tankbook.Api/Migrations"), "*.up.sql")
                     .OrderBy(f => f, StringComparer.Ordinal))
        {
            // The API fills `{{PAYLOAD_SCHEMAS_*}}` with its schema-registry seed before it
            // runs a migration; the viewer never reads that registry, so the seed is dropped.
            var sql = PayloadSeedPlaceholder().Replace(await File.ReadAllTextAsync(file), "");
            await c.ExecuteAsync(sql);
        }
        var roles = await File.ReadAllTextAsync(Path.Combine(RepoRoot, "admin/api/src/Tankbook.Admin/Migrations/roles.sql"));
        await c.ExecuteAsync(roles
            .Replace("change-me-ro", ReadOnlyPassword, StringComparison.Ordinal)
            .Replace("change-me-rw", WritePassword, StringComparison.Ordinal));
        var config = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:ApiRead"] = ApiRead,
            ["ConnectionStrings:AdminWrite"] = AdminWrite,
        }).Build();
        await Migrator.ApplyAsync(new Db(config));
    }

    public Task DisposeAsync() => _container.DisposeAsync().AsTask();

    private string Role(string user, string password) =>
        new NpgsqlConnectionStringBuilder(Superuser) { Username = user, Password = password }.ConnectionString;

    public static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "backend")))
            {
                dir = dir.Parent;
            }
            return dir?.FullName ?? throw new InvalidOperationException("repo root not found");
        }
    }
}

[CollectionDefinition(Name)]
public sealed class AdminCollection : ICollectionFixture<AdminDatabase>
{
    public const string Name = "admin database";
}
