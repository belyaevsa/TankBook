namespace Tankbook.Api.Llm;

/// <summary>The optional hints from the request body (docs/API.md "POST /extract").</summary>
public sealed record ExtractHints(
    string? Currency,
    string? Locale,
    IReadOnlyList<string>? VehicleFuelKinds);

/// <summary>One extracted field: an opaque value and a 0-1 confidence. The value is passed through, never judged (hard rule 9).</summary>
public sealed record LlmField(object? Value, double Confidence);

/// <summary>
/// The provider's answer for one image: the extracted fields plus the metering
/// facts the gateway must record (model id and token counts). The server maps
/// this straight onto the <c>ExtractionMeta</c> response shape and increments the
/// <c>llm_usage</c> ledger from the token counts - it never interprets a field.
/// <see cref="ResponseBody"/> and <see cref="ThinkingBody"/> feed the call
/// ledger (migration 015): the raw response the model returned and its thinking
/// trace when thinking was enabled. They are content and are stored only in the
/// ledger column, purged on account deletion and after 30 days - never logged
/// (hard rule 12).
/// </summary>
public sealed record LlmExtraction(
    IReadOnlyDictionary<string, LlmField> Fields,
    string Model,
    long PromptTokens,
    long CompletionTokens,
    string? ResponseBody = null,
    string? ThinkingBody = null)
{
    public long TotalTokens => PromptTokens + CompletionTokens;
}

/// <summary>
/// The model-provider seam (docs/TESTING.md "mock the boundary"). The cloud model
/// sits behind this interface so the L2 suite swaps in a recording double and
/// never makes a paid call; the real HTTP implementation
/// (<see cref="OpenAiCompatibleLlmProvider"/>) is never exercised by the suite.
/// The provider receives decoded image bytes, not the base64 envelope - the
/// gateway decodes once and the bytes live only for the request's duration.
/// </summary>
public interface ILlmProvider
{
    /// <summary>
    /// Extracts fields from one image. <paramref name="model"/> is the resolved
    /// <see cref="LlmModelChoice"/> for the kind (migration 014) - which model
    /// id to call, and whether that model supports thinking, so the provider can
    /// request and capture a thinking trace rather than being told nothing about
    /// the model it is about to spend money on.
    /// </summary>
    Task<LlmExtraction> ExtractAsync(
        string kind,
        byte[] imageBytes,
        ExtractHints hints,
        LlmModelChoice model,
        CancellationToken cancellationToken);
}
