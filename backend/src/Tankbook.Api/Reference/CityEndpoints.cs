using System.Reflection;
using Tankbook.Api.Catalog;
using Tankbook.Api.Http;

namespace Tankbook.Api.Reference;

/// <summary>
/// GET /v1/reference/cities (docs/API.md "GET /reference/cities"): the city
/// dictionary the device suggests and picks a car's home city from. PUBLIC and
/// ETag'd, with no query parameter - a public pack that never varies per
/// request, so the server learns nothing about who asks or where they are. The
/// body is the committed dictionary file, embedded at build time: a correction
/// is a commit and a backend deploy, never an app release, and the device keeps
/// whichever of its bundled copy and this pack has the higher version.
/// </summary>
public static class CityEndpoints
{
    private const string ResourceName = "Tankbook.Api.Reference.Cities.seed.json";

    private static readonly Lazy<(string Body, string Etag)> Pack = new(() =>
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName)
            ?? throw new InvalidOperationException($"embedded resource {ResourceName} is missing");
        using var reader = new StreamReader(stream);
        var body = reader.ReadToEnd();
        return (body, EtagHelpers.ComputeEtag(body));
    });

    public static IResult GetCities(HttpContext httpContext)
    {
        var (body, etag) = Pack.Value;
        httpContext.Response.Headers.CacheControl = CatalogEndpoints.CacheControl;
        httpContext.Response.Headers.ETag = etag;
        if (EtagHelpers.IfNoneMatchMatches(httpContext.Request, etag))
        {
            return Results.StatusCode(StatusCodes.Status304NotModified);
        }

        return Results.Text(body, "application/json");
    }
}
