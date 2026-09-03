namespace Tankbook.Api.Rates;

/// <summary>One published quote: 1 base = <c>Rate</c> units of <c>Quote</c> (docs/SCHEMA.md Money: rate is original-per-home).</summary>
public sealed record RateQuote(string Quote, decimal Rate);

/// <summary>The stable source tags stored in exchange_rates.source.</summary>
public static class RateSources
{
    public const string Ecb = "ecb";
    public const string Cis = "cis";

    /// <summary>The National Bank of Kazakhstan - the authoritative publisher of KZT (RV.19). See <see cref="NbkRateFeed"/>.</summary>
    public const string Nbk = "nbk";

    /// <summary>The suffix a carried-forward source tag bears (RV.36: a carried row is a replaceable placeholder, not a permanent one).</summary>
    public const string CarriedSuffix = ":carried-forward";

    /// <summary>The source tag for a row that carries the last published value forward across a non-publishing day.</summary>
    public static string Carried(string source) => source + CarriedSuffix;

    /// <summary>True when the source tag marks a carried-forward row rather than a published one.</summary>
    public static bool IsCarried(string source) => source.Contains(CarriedSuffix, StringComparison.Ordinal);
}

/// <summary>
/// The exchange-rate feed seam (docs/TESTING.md "mock the boundary"): every
/// third-party rate source sits behind this interface, so the L2 suite can swap
/// in a recording double and never touch the ECB/CIS network. A feed returns the
/// quotes it published for one (date, base) pair - empty when it published
/// nothing that day (weekend, holiday, or an unsupported base). The production
/// implementations (<see cref="EcbRateFeed"/>, <see cref="CisRateFeed"/>) do the
/// HTTP; nothing above this interface knows the provider.
/// </summary>
public interface IRateFeed
{
    /// <summary>The stable source tag written to exchange_rates.source for a published row.</summary>
    string Source { get; }

    /// <summary>The quotes published for this date and base currency, expressed as 1 base = rate quote units.</summary>
    Task<IReadOnlyList<RateQuote>> FetchAsync(DateOnly date, string baseCurrency, CancellationToken cancellationToken);
}
