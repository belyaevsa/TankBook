using System.Data;
using Dapper;

namespace Tankbook.Api.Config;

/// <summary>One published config document row (docs/CONFIG.md).</summary>
public sealed class ConfigDocumentRow
{
    public ConfigDocumentRow()
    {
    }

    public ConfigDocumentRow(
        int version,
        string document,
        string signature,
        DateTimeOffset issuedAt,
        DateTimeOffset notAfter,
        DateTimeOffset publishedAt)
    {
        Version = version;
        Document = document;
        Signature = signature;
        IssuedAt = issuedAt;
        NotAfter = notAfter;
        PublishedAt = publishedAt;
    }

    public int Version { get; set; }

    public string Document { get; set; } = string.Empty;

    public string Signature { get; set; } = string.Empty;

    public DateTimeOffset IssuedAt { get; set; }

    public DateTimeOffset NotAfter { get; set; }

    public DateTimeOffset PublishedAt { get; set; }
}

/// <summary>
/// Database access for <c>config_documents</c> (migration 003). The server
/// stores the document verbatim and the Ed25519 signature; the validity window
/// is mirrored in columns so <see cref="ConfigReadService"/> can select the
/// servable version without parsing the payload.
/// </summary>
public sealed class ConfigRepository
{
    private readonly IDbConnection _db;

    public ConfigRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>
    /// Every document, newest first. The read service applies the validity
    /// selection; the row set is tiny and changes rarely.
    /// </summary>
    public async Task<IReadOnlyList<ConfigDocumentRow>> GetAllDescendingAsync(CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<ConfigDocumentRow>(new CommandDefinition(
                """
                SELECT version,
                       document::text AS Document,
                       signature       AS Signature,
                       issued_at       AS IssuedAt,
                       not_after       AS NotAfter,
                       published_at    AS PublishedAt
                FROM config_documents
                ORDER BY version DESC
                """,
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

    /// <summary>The highest published version, or null when the table is empty.</summary>
    public async Task<int?> GetHighestVersionAsync(CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleOrDefaultAsync<int?>(new CommandDefinition(
                "SELECT max(version) FROM config_documents",
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

    /// <summary>Inserts a signed document. The version primary key refuses duplicates.</summary>
    public async Task InsertAsync(ConfigDocumentRow row, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO config_documents (version, document, signature, issued_at, not_after)
                VALUES (@Version, @Document::jsonb, @Signature, @IssuedAt, @NotAfter)
                """,
                new
                {
                    row.Version,
                    row.Document,
                    row.Signature,
                    row.IssuedAt,
                    row.NotAfter,
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

    /// <summary>Re-signs an existing document in place (the baseline seed path).</summary>
    public async Task UpdateSignatureAsync(int version, string signature, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                "UPDATE config_documents SET signature = @Signature WHERE version = @Version",
                new { Version = version, Signature = signature },
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

        // The DI container always supplies an NpgsqlConnection, which is a
        // DbConnection; the System.Data IDbConnection abstraction has no
        // OpenAsync, so open through the concrete base.
        await ((System.Data.Common.DbConnection)_db).OpenAsync();
        return true;
    }
}
