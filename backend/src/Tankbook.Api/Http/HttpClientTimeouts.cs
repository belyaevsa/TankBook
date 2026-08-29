namespace Tankbook.Api.Http;

/// <summary>
/// Named timeouts for the server's outbound HTTP clients (docs/PRACTICES.md U6,
/// §6 "Timeouts, backoff and poll intervals are operational"). Every value here
/// is a **compiled constant** on purpose: transport timeouts may never be
/// remote-configurable - a remote-set 0 s timeout is a remote-triggered outage.
///
/// The ASP.NET Core <see cref="System.Net.Http.HttpClient.Timeout"/> default is
/// 100 s. A slow feed under that default pins a background job thread; a slow
/// JWKS fetch stalls every sign-in behind it. Each outbound role gets its own
/// named client with a budget that fits its caller, rather than one number
/// pretending to fit everything.
/// </summary>
public static class HttpClientTimeouts
{
    /// <summary>
    /// The exchange-rate feeds (ECB / CIS). A background job with no user
    /// waiting, so a generous-but-bounded budget: long enough for a slow feed,
    /// short enough that a dead feed stops pinning the job thread at the 100 s
    /// default.
    /// </summary>
    public static readonly TimeSpan RateFeed = TimeSpan.FromSeconds(30);

    /// <summary>
    /// The Apple/Google JWKS fetch. This runs behind the first sign-in from a
    /// cold cache, so every sign-in is stalled while it is stuck. Short on
    /// purpose: the keys are public, cached for <c>JwksCacheMinutes</c>, and a
    /// stall here is a stall for the user.
    /// </summary>
    public static readonly TimeSpan Jwks = TimeSpan.FromSeconds(15);

    /// <summary>
    /// APNs push sends. HTTP/2 to Apple's push endpoint; a healthy send is
    /// sub-second, so a 30 s cap is generous headroom, never a floor.
    /// </summary>
    public static readonly TimeSpan Apns = TimeSpan.FromSeconds(30);
}
