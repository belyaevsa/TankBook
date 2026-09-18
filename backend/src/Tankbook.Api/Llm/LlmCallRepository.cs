using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Llm;

/// <summary>The storage-key layout for the ledger's prompt renditions (docs/SECURITY.md "LLM call ledger").</summary>
public static class LlmCallKeys
{
    /// <summary>The rendition of the prompt image, content-addressed under the account prefix.</summary>
    public static string PromptKey(Guid accountId, string sha256) => $"{accountId.ToString("N")}/llm/{sha256}";
}

/// <summary>One llm_calls row to write (migration 015).</summary>
public sealed record LlmCallInsert(
    Guid Id,
    Guid AccountId,
    Guid? DeviceId,
    string Kind,
    string ModelId,
    string Vendor,
    string Outcome,
    string Category,
    long PromptTokens,
    long CompletionTokens,
    bool ThinkingEnabled,
    decimal InputPricePerToken,
    decimal OutputPricePerToken,
    decimal Cost,
    string Currency,
    string? PromptSha256,
    string? PromptBody,
    string? ResponseBody,
    string? ThinkingBody,
    long DurationMs,
    string[]? PromptPageSha256s = null);

/// <summary>A ledger row whose content is due for the retention purge (its account, id and the renditions it references).</summary>
public sealed record LlmCallPurgeRow(Guid AccountId, Guid Id, string? PromptSha256, string[]? PromptPageSha256s)
{
    /// <summary>The single-rendition shape (every row before migration 024).</summary>
    public LlmCallPurgeRow(Guid accountId, Guid id, string? promptSha256)
        : this(accountId, id, promptSha256, null)
    {
    }

    /// <summary>Every rendition the row references: the first page and the further pages of a multi-page call.</summary>
    public IEnumerable<string> AllSha256s
    {
        get
        {
            if (PromptSha256 is not null)
            {
                yield return PromptSha256;
            }

            foreach (var sha in PromptPageSha256s ?? [])
            {
                yield return sha;
            }
        }
    }
}

/// <summary>
/// Database access for the LLM call ledger (migration 015, docs/SECURITY.md
/// "LLM call ledger"). The gateway writes one row per call; nothing reads the
/// ledger over HTTP - there is no query, search or stats endpoint over it, so
/// the only reads here are the purge's enumeration (id + sha256, never a body).
/// </summary>
public sealed class LlmCallRepository
{
    private readonly IDbConnection _db;

    public LlmCallRepository(IDbConnection db)
    {
        _db = db;
    }

    public async Task InsertAsync(LlmCallInsert call, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO llm_calls
                    (id, account_id, device_id, kind, model_id, vendor, outcome, category,
                     prompt_tokens, completion_tokens, thinking_enabled,
                     input_price_per_token, output_price_per_token, cost, currency,
                     prompt_sha256, prompt_body, response_body, thinking_body, duration_ms,
                     prompt_page_sha256s)
                VALUES
                    (@Id, @AccountId, @DeviceId, @Kind, @ModelId, @Vendor, @Outcome, @Category,
                     @PromptTokens, @CompletionTokens, @ThinkingEnabled,
                     @InputPricePerToken, @OutputPricePerToken, @Cost, @Currency,
                     @PromptSha256, @PromptBody, @ResponseBody, @ThinkingBody, @DurationMs,
                     @PromptPageSha256s)
                """,
                call,
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
    /// Calls past the retention cutoff that still carry content (a body or a
    /// rendition reference). The purge nulls their bodies and deletes their
    /// renditions, leaving the ledger fields and the sha256 reference.
    /// </summary>
    public async Task<IReadOnlyList<LlmCallPurgeRow>> ListDueAsync(DateTimeOffset cutoff, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            // Materialised through a property-bound row: Dapper cannot match a
            // text[] column onto a record constructor's string[] parameter.
            var rows = await _db.QueryAsync<PurgeRowDto>(new CommandDefinition(
                """
                SELECT account_id AS AccountId, id AS Id, prompt_sha256 AS PromptSha256,
                       prompt_page_sha256s AS PromptPageSha256s
                FROM llm_calls
                WHERE created_at <= @Cutoff
                  AND (prompt_body IS NOT NULL OR response_body IS NOT NULL
                       OR thinking_body IS NOT NULL OR prompt_sha256 IS NOT NULL
                       OR prompt_page_sha256s IS NOT NULL)
                """,
                new { Cutoff = cutoff },
                cancellationToken: cancellationToken));
            return rows.Select(r => new LlmCallPurgeRow(r.AccountId, r.Id, r.PromptSha256, r.PromptPageSha256s)).ToList();
        }
        finally
        {
            if (opened)
            {
                _db.Close();
            }
        }
    }

    /// <summary>Nulls the content columns for the given rows, keeping the ledger fields and sha256.</summary>
    public async Task PurgeContentAsync(IReadOnlyList<Guid> ids, CancellationToken cancellationToken)
    {
        if (ids.Count == 0)
        {
            return;
        }

        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                UPDATE llm_calls
                SET prompt_body = NULL, response_body = NULL, thinking_body = NULL
                WHERE id = ANY(@Ids)
                """,
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

    /// <summary>The distinct prompt renditions an account's ledger references (for account-deletion purge).</summary>
    public async Task<IReadOnlyList<string>> ListAccountSha256sAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<string>(new CommandDefinition(
                """
                SELECT DISTINCT sha256 FROM (
                    SELECT prompt_sha256 AS sha256 FROM llm_calls
                    WHERE account_id = @AccountId AND prompt_sha256 IS NOT NULL
                    UNION ALL
                    SELECT unnest(prompt_page_sha256s) FROM llm_calls
                    WHERE account_id = @AccountId AND prompt_page_sha256s IS NOT NULL
                ) AS renditions
                """,
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

    /// <summary>
    /// The prompt renditions still referenced by a call inside the retention
    /// window (its content is still present). Content-addressing dedupes two
    /// identical images to one hash, so a rendition must survive until the last
    /// reference expires - these shas protect the shared blob from the retention
    /// purge.
    /// </summary>
    public async Task<IReadOnlyList<string>> ListLiveSha256sAsync(DateTimeOffset cutoff, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            var rows = await _db.QueryAsync<string>(new CommandDefinition(
                """
                SELECT DISTINCT sha256 FROM (
                    SELECT prompt_sha256 AS sha256 FROM llm_calls
                    WHERE prompt_sha256 IS NOT NULL AND created_at > @Cutoff
                    UNION ALL
                    SELECT unnest(prompt_page_sha256s) FROM llm_calls
                    WHERE prompt_page_sha256s IS NOT NULL AND created_at > @Cutoff
                ) AS renditions
                """,
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

    /// <summary>Nulls the content columns for one account (the row survives, account_id included).</summary>
    public async Task PurgeAccountContentAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            await _db.ExecuteAsync(new CommandDefinition(
                """
                UPDATE llm_calls
                SET prompt_body = NULL, response_body = NULL, thinking_body = NULL
                WHERE account_id = @AccountId
                """,
                new { AccountId = accountId },
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

/// <summary>Dapper's materialisation shape for the purge enumeration (see ListDueAsync).</summary>
internal sealed class PurgeRowDto
{
    public Guid AccountId { get; set; }
    public Guid Id { get; set; }
    public string? PromptSha256 { get; set; }
    public string[]? PromptPageSha256s { get; set; }
}
