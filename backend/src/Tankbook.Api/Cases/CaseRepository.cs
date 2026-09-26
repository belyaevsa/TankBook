using System.Data;
using System.Data.Common;
using System.Text.Json;
using Dapper;

namespace Tankbook.Api.Cases;

/// <summary>One stored part of a case: its name, declared content type, size and storage key.</summary>
public sealed record CasePart(string Name, string ContentType, long Bytes, string Key);

/// <summary>The case index row (migration 026). Envelope only - never a part's content.</summary>
public sealed record CaseRow(string Id, Guid? AccountId, Guid DeviceId, string? App, IReadOnlyList<CasePart> Parts,
                             long TotalBytes, DateTimeOffset CreatedAt);

/// <summary>
/// Database access for the debug case index (migration 026). The purge, the
/// account purge and the admin viewer's lookup read it; nothing queries a case
/// by what it contains (hard rule 9).
/// </summary>
public sealed class CaseRepository
{
    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);
    private readonly IDbConnection _db;

    public CaseRepository(IDbConnection db)
    {
        _db = db;
    }

    private sealed record RawRow(string Id, Guid? AccountId, Guid DeviceId, string? App, string Parts, long TotalBytes,
                                 DateTime CreatedAt);

    private const string Columns = """
        id AS Id, account_id AS AccountId, device_id AS DeviceId, app AS App,
        parts::text AS Parts, total_bytes AS TotalBytes, created_at AS CreatedAt
        """;

    public Task InsertAsync(CaseRow row, CancellationToken cancellationToken)
        => WithConnection(() => _db.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO debug_cases (id, account_id, device_id, app, parts, total_bytes)
            VALUES (@Id, @AccountId, @DeviceId, @App, CAST(@Parts AS jsonb), @TotalBytes)
            """,
            new
            {
                row.Id,
                row.AccountId,
                row.DeviceId,
                row.App,
                Parts = JsonSerializer.Serialize(row.Parts, WireJson),
                row.TotalBytes,
            },
            cancellationToken: cancellationToken)));

    public async Task<IReadOnlyList<CaseRow>> ListDueAsync(DateTimeOffset cutoff, CancellationToken cancellationToken)
        => await QueryAsync("created_at <= @Cutoff", new { Cutoff = cutoff }, cancellationToken);

    public async Task<IReadOnlyList<CaseRow>> ListForAccountAsync(Guid accountId, CancellationToken cancellationToken)
        => await QueryAsync("account_id = @AccountId", new { AccountId = accountId }, cancellationToken);

    public async Task DeleteManyAsync(IReadOnlyList<string> ids, CancellationToken cancellationToken)
    {
        if (ids.Count == 0)
        {
            return;
        }

        await WithConnection(() => _db.ExecuteAsync(new CommandDefinition(
            "DELETE FROM debug_cases WHERE id = ANY(@Ids)",
            new { Ids = ids.ToArray() },
            cancellationToken: cancellationToken)));
    }

    private async Task<IReadOnlyList<CaseRow>> QueryAsync(string where, object parameters,
                                                          CancellationToken cancellationToken)
    {
        var rows = await WithConnection(() => _db.QueryAsync<RawRow>(new CommandDefinition(
            $"SELECT {Columns} FROM debug_cases WHERE {where}", parameters, cancellationToken: cancellationToken)));
        return rows.Select(ToRow).ToList();
    }

    private static CaseRow ToRow(RawRow raw)
        => new(raw.Id, raw.AccountId, raw.DeviceId, raw.App,
               JsonSerializer.Deserialize<List<CasePart>>(raw.Parts, WireJson) ?? [],
               raw.TotalBytes, new DateTimeOffset(DateTime.SpecifyKind(raw.CreatedAt, DateTimeKind.Utc)));

    private async Task<T> WithConnection<T>(Func<Task<T>> body)
    {
        var opened = false;
        if (_db.State != ConnectionState.Open)
        {
            await ((DbConnection)_db).OpenAsync();
            opened = true;
        }

        try
        {
            return await body();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }
}
