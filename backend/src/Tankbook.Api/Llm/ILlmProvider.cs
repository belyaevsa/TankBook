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
/// </summary>
public sealed record LlmExtraction(
    IReadOnlyDictionary<string, LlmField> Fields,
    string Model,
    long PromptTokens,
    long CompletionTokens)
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
    Task<LlmExtraction> ExtractAsync(
        string kind,
        byte[] imageBytes,
        ExtractHints hints,
        CancellationToken cancellationToken);
}
