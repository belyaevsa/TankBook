using System.Data;
using System.Data.Common;
using System.Text.Json;
using Dapper;

namespace Tankbook.Api.Feedback;

/// <summary>
/// Database access for the feedback table (migration 001, docs/SCHEMA.md
/// "Feedback intake"). One row per case: the category and text in dedicated
/// columns, the optional metadata envelope (appVersion, deviceModel, replyTo)
/// in the meta jsonb. account_id is NULL for the signed-out path - a user with
/// no account can complain too. Only shape is ever read back or logged (hard
/// rule 12); the text, the replyTo address and the device model never enter a
/// log line (docs/LOGGING.md -> Feedback).
/// </summary>
public sealed class FeedbackRepository
{
    private readonly IDbConnection _db;

    public FeedbackRepository(IDbConnection db)
    {
        _db = db;
    }

    public async Task InsertAsync(
        Guid id,
        Guid? accountId,
        string category,
        string text,
        string? appVersion,
        string? deviceModel,
        string? replyTo,
        CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO feedback (id, account_id, category, text, meta)
                VALUES (@Id, @AccountId, @Category, @Text, @Meta::jsonb)
                """,
                new
                {
                    Id = id,
                    AccountId = accountId,
                    Category = category,
                    Text = text,
                    Meta = BuildMeta(appVersion, deviceModel, replyTo),
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

    /// <summary>
    /// The optional metadata envelope as one jsonb document. Only the fields
    /// the user supplied appear; replyTo is user-supplied contact data, so it
    /// is the most sensitive value in the row (and never touches a log line).
    /// </summary>
    private static string BuildMeta(string? appVersion, string? deviceModel, string? replyTo)
    {
        var meta = new Dictionary<string, string>();
        if (appVersion is not null)
        {
            meta["appVersion"] = appVersion;
        }

        if (deviceModel is not null)
        {
            meta["deviceModel"] = deviceModel;
        }

        if (replyTo is not null)
        {
            meta["replyTo"] = replyTo;
        }

        return JsonSerializer.Serialize(meta);
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
