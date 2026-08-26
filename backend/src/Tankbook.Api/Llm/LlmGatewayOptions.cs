namespace Tankbook.Api.Llm;

/// <summary>
/// LLM gateway configuration (docs/API.md "LLM gateway (Pro)"). Bound from the
/// "LlmGateway" configuration section; environment variables use the
/// LlmGateway__MaxImageBytes, LlmGateway__BaseUrl, ... form. The provider key
/// and endpoint are server-side only (docs/SECURITY.md - the whole reason this
/// gateway exists is so the key never ships in an app bundle); appsettings.json
/// carries empty placeholders and the platform secret store supplies the values.
/// The per-tier allowance is a request count per period keyed by the tier name
/// stored in accounts.llm_tier (migration 010). A tier absent from the map, or
/// present with a zero allowance, has no LLM access at all (402); a tier with an
/// allowance that is spent for the current period answers 429.
/// </summary>
public sealed class LlmGatewayOptions
{
    public const string SectionName = "LlmGateway";

    /// <summary>Cap on the base64 image body, docs/API.md "POST /extract": 4 MB.</summary>
    public long MaxImageBytes { get; set; } = 4L * 1024 * 1024;

    /// <summary>Per-tier, per-period request allowance (the "quota" in GET /account).</summary>
    public Dictionary<string, int> TierRequestsPerPeriod { get; set; } =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["free"] = 0,
            ["pro"] = 200,
        };

    /// <summary>The OpenAI-compatible chat-completions base URL (server-side secret store).</summary>
    public string? BaseUrl { get; set; }

    /// <summary>The provider API key (server-side secret store; never logged, hard rule 12).</summary>
    public string? ApiKey { get; set; }

    /// <summary>The model id to call (e.g. a vision model); configuration, not a code decision.</summary>
    public string? ModelId { get; set; }

    /// <summary>The per-period allowance for a tier, or null when the tier is not entitled at all.</summary>
    public int? AllowanceFor(string? tier)
    {
        if (tier is null || !TierRequestsPerPeriod.TryGetValue(tier, out var allowance) || allowance <= 0)
        {
            return null;
        }

        return allowance;
    }
}
