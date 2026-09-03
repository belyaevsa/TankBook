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

    /// <summary>
    /// How far BACK the demand-driven backfill will carry a missing date from the
    /// most recent earlier published rate (docs/SCHEMA.md "Exchange rates"). 14 is
    /// measured, not assumed: CBR does not publish across the Russian New Year -
    /// date_req for 01, 05, 08, 09, 10 and 12 January 2026 all return the document
    /// dated 31.12.2025, and the first January document is 13.01.2026, a 13-day
    /// gap. A date whose last known rate is further back stays absent rather than
    /// taking a stale, unrelated rate into someone's cost history.
    /// </summary>
    public int CarryBackWindowDays { get; set; } = 14;

    /// <summary>How many pending (date, base) rows one backfill pass fetches before stopping, bounding the upstream burst.</summary>
    public int BackfillBatchSize { get; set; } = 50;

    /// <summary>How often the backfill hosted service runs a pass over the pending queue. Shorter than the daily job because it is demand-driven and the device is waiting on its next refresh.</summary>
    public int BackfillIntervalMinutes { get; set; } = 5;

    public TimeSpan JobInterval => TimeSpan.FromMinutes(JobIntervalMinutes);

    public TimeSpan BackfillInterval => TimeSpan.FromMinutes(BackfillIntervalMinutes);
}
