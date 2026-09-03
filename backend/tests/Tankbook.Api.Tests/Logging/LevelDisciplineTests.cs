using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Tests;

/// <summary>
/// docs/LOGGING.md §3 level discipline: health and readiness endpoints log at
/// DEBUG only, so they do not drown the stream. The middleware is invoked
/// directly on a DefaultHttpContext (docs/TESTING.md standing rule).
/// </summary>
public class LevelDisciplineTests
{
    [Fact]
    public async Task Health_ProducesNoInformationRequestLine()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var context = LoggingTestHelpers.NewContext(services, path: "/health");
        LoggingTestHelpers.SetRoute(context, "/health");
        var middleware = LoggingTestHelpers.BuildMiddleware(services);

        await middleware.InvokeAsync(context);

        var lines = writer.JsonLines().ToList();
        var healthRequestLines = lines
            .Where(l => l.Prop("event") == "http.request" && l.Prop("path") == "/health")
            .ToList();

        // The health request was logged (at DEBUG), and never at INFO or above.
        Assert.NotEmpty(healthRequestLines);
        Assert.All(healthRequestLines, l => Assert.Equal("Debug", l.Prop("level")));
        Assert.DoesNotContain(healthRequestLines, l => l.Prop("level") == "Information");
    }

    /// <summary>
    /// The per-request line is levelled by OUTCOME (2026-09-02), not by whether
    /// the route is /health.
    ///
    /// It used to be Information for every request, which buried the lines that
    /// say what actually happened - auth.session, sync.push, blob.commit - under
    /// one http.request per call. A production log nobody can read is not
    /// observability, so a SUCCESS is now Debug and only failures are surfaced.
    /// Nothing is lost: Logging:LogLevel:Default = Debug brings every request
    /// back, which is what `RequestLineStillEmittedAtDebug` below pins.
    ///
    /// All four outcomes are asserted together, because the earlier version of
    /// this test checked one and would have passed against a rule that levelled
    /// 5xx the same as 2xx.
    /// </summary>
    [Theory]
    [InlineData(200, "Debug")]
    [InlineData(204, "Debug")]
    [InlineData(400, "Information")]
    [InlineData(500, "Warning")]
    public async Task NonHealthRequest_IsLevelledByOutcome(int status, string expectedLevel)
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var context = LoggingTestHelpers.NewContext(services, path: "/v1/regular");
        LoggingTestHelpers.SetRoute(context, "/v1/regular");
        context.Response.StatusCode = status;
        var middleware = LoggingTestHelpers.BuildMiddleware(services);

        await middleware.InvokeAsync(context);

        var requestLine = writer.JsonLines().RequestLine("/v1/regular");
        Assert.Equal(expectedLevel, requestLine.Prop("level"));
    }

    /// <summary>
    /// RV.16: a request that matched NO endpoint logs at Debug, not at the
    /// Information its 404 would otherwise earn.
    ///
    /// The bug: on a public IP this is internet scanning, not a client. Measured
    /// in production on 2026-09-03, ~250 Information lines in 90 seconds -
    /// POSTs of 5 KB and 67 KB to routes this app has never had - which buried
    /// sync.push, blob.commit and llm.extract for the whole window.
    ///
    /// 404 and 405 are both asserted: an unmatched route can produce either
    /// (a wrong path, or a right path with the wrong method), and a rule keyed
    /// on the status code alone would catch one and miss the other. The rule is
    /// keyed on the ROUTE, which is why both must be Debug.
    /// </summary>
    [Theory]
    [InlineData(404)]
    [InlineData(405)]
    public async Task UnmatchedRoute_IsDebug_NotInformation(int status)
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var context = LoggingTestHelpers.NewContext(services, path: "/wp-login.php");
        // Deliberately NO SetRoute: no endpoint matched, which is the whole case.
        context.Response.StatusCode = status;
        var middleware = LoggingTestHelpers.BuildMiddleware(services);

        await middleware.InvokeAsync(context);

        var requestLine = writer.JsonLines().RequestLine(TraceCorrelationMiddleware.UnmatchedRoute);
        Assert.Equal("Debug", requestLine.Prop("level"));
    }

    /// <summary>
    /// The OTHER half, and the half that makes the pair a rule rather than a
    /// blanket mute: a 4xx from a REAL endpoint still logs at Information. That
    /// is a client of ours getting an answer it may need help with - a blob that
    /// is not there, an account that does not exist - and it is exactly what
    /// somebody reads the log for.
    ///
    /// Without this test, "unmatched is Debug" and "every 404 is Debug" are
    /// indistinguishable, and the second one loses real signal while looking
    /// like the fix.
    /// </summary>
    [Fact]
    public async Task MatchedRouteReturning404_StaysInformation()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var context = LoggingTestHelpers.NewContext(services, path: "/v1/blobs/deadbeef");
        LoggingTestHelpers.SetRoute(context, "/v1/blobs/{sha256}");
        context.Response.StatusCode = 404;
        var middleware = LoggingTestHelpers.BuildMiddleware(services);

        await middleware.InvokeAsync(context);

        var requestLine = writer.JsonLines().RequestLine("/v1/blobs/{sha256}");
        Assert.Equal("Information", requestLine.Prop("level"));
    }

    /// <summary>
    /// A 5xx on an unmatched route is still a Warning: the server broke while
    /// answering, and which route it was answering does not change that.
    /// Pins the ORDER of the arms - moving the unmatched arm above the 5xx one
    /// silently downgrades every such failure to Debug, and no other test here
    /// would notice.
    /// </summary>
    [Fact]
    public async Task UnmatchedRouteReturning500_IsStillWarning()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var context = LoggingTestHelpers.NewContext(services, path: "/nonsense");
        context.Response.StatusCode = 500;
        var middleware = LoggingTestHelpers.BuildMiddleware(services);

        await middleware.InvokeAsync(context);

        var requestLine = writer.JsonLines().RequestLine(TraceCorrelationMiddleware.UnmatchedRoute);
        Assert.Equal("Warning", requestLine.Prop("level"));
    }

    /// <summary>
    /// The audit trail is re-levelled, never removed: at Debug the successful
    /// request still produces its line, with its correlation fields intact.
    /// Without this, "quieter" and "gone" would be indistinguishable.
    /// </summary>
    [Fact]
    public async Task SuccessfulRequestLineIsStillEmittedAtDebug()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var context = LoggingTestHelpers.NewContext(services, path: "/v1/regular");
        LoggingTestHelpers.SetRoute(context, "/v1/regular");
        context.Response.StatusCode = 200;
        var middleware = LoggingTestHelpers.BuildMiddleware(services);

        await middleware.InvokeAsync(context);

        var requestLine = writer.JsonLines().RequestLine("/v1/regular");
        Assert.Equal("Debug", requestLine.Prop("level"));
        Assert.Equal("/v1/regular", requestLine.Prop("Path"));
    }
}
