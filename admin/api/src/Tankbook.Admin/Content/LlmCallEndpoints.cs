using Dapper;
using Tankbook.Admin.Access;
using Tankbook.Admin.Data;

namespace Tankbook.Admin.Content;

/// <summary>
/// The LLM call ledger (<c>llm_calls</c>, migration 015) read by its one reader
/// (hard rule 9's admin-viewer amendment): an account's calls newest first, one call whole,
/// and its prompt image page by page from the bucket. The ledger's own retention applies -
/// a purged body or image is shown as purged, never as an error.
/// </summary>
public static class LlmCallEndpoints
{
    public sealed record CallSummary(Guid Id, DateTimeOffset CreatedAt, string Kind, string ModelId, string Vendor,
        string Outcome, string Category, long PromptTokens, long CompletionTokens, decimal Cost, string Currency,
        long DurationMs, int Pages);

    public sealed record Call(Guid Id, Guid AccountId, Guid? DeviceId, DateTimeOffset CreatedAt, string Kind,
        string ModelId, string Vendor, string Outcome, string Category, long PromptTokens, long CompletionTokens,
        bool ThinkingEnabled, decimal Cost, string Currency, long DurationMs, int Pages, bool PromptPurged,
        string? PromptBody, string? ResponseBody, string? ThinkingBody);

    // Property-mapped, not a positional record: Npgsql reads text[] as System.Array, which
    // no constructor parameter matches, while a string[] property takes it.
    private sealed class Row
    {
        public Guid Id { get; init; }
        public Guid AccountId { get; init; }
        public Guid? DeviceId { get; init; }
        public DateTime CreatedAt { get; init; }
        public string Kind { get; init; } = "";
        public string ModelId { get; init; } = "";
        public string Vendor { get; init; } = "";
        public string Outcome { get; init; } = "";
        public string Category { get; init; } = "";
        public long PromptTokens { get; init; }
        public long CompletionTokens { get; init; }
        public bool ThinkingEnabled { get; init; }
        public decimal Cost { get; init; }
        public string Currency { get; init; } = "";
        public long DurationMs { get; init; }
        public string? PromptSha256 { get; init; }
        public string[]? PromptPageSha256s { get; init; }
        public string? PromptBody { get; init; }
        public string? ResponseBody { get; init; }
        public string? ThinkingBody { get; init; }

        public IReadOnlyList<string> PageShas =>
            PromptSha256 is null ? [] : [PromptSha256, .. PromptPageSha256s ?? []];
    }

    private const string Columns =
        "id, account_id AS AccountId, device_id AS DeviceId, created_at AS CreatedAt, kind, model_id AS ModelId, vendor, " +
        "outcome, category, prompt_tokens AS PromptTokens, completion_tokens AS CompletionTokens, " +
        "thinking_enabled AS ThinkingEnabled, cost, currency, duration_ms AS DurationMs, prompt_sha256 AS PromptSha256, " +
        "prompt_page_sha256s AS PromptPageSha256s";

    public static void Map(RouteGroupBuilder api)
    {
        api.MapGet("/accounts/{id}/llm-calls", ListForAccount).AccessLogged("llm-calls", "id");
        api.MapGet("/llm-calls/{id}", GetCall).AccessLogged("llm-call", "id");
        api.MapGet("/llm-calls/{id}/pages/{page:int}", GetPage).AccessLogged("llm-prompt-image", "id");
    }

    private static async Task<IResult> ListForAccount(string id, DateTimeOffset? before, int? limit, Db db)
    {
        if (!Guid.TryParse(id, out var accountId))
        {
            return Results.NotFound();
        }
        var take = Math.Clamp(limit ?? 50, 1, 200);
        await using var c = db.ApiRead();
        var rows = await c.QueryAsync<Row>(
            $"SELECT {Columns}, NULL AS PromptBody, NULL AS ResponseBody, NULL AS ThinkingBody FROM llm_calls " +
            "WHERE account_id = @accountId AND (@before::timestamptz IS NULL OR created_at < @before) " +
            "ORDER BY created_at DESC LIMIT @take",
            new { accountId, before = before?.UtcDateTime, take });
        return Results.Ok(rows.Select(r => new CallSummary(r.Id, Utc(r.CreatedAt), r.Kind, r.ModelId, r.Vendor, r.Outcome,
            r.Category, r.PromptTokens, r.CompletionTokens, r.Cost, r.Currency, r.DurationMs, r.PageShas.Count)));
    }

    private static async Task<IResult> GetCall(string id, Db db)
    {
        var row = await FindAsync(db, id, withBodies: true);
        if (row is null)
        {
            return Results.NotFound();
        }
        return Results.Ok(new Call(row.Id, row.AccountId, row.DeviceId, Utc(row.CreatedAt), row.Kind, row.ModelId,
            row.Vendor, row.Outcome, row.Category, row.PromptTokens, row.CompletionTokens, row.ThinkingEnabled, row.Cost,
            row.Currency, row.DurationMs, row.PageShas.Count, row.PageShas.Count == 0, row.PromptBody, row.ResponseBody,
            row.ThinkingBody));
    }

    private static async Task<IResult> GetPage(string id, int page, Db db, IBlobReader blobs, CancellationToken ct)
    {
        var row = await FindAsync(db, id, withBodies: false);
        if (row is null || page < 0 || page >= row.PageShas.Count)
        {
            return Results.NotFound();
        }
        var bytes = await blobs.ReadAsync(BlobKeys.LlmPrompt(row.AccountId, row.PageShas[page]), ct);
        return bytes is null ? Results.NotFound() : Results.File(bytes, "image/jpeg");
    }

    private static async Task<Row?> FindAsync(Db db, string id, bool withBodies)
    {
        if (!Guid.TryParse(id, out var callId))
        {
            return null;
        }
        await using var c = db.ApiRead();
        var bodies = withBodies
            ? "prompt_body AS PromptBody, response_body AS ResponseBody, thinking_body AS ThinkingBody"
            : "NULL AS PromptBody, NULL AS ResponseBody, NULL AS ThinkingBody";
        return await c.QuerySingleOrDefaultAsync<Row>(
            $"SELECT {Columns}, {bodies} FROM llm_calls WHERE id = @callId", new { callId });
    }

    private static DateTimeOffset Utc(DateTime value) => new(DateTime.SpecifyKind(value, DateTimeKind.Utc));
}
