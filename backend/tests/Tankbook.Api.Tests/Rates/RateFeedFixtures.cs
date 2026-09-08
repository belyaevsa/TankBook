using System.Net;

namespace Tankbook.Api.Tests;

/// <summary>
/// Shared plumbing for the feed tests that run against REAL captured responses
/// (the model RV.15 set: the bytes are the evidence, so the fixture itself is
/// asserted and a later recapture cannot quietly invalidate a test).
/// </summary>
public static class RateFeedFixtures
{
    public static string Path(string name) =>
        System.IO.Path.Combine(AppContext.BaseDirectory, "Rates", "Fixtures", name);

    public static byte[] Bytes(string name) => File.ReadAllBytes(Path(name));
}

/// <summary>
/// A handler that answers the way the real endpoint does: it looks at the query
/// string and serves the fixture captured for THAT date, falling back to the
/// "today" fixture when the request names no date it knows - which is exactly
/// what cbr.ru and nationalbank.kz do with a missing or unknown date parameter.
///
/// This routing is the point. A stub that returned one body for every request
/// would pass whether or not the feed passes its date parameter, which is the
/// bug RV.20 fixed. Here, dropping the parameter means the past-date tests get
/// today's document and go red.
/// </summary>
public sealed class FixtureRoutingHandler : HttpMessageHandler
{
    private readonly IReadOnlyList<(string Marker, string Fixture)> _routes;
    private readonly string _fallback;

    /// <summary>The URIs this handler was asked for, in order - so a test can assert the request itself.</summary>
    public List<Uri> Requests { get; } = [];

    public FixtureRoutingHandler(string fallbackFixture, params (string Marker, string Fixture)[] routes)
    {
        _fallback = fallbackFixture;
        _routes = routes;
    }

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var uri = request.RequestUri!;
        Requests.Add(uri);

        var fixture = _fallback;
        foreach (var route in _routes)
        {
            if (uri.Query.Contains(route.Marker, StringComparison.Ordinal))
            {
                fixture = route.Fixture;
                break;
            }
        }

        return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = new ByteArrayContent(RateFeedFixtures.Bytes(fixture)),
        });
    }
}

/// <summary>
/// The ECB counterpart to <see cref="FixtureRoutingHandler"/>: ECB's three files
/// differ by PATH, not by query string (daily vs hist-90d vs hist), so the
/// fixture for a request is chosen by which file path it names. <paramref name="fallbackFixture"/>
/// lets a test serve one file for every path - the shape that proves a feed
/// would still never leak today's row onto another date, because the row guard
/// lives in the parser, not in the URL.
/// </summary>
public sealed class PathRoutingHandler : HttpMessageHandler
{
    private readonly IReadOnlyList<(string Marker, string Fixture)> _routes;
    private readonly string? _fallbackFixture;

    /// <summary>The URIs this handler was asked for, in order - so a test can assert how many upstream requests a pass made and which files it touched.</summary>
    public List<Uri> Requests { get; } = [];

    public PathRoutingHandler(IEnumerable<(string Marker, string Fixture)> routes, string? fallbackFixture = null)
    {
        _routes = routes.ToArray();
        _fallbackFixture = fallbackFixture;
    }

    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var uri = request.RequestUri!;
        Requests.Add(uri);

        foreach (var route in _routes)
        {
            if (uri.AbsolutePath.Contains(route.Marker, StringComparison.Ordinal))
            {
                return Ok(route.Fixture);
            }
        }

        // A path this handler does not know is 404 unless a fallback was given:
        // a feed reaching for a file the test did not stub is a failure the test
        // should see, not a silent empty.
        return _fallbackFixture is null
            ? Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound))
            : Ok(_fallbackFixture);

        static Task<HttpResponseMessage> Ok(string fixture) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new ByteArrayContent(RateFeedFixtures.Bytes(fixture)),
            });
    }
}
