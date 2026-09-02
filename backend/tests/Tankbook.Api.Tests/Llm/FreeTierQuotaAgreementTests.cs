using Tankbook.Api.Llm;
using Xunit;

namespace Tankbook.Api.Tests.Llm;

/// <summary>
/// The gate and the promise must agree (RV.4).
/// </summary>
/// <remarks>
/// Until 2026-09-03 the free tier's allowance was 0, so <c>POST /extract</c>
/// answered 402 to every user - while the config document the same server serves
/// advertised <c>llmQuota.cloudFallback: 50</c>. Both halves were individually
/// correct and the pair was a lie, which nothing detected because no test looked
/// at both. That is the same seam every RV bug lives in.
/// </remarks>
public class FreeTierQuotaAgreementTests
{
    /// <summary>
    /// The number migration 003 seeds into the baseline document, and the same
    /// number ios/Sources/TankbookCore/Config/Config.default.json ships. Written
    /// as a literal on purpose: if the migration changes, this fails and someone
    /// has to look at the tier table too.
    /// </summary>
    private const int AdvertisedCloudFallback = 50;

    [Fact]
    public void FreeTierGetsWhatTheConfigDocumentAdvertises()
    {
        var options = new LlmGatewayOptions();

        Assert.Equal(AdvertisedCloudFallback, LlmGatewayOptions.AdvertisedCloudFallbackPerDay);
        Assert.Equal(AdvertisedCloudFallback, options.AllowanceFor("free"));
    }

    [Fact]
    public void FreeTierIsEntitledAtAll()
    {
        // AllowanceFor returns null for a tier with no entitlement, which is what
        // produced the 402. Asserted separately from the number: a future change
        // to zero would still satisfy an equality check against a zero constant.
        Assert.NotNull(new LlmGatewayOptions().AllowanceFor("free"));
    }

    [Fact]
    public void AnUnknownTierIsStillRefused()
    {
        // Granting the free tier must not accidentally grant everyone: an
        // unrecognised tier has no entitlement and still answers 402.
        Assert.Null(new LlmGatewayOptions().AllowanceFor("enterprise"));
        Assert.Null(new LlmGatewayOptions().AllowanceFor(null));
    }
}
