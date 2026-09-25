using System.Reflection;
using Dapper;

namespace Tankbook.Admin.Data;

/// <summary>
/// Applies the viewer's own migrations (<c>Migrations/NNN_*.up.sql</c>, embedded) through
/// the admin-write connection, each once, recorded in <c>admin.schema_migrations</c>. Run as
/// its own step (<c>--migrate</c>), never as a side effect of the service starting.
/// </summary>
public static class Migrator
{
    public static async Task<int> ApplyAsync(Db db, CancellationToken ct = default)
    {
        await using var connection = db.AdminWrite();
        await connection.OpenAsync(ct);
        // Schema `admin` is created by `roles.sql`, owned by the write role, which has no
        // right to create schemas itself - least privilege, checked by Postgres before
        // IF NOT EXISTS is.
        await connection.ExecuteAsync(
            "CREATE TABLE IF NOT EXISTS admin.schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())");
        var applied = (await connection.QueryAsync<string>("SELECT name FROM admin.schema_migrations")).ToHashSet();
        var assembly = Assembly.GetExecutingAssembly();
        var scripts = assembly.GetManifestResourceNames()
            .Where(n => n.EndsWith(".up.sql", StringComparison.Ordinal))
            .OrderBy(n => n, StringComparer.Ordinal)
            .ToList();
        var count = 0;
        foreach (var resource in scripts)
        {
            var name = resource[(resource.IndexOf("Migrations.", StringComparison.Ordinal) + "Migrations.".Length)..];
            if (applied.Contains(name))
            {
                continue;
            }
            await using var stream = assembly.GetManifestResourceStream(resource)!;
            using var reader = new StreamReader(stream);
            var sql = await reader.ReadToEndAsync(ct);
            await using var transaction = await connection.BeginTransactionAsync(ct);
            await connection.ExecuteAsync(sql, transaction: transaction);
            await connection.ExecuteAsync("INSERT INTO admin.schema_migrations (name) VALUES (@name)", new { name }, transaction);
            await transaction.CommitAsync(ct);
            count++;
        }
        return count;
    }
}
