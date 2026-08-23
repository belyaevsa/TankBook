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

    [Fact]
    public async Task NonHealthRequest_LogsAtInformation()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var context = LoggingTestHelpers.NewContext(services, path: "/v1/regular");
        LoggingTestHelpers.SetRoute(context, "/v1/regular");
        var middleware = LoggingTestHelpers.BuildMiddleware(services);

        await middleware.InvokeAsync(context);

        var requestLine = writer.JsonLines().RequestLine("/v1/regular");
        Assert.Equal("Information", requestLine.Prop("level"));
    }
}
