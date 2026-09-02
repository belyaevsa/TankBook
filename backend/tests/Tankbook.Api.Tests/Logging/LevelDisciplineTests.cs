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
