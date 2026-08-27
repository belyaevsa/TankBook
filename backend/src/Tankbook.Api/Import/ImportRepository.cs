using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Import;

/// <summary>
/// Database access for the import parse index (migration 012, docs/SECURITY.md
/// "Import files at rest"). The row holds only shape - format, file kind and
/// counts - so the 30-day purge and the account purge can enumerate what to drop
/// without ever reading a payload (hard rule 12). The uploaded file and its
/// parse result live in blob storage at file_key / result_key.
/// </summary>
public sealed class ImportRepository
{
    private readonly IDbConnection _db;

    public ImportRepository(IDbConnection db)
    {
        _db = db;
    }

    private const string Columns = """
        id            AS Id,
        account_id    AS AccountId,
        device_id     AS DeviceId,
        format        AS Format,
        file_kind     AS FileKind,
        file_key      AS FileKey,
        result_key    AS ResultKey,
        rows_read     AS RowsRead,
        candidate_count AS CandidateCount,
        unparsed_count AS UnparsedCount,
        created_at    AS CreatedAt
        """;

    public async Task InsertAsync(
        Guid id,
        Guid? accountId,
        Guid deviceId,
        string format,
        string fileKind,
        string fileKey,
        string resultKey,
        int rowsRead,
        int candidateCount,
        int unparsedCount,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO import_parses
                    (id, account_id, device_id, format, file_kind, file_key, result_key,
                     rows_read, candidate_count, unparsed_count)
                VALUES
                    (@Id, @AccountId, @DeviceId, @Format, @FileKind, @FileKey, @ResultKey,
                     @RowsRead, @CandidateCount, @UnparsedCount)
                """,
                new
                {
                    Id = id,
                    AccountId = accountId,
                    DeviceId = deviceId,
                    Format = format,
                    FileKind = fileKind,
                    FileKey = fileKey,
                    ResultKey = resultKey,
                    RowsRead = rowsRead,
                    CandidateCount = candidateCount,
                    UnparsedCount = unparsedCount,
                },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    public async Task<ImportParseRow?> GetAsync(Guid id, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleOrDefaultAsync<ImportParseRow>(new CommandDefinition(
                $"SELECT {Columns} FROM import_parses WHERE id = @Id",
                new { Id = id },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    public async Task DeleteAsync(Guid id, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM import_parses WHERE id = @Id",
                new { Id = id },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Parses stored long enough ago to be purged (created_at &lt;= cutoff), and returns their storage keys so the caller can drop the objects too.</summary>
    public async Task<IReadOnlyList<ImportParseRow>> ListDueAsync(DateTimeOffset cutoff, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<ImportParseRow>(new CommandDefinition(
                $"SELECT {Columns} FROM import_parses WHERE created_at <= @Cutoff",
                new { Cutoff = cutoff },
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Every parse an account owns (docs/SECURITY.md: deleting the account deletes these too).</summary>
    public async Task<IReadOnlyList<ImportParseRow>> ListForAccountAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<ImportParseRow>(new CommandDefinition(
                $"SELECT {Columns} FROM import_parses WHERE account_id = @AccountId",
                new { AccountId = accountId },
                cancellationToken: cancellationToken));
            return rows.ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    public async Task DeleteManyAsync(IReadOnlyList<Guid> ids, CancellationToken cancellationToken)
    {
        if (ids.Count == 0)
        {
            return;
        }

        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "DELETE FROM import_parses WHERE id = ANY(@Ids)",
                new { Ids = ids.ToArray() },
                cancellationToken: cancellationToken));
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    private async Task<bool> OpenIfNeededAsync()
    {
        if (_db.State == ConnectionState.Open)
        {
            return false;
        }

        await ((DbConnection)_db).OpenAsync();
        return true;
    }
}
