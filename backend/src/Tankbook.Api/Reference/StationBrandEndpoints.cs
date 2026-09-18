using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Tankbook.Api.Catalog;
using Tankbook.Api.Http;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Reference;

/// <summary>
/// GET /v1/reference/station-brands (docs/API.md "GET /reference/station-brands").
/// PUBLIC - no auth, no account - because a signed-out user importing a file
/// needs the vocabulary too. The same contract as GET /catalog: a full pack or
/// a delta above <c>since_version</c> (bounded by <see cref="CatalogOptions.MaxDeltaEntries"/>),
/// every response naming its <c>kind</c>, ETag'd and cacheable. The server
/// serves rows and reads no meaning: the matching, and the relevance ordering,
/// run on the device (hard rule 9), and there is no query parameter that would
/// make a public pack vary per request (no geo, no per-user state).
/// </summary>
public static class StationBrandEndpoints
{
    private static readonly JsonSerializerOptions WireJson = new(JsonSerializerDefaults.Web);

    public static async Task<IResult> GetStationBrands(
        [FromQuery(Name = "since_version")] string? sinceVersion,
        StationBrandRepository repository,
        IOptions<CatalogOptions> options,
        HttpContext httpContext,
        CancellationToken cancellationToken)
    {
        int? since = null;
        if (sinceVersion is not null)
        {
            if (!int.TryParse(sinceVersion, out var parsed) || parsed < 0)
            {
                return ProblemResponses.Problem(
                    StatusCodes.Status400BadRequest,
                    TankbookErrorCodes.PayloadInvalid,
                    "Invalid station brands request.",
                    "The 'since_version' query parameter must be a non-negative integer, or be omitted for a full pack.");
            }

            since = parsed;
        }

        var current = await repository.GetCurrentPackVersionAsync(cancellationToken);
        var isFull = since is null;
        IReadOnlyList<StationBrandRow> brands;
        if (since is null)
        {
            brands = await repository.GetFullPackAsync(cancellationToken);
        }
        else if (since >= current)
        {
            brands = [];
        }
        else
        {
            var deltaCount = await repository.GetDeltaCountAsync(since.Value, cancellationToken);
            if (deltaCount <= options.Value.MaxDeltaEntries)
            {
                brands = await repository.GetDeltaAsync(since.Value, cancellationToken);
            }
            else
            {
                isFull = true;
                brands = await repository.GetFullPackAsync(cancellationToken);
            }
        }

        var body = JsonSerializer.Serialize(
            new StationBrandsResponse(
                current,
                brands.Select(b => new StationBrandResponse(b.Id, b.Name, b.Country, b.Aliases)).ToList(),
                isFull ? "full" : "delta"),
            WireJson);

        httpContext.Response.Headers.CacheControl = CatalogEndpoints.CacheControl;
        var etag = EtagHelpers.ComputeEtag(body);
        httpContext.Response.Headers.ETag = etag;
        if (EtagHelpers.IfNoneMatchMatches(httpContext.Request, etag))
        {
            return Results.StatusCode(StatusCodes.Status304NotModified);
        }

        return Results.Text(body, "application/json");
    }

    private sealed record StationBrandsResponse(int PackVersion, IReadOnlyList<StationBrandResponse> Brands, string Kind);

    private sealed record StationBrandResponse(string Id, string Name, string Country, string[] Aliases);
}
