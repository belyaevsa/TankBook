using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Tankbook.Api.Http;

namespace Tankbook.Api.Catalog;

/// <summary>
/// GET /v1/catalog and POST /v1/catalog/publish (docs/API.md "Vehicle catalog",
/// docs/SYNC.md "Reference data"). GET is PUBLIC - no auth, no account - because
/// a signed-out user's Add-car autocomplete needs the dictionary too. It serves a
/// delta (entries changed since the client's version) or a full pack, per the
/// stated rule in <see cref="GetCatalog"/>, is ETag'd, and answers 304 when the
/// catalog has not changed. POST is an OPERATOR surface, not a public one: it is
/// gated on the <c>Catalog:AdminToken</c> server-side secret
/// (docs/SECURITY.md), never on a user account.
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
            entries = deltaCount <= options.Value.MaxDeltaEntries
                ? await repository.GetDeltaAsync(since.Value, cancellationToken)
                : await repository.GetFullPackAsync(cancellationToken);
        }

        var body = JsonSerializer.Serialize(
            new CatalogResponse(current, entries.Select(ToResponse).ToList()),
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

    /// <summary>
    /// The operator publish path (docs/API.md "Vehicle catalog"). Gated on the
    /// <c>Catalog:AdminToken</c> secret; a server with no token configured
    /// answers 503 - curation is disabled. The pack is validated against its
    /// schema and the version is checked monotonic before anything is written,
    /// whole or not at all: a refused pack leaves the previously published pack
    /// serving untouched.
    /// </summary>
    public static async Task<IResult> Publish(
        CatalogPublishService publish,
        IOptions<CatalogOptions> options,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        var configuredToken = options.Value.AdminToken;
        if (string.IsNullOrWhiteSpace(configuredToken))
        {
            return Results.Problem(
                statusCode: StatusCodes.Status503ServiceUnavailable,
                title: "Catalog curation is not configured.",
                detail: "Catalog:AdminToken is unset; the publish path is disabled.");
        }

        var provided = httpContext.Request.Headers["X-Admin-Token"].ToString();
        if (!TokenMatches(configuredToken, provided))
        {
            return Results.Problem(
                statusCode: StatusCodes.Status401Unauthorized,
                title: "Unauthorized.",
                detail: "A valid Catalog:AdminToken is required to publish a catalog pack.");
        }

        var packJson = await new StreamReader(httpContext.Request.Body).ReadToEndAsync(cancellationToken);
        var result = await publish.PublishAsync(packJson, cancellationToken);

        if (!result.IsSuccess)
        {
            return result.Error.Kind switch
            {
                CatalogPublishErrorKind.InvalidDocument => Results.Problem(
                    statusCode: StatusCodes.Status400BadRequest,
                    title: "Invalid catalog pack.",
                    detail: result.Error.Detail),
                CatalogPublishErrorKind.SchemaValidationFailed => Results.Problem(
                    statusCode: StatusCodes.Status400BadRequest,
                    title: "The catalog pack failed its schema.",
                    detail: result.Error.Detail),
                CatalogPublishErrorKind.VersionNotMonotonic => Results.Problem(
                    statusCode: StatusCodes.Status409Conflict,
                    title: "Pack version rejected.",
                    detail: result.Error.Detail),
                _ => Results.Problem(
                    statusCode: StatusCodes.Status400BadRequest,
                    title: "Catalog publish refused.",
                    detail: result.Error.Detail),
            };
        }

        return Results.Json(
            new PublishResponse(result.Version, result.EntriesPublished),
            WireJson,
            statusCode: StatusCodes.Status200OK);
    }

    private static CatalogEntryResponse ToResponse(CatalogEntryRow row)
        => new(
            row.Id,
            row.Make,
            row.Model,
            row.Generation,
            row.YearsStart is int start && row.YearsEnd is int end ? new[] { start, end } : null,
            row.Powertrain,
            row.FuelKinds,
            row.TankCapacityL,
            row.BatteryCapacityKwh);

    private static bool TokenMatches(string configured, string provided)
    {
        if (string.IsNullOrEmpty(provided))
        {
            return false;
        }

        var expected = Encoding.UTF8.GetBytes(configured);
        var actual = Encoding.UTF8.GetBytes(provided);
        return expected.Length == actual.Length
            && CryptographicOperations.FixedTimeEquals(expected, actual);
    }

    private static IResult InvalidRequest(string detail)
        => Results.Problem(statusCode: StatusCodes.Status400BadRequest, title: "Invalid catalog request.", detail: detail);

    private sealed record CatalogResponse(int PackVersion, IReadOnlyList<CatalogEntryResponse> Entries);

    private sealed record CatalogEntryResponse(
        Guid Id,
        string Make,
        string Model,
        string? Generation,
        int[]? Years,
        string Powertrain,
        string[] FuelKinds,
        decimal? TankCapacityL,
        decimal? BatteryCapacityKwh);

    private sealed record PublishResponse(int PackVersion, int EntriesPublished);
}
