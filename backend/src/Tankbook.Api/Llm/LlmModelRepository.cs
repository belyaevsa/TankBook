using System.Data;
using System.Data.Common;
using Dapper;

namespace Tankbook.Api.Llm;

/// <summary>A llm_models row (migration 014) - one effective pricing entry for a model.</summary>
public sealed record LlmModelRow(
    string ModelId,
    string Vendor,
    decimal InputPricePerToken,
    decimal OutputPricePerToken,
    string Currency,
    int ContextWindow,
    bool SupportsThinking);

/// <summary>
/// Database access for the model dictionary and the per-kind model settings
/// (migration 014, docs/API.md "LLM gateway"). Two read-only queries - the
/// tables are written by direct DB write, never by an endpoint, so there is no
/// write path here. The dictionary is keyed (model_id, effective_from), so
/// <see cref="GetCurrentModelAsync"/> picks the entry whose effective_from is
/// the latest at-or-before the given day - a price correction is a new row,
/// never an edit.
/// </summary>
public sealed class LlmModelRepository
{
    private readonly IDbConnection _db;

    public LlmModelRepository(IDbConnection db)
    {
        _db = db;
    }

    /// <summary>The model id a kind resolves to, or null when no setting row exists (fall back).</summary>
    public async Task<string?> GetSettingForKindAsync(string kind, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleOrDefaultAsync<string>(new CommandDefinition(
                "SELECT model_id FROM llm_settings WHERE kind = @Kind",
                new { Kind = kind },
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
    /// The model's current pricing entry - the row whose effective_from is the
    /// latest at-or-before <paramref name="today"/>. Null when the model id is
    /// unknown in the dictionary (the resolver falls back).
    /// </summary>
    public async Task<LlmModelRow?> GetCurrentModelAsync(string modelId, DateOnly today, CancellationToken cancellationToken)
    {
        var opened = await OpenIfNeededAsync();
        try
        {
            return await _db.QuerySingleOrDefaultAsync<LlmModelRow>(new CommandDefinition(
                """
                SELECT model_id AS ModelId, vendor AS Vendor,
                       input_price AS InputPricePerToken,
                       output_price AS OutputPricePerToken,
                       currency AS Currency,
                       context_window AS ContextWindow,
                       supports_thinking AS SupportsThinking
                FROM llm_models
                WHERE model_id = @ModelId AND effective_from <= @Today
                ORDER BY effective_from DESC
                LIMIT 1
                """,
                new { ModelId = modelId, Today = today },
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
