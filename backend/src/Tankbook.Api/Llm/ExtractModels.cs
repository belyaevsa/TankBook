namespace Tankbook.Api.Llm;

/// <summary>POST /extract request body (docs/API.md "LLM gateway (Pro)").</summary>
public sealed record ExtractRequest(string? Kind, string? Image, ExtractHints? Hints);

/// <summary>The document kinds the gateway accepts (docs/API.md). Anything else is a 400.</summary>
public static class ExtractKinds
{
    public static readonly IReadOnlySet<string> Valid =
        new HashSet<string>(StringComparer.Ordinal) { "receipt", "pump", "chargeScreenshot", "invoice" };

    public static bool IsValid(string? kind) => kind is not null && Valid.Contains(kind);
}

/// <summary>One extracted field on the wire: an opaque value plus its confidence (docs/SCHEMA.md FieldExtraction).</summary>
public sealed record ExtractFieldResponse(object? Value, double Confidence);

/// <summary>
/// POST /extract response - exactly the <c>ExtractionMeta</c> shape from
/// docs/SCHEMA.md: a map of FieldRef to <c>{ value, confidence }</c> plus the
/// pipeline id. The server returns the provider's fields verbatim, including
/// low-confidence ones; a low-confidence field is "uncertain", never "absent",
/// and dropping it would change the claim (hard rule 13).
/// </summary>
public sealed record ExtractResponse(IReadOnlyDictionary<string, ExtractFieldResponse> Fields, string Pipeline);
