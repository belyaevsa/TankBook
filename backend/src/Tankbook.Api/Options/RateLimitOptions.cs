namespace Tankbook.Api.Options;

/// <summary>
/// Rate-limit configuration (docs/API.md "Rate limits", docs/PRACTICES.md S9,
/// PR.17). Bound from the "RateLimit" configuration section; environment
/// variables use the RateLimit__AuthSessionPerMinute form. The limits are
/// operational, so ops may tune them without a release - every default is
/// chosen so a real user can never hit it: a 429 here is an attacker or a bug,
/// never a busy human. Each default is a request count per one-minute fixed
/// window.
/// </summary>
public sealed class RateLimitOptions
{
    public const string SectionName = "RateLimit";

    /// <summary>
    /// Per-IP. Sign-in is rare (once, then retries on failure); even an
    /// aggressive retry-with-backoff stays far below 30/min. 30/min leaves a
    /// real human 30x headroom.
    /// </summary>
    public int AuthSessionPerMinute { get; set; } = 30;

    /// <summary>
    /// Per-IP. Refresh runs ~once/hour per device; a whole family of devices
    /// behind one NAT refreshing together stays far below 60/min.
    /// </summary>
    public int AuthRefreshPerMinute { get; set; } = 60;

    /// <summary>
    /// Per-IP. Import is a deliberate, one-file-at-a-time action. 20/min.
    /// </summary>
    public int ImportParsePerMinute { get; set; } = 20;

    /// <summary>
    /// Per-IP. POST /catalog/publish is the operator surface, not a user one.
    /// 30/min.
    /// </summary>
    public int CatalogPublishPerMinute { get; set; } = 30;

    /// <summary>
    /// Per-device. A capture-driven extract is about one per entry; the
    /// per-period LLM quota (docs/API.md, default 200/day for pro) is the real
    /// budget - this is only the flood guard. 30/min.
    /// </summary>
    public int ExtractPerMinute { get; set; } = 30;

    /// <summary>
    /// Per-device. Sync push is batched and debounced client-side; even a "sync
    /// now" burst stays well under this. Generous (120/min) because push is the
    /// hot path, but still bounds a flood to 2/s.
    /// </summary>
    public int SyncPushPerMinute { get; set; } = 120;

    /// <summary>
    /// Per-device. One begin per attachment; a bulk photo import is the only
    /// realistic burst. 120/min.
    /// </summary>
    public int BlobBeginPerMinute { get; set; } = 120;

    public static readonly TimeSpan Window = TimeSpan.FromMinutes(1);
}
