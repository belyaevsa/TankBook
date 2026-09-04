using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Tankbook.Api.Http;

namespace Tankbook.Api.Catalog;

/// <summary>
/// GET /v1/catalog (docs/API.md "Vehicle catalog", docs/SYNC.md "Reference
/// data"). PUBLIC - no auth, no account - because a signed-out user's Add-car
/// autocomplete needs the dictionary too. It serves a delta (entries changed
/// since the client's version) or a full pack, per the stated rule in
/// <see cref="GetCatalog"/>, is ETag'd, and answers 304 when the catalog has not
/// changed.
///
/// There is NO publish endpoint (removed 2026-09-01, product owner): catalog
/// packs are written directly to the database. <see cref="CatalogPublishService"/>
/// survives as the in-process path that does that writing, so the schema check
/// and the monotonic-version guard still apply to whatever performs the write -
/// they were never properties of the HTTP surface.
/// </summary>
public static class CatalogEndpoints
{
    public const string CacheControl = "public, max-age=300, must-revalidate";

    // Camel-case property names, matching the rest of the wire surface
    // (docs/API.md examples use packVersion / fuelKinds / etc.).
    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);

    /// <summary>
    /// The delta-vs-full-pack rule (docs/API.md "Vehicle catalog"): a client that
    /// sends the <c>since_version</c> it holds gets the entries changed since
    /// that version, unless the delta would be larger than the server is willing
    /// to send - more than <see cref="CatalogOptions.MaxDeltaEntries"/> changed
    /// entries means the client is too far behind and gets the full pack. A
    /// missing <c>since_version</c> (a fresh client or a seed refresh) gets the
    /// full pack by documented default. A <c>since_version</c> at or above the
    /// current version gets an honest empty delta with the current packVersion -
    /// never a fabricated entry, never a full pack pretending to be a delta.
    /// Every response names its kind with <c>kind: "full" | "delta"</c>, so a
    /// client can tell "here is everything" from "here is what changed" - the
    /// marker that makes entry withdrawal expressible (a full pack is
    /// authoritative and replaces the client's held set; a delta is an overlay).
    /// </summary>
    public static async Task<IResult> GetCatalog(
        [FromQuery(Name = "since_version")] string? sinceVersion,
        CatalogRepository repository,
        IOptions<CatalogOptions> options,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        int? since = null;
        if (sinceVersion is not null)
        {
            if (!int.TryParse(sinceVersion, out var parsed) || parsed < 0)
            {
                return InvalidRequest("The 'since_version' query parameter must be a non-negative integer, or be omitted for a full pack.");
            }

            since = parsed;
        }

        var current = await repository.GetCurrentPackVersionAsync(cancellationToken);

        // The response always says which kind it is (docs/API.md "Vehicle
        // catalog"): "full" means entries ARE the whole catalog - the client
        // replaces its held set with them, so an entry absent from the pack is
        // withdrawn - while "delta" means entries are only what changed since
        // the client's version and are overlaid, never removing anything
        // (docs/SYNC.md "Applying an update"). The marker is present on every
        // response, never inferred from an entry count or from the absence of
        // since_version.
        var isFull = since is null;
        IReadOnlyList<CatalogEntryRow> entries;
        if (since is null)
        {
            entries = await repository.GetFullPackAsync(cancellationToken);
        }
        else if (since >= current)
        {
            entries = [];
        }
        else
        {
            var deltaCount = await repository.GetDeltaCountAsync(since.Value, cancellationToken);
            if (deltaCount <= options.Value.MaxDeltaEntries)
            {
                entries = await repository.GetDeltaAsync(since.Value, cancellationToken);
            }
            else
            {
                isFull = true;
                entries = await repository.GetFullPackAsync(cancellationToken);
            }
        }

        var body = JsonSerializer.Serialize(
            new CatalogResponse(current, entries.Select(ToResponse).ToList(), isFull ? "full" : "delta"),
            WireJson);

        httpContext.Response.Headers.CacheControl = CacheControl;
        var etag = EtagHelpers.ComputeEtag(body);
        httpContext.Response.Headers.ETag = etag;

        if (EtagHelpers.IfNoneMatchMatches(httpContext.Request, etag))
        {
            return Results.StatusCode(StatusCodes.Status304NotModified);
        }

        return Results.Text(body, "application/json");
    }

    private static CatalogEntryResponse ToResponse(CatalogEntryRow row)
        => new(
            row.Id,
            row.Make,
            row.Model,
            row.Generation,
            // An open-ended model line - one still in production - has a start
            // year and NO end. Collapsing the pair to null because the end is
            // missing threw away a perfectly good start year, and the client
            // rendered the resulting "no years" as "0-" in Add-car autocomplete.
            // So the pair is [firstYear, lastYear] with a NULL last year for a
            // line still in production (docs/API.md "GET /catalog"); only a row
            // with no range at all is null.
            row.YearsStart is int start ? new int?[] { start, row.YearsEnd } : null,
            row.Powertrain,
            row.FuelKinds,
            row.TankCapacityL,
            row.BatteryCapacityKwh);

    private static IResult InvalidRequest(string detail)
        => Results.Problem(statusCode: StatusCodes.Status400BadRequest, title: "Invalid catalog request.", detail: detail);

    private sealed record CatalogResponse(int PackVersion, IReadOnlyList<CatalogEntryResponse> Entries, string Kind);

    private sealed record CatalogEntryResponse(
        Guid Id,
        string Make,
        string Model,
        string? Generation,
        int?[]? Years,
        string Powertrain,
        string[] FuelKinds,
        decimal? TankCapacityL,
        decimal? BatteryCapacityKwh);
}
