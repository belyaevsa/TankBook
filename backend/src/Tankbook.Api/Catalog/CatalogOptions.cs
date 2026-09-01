namespace Tankbook.Api.Catalog;

/// <summary>
/// Vehicle catalog service configuration (docs/SYNC.md "Reference data",
/// docs/API.md "Vehicle catalog"). Bound from the "Catalog" configuration
/// section; environment variables use the Catalog__MaxDeltaEntries form.
/// </summary>
public sealed class CatalogOptions
{
    public const string SectionName = "Catalog";

    /// <summary>
    /// The delta-vs-full-pack rule (docs/API.md "Vehicle catalog"): GET /catalog
    /// serves a delta only when the set of entries changed since the client's
    /// version fits within this bound; a client whose delta would exceed it is
    /// treated as too far behind and gets the full pack instead. A stated,
    /// testable threshold - not an accidental one.
    /// </summary>
    public int MaxDeltaEntries { get; set; } = 50;
}
