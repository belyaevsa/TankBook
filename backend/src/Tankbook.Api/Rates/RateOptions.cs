namespace Tankbook.Api.Rates;

/// <summary>
/// Exchange-rate service configuration (docs/SCHEMA.md "Reference data ->
/// Exchange rates"). Bound from the "Rates" configuration section; environment
/// variables use the Rates__BaseCurrencies, Rates__JobIntervalMinutes form.
/// </summary>
public sealed class RateOptions
{
    public const string SectionName = "Rates";

    /// <summary>
    /// The base currencies the daily job fetches quotes for. EUR covers the ECB
    /// feed (ECB publishes EUR base only) and the CIS feed's EUR-denominated
    /// quotes. Stored as-is in exchange_rates.base.
    /// </summary>
    public string[] BaseCurrencies { get; set; } = ["EUR"];

    /// <summary>How often the background job runs a pass. The pass is idempotent, so this is a liveness knob, not a correctness one.</summary>
    public int JobIntervalMinutes { get; set; } = 360;

    /// <summary>The largest inclusive date span GET /rates/pack will serve in one response; anything wider is a 400.</summary>
    public int MaxPackDays { get; set; } = 400;

    public TimeSpan JobInterval => TimeSpan.FromMinutes(JobIntervalMinutes);
}
