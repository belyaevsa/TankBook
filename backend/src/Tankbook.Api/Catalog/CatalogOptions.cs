namespace Tankbook.Api.Catalog;

/// <summary>
/// Vehicle catalog service configuration (docs/SYNC.md "Reference data",
/// docs/API.md "Vehicle catalog"). Bound from the "Catalog" configuration
/// section; environment variables use the Catalog__AdminToken form.
/// </summary>
public sealed class CatalogOptions
{
    public const string SectionName = "Catalog";

    /// <summary>
    /// The operator token that gates the publish path (POST /v1/catalog/publish).
    /// A server-side secret: it lives in the platform secret store, never in
    /// appsettings.json (which holds an empty placeholder); only a dev-only
    /// default sits in appsettings.Development.json (docs/SECURITY.md). Empty in
    /// production means the publish endpoint answers 503 - curation is disabled.
    /// </summary>
    public string? AdminToken { get; set; }

    /// <summary>
    /// The delta-vs-full-pack rule (docs/API.md "Vehicle catalog"): GET /catalog
    /// serves a delta only when the set of entries changed since the client's
    /// version fits within this bound; a client whose delta would exceed it is
    /// treated as too far behind and gets the full pack instead. A stated,
    /// testable threshold - not an accidental one.
    /// </summary>
    public int MaxDeltaEntries { get; set; } = 50;
}
