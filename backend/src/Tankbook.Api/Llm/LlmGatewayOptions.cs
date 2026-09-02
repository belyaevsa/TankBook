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

    /// <summary>
    /// The per-day allowance the config document advertises as
    /// <c>llmQuota.cloudFallback</c> - in migration 003's baseline, in
    /// `Config.default.json`, and therefore in every client. The free tier is
    /// granted exactly this, so the promise and the gate cannot disagree; a test
    /// pins the two together.
    /// </summary>
    public const int AdvertisedCloudFallbackPerDay = 50;

    /// <summary>Per-tier, per-period request allowance (the "quota" in GET /account).</summary>
    /// <remarks>
    /// **The free tier gets cloud extract in v1 (decided 2026-09-03, product
    /// owner).** It was 0, which made `POST /extract` answer 402 to every user -
    /// correct against `API.md`'s "LLM gateway (Pro)", but Pro is cut from v1
    /// (`P6.16`), so the gate applied to nobody and refused everyone, while the
    /// served config document promised `cloudFallback: 50`. The server and the
    /// document now agree.
    ///
    /// It matters because of what the alternative costs: with cloud extract off,
    /// capture runs on on-device Vision alone, which the corpus measures at
    /// **38.3%** on receipts against the cloud model's 84/96 (`P4.12`) - the
    /// difference between a head start and a retype.
    ///
    /// The period is a DAY (`LlmService` keys usage on `DateOnly`), so this is
    /// 50 extractions per account per day, and it is configuration
    /// (`LlmGateway__TierRequestsPerPeriod__free`) rather than a code decision -
    /// lower it without a deploy if the provider bill says so.
    /// </remarks>
    public Dictionary<string, int> TierRequestsPerPeriod { get; set; } =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ["free"] = AdvertisedCloudFallbackPerDay,
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
