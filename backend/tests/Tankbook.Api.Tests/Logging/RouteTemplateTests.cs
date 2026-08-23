using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Tests;

/// <summary>
/// docs/LOGGING.md §3: the request line carries the route template, never the
/// concrete path, so ids stay out of logged paths. The middleware is invoked
/// directly with an Endpoint carrying the route pattern metadata
/// (docs/TESTING.md standing rule); no route is registered.
/// </summary>
public class RouteTemplateTests
{
    [Fact]
    public async Task ParameterizedRoute_LogsTemplate_NotConcreteId()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var context = LoggingTestHelpers.NewContext(services, path: "/v1/things/some-secret-id-42");
        LoggingTestHelpers.SetRoute(context, "/v1/things/{id}");
        var middleware = LoggingTestHelpers.BuildMiddleware(services);

        await middleware.InvokeAsync(context);

        var requestLine = writer.JsonLines().RequestLine("/v1/things/{id}");
        Assert.Equal("/v1/things/{id}", requestLine.Prop("path"));
        Assert.Equal("GET", requestLine.Prop("method"));

        var allOutput = string.Join('\n', writer.Lines);
        Assert.DoesNotContain("some-secret-id-42", allOutput);
    }

    [Fact]
    public async Task UnmatchedRoute_LogsUnmatched_NotARawPath()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        // No endpoint attached: the request never matched a route.
        var context = LoggingTestHelpers.NewContext(services, path: "/v1/totally/unknown");
        var middleware = LoggingTestHelpers.BuildMiddleware(services, next: ctx =>
        {
            ctx.Response.StatusCode = 404;
            return Task.CompletedTask;
        });

        await middleware.InvokeAsync(context);

        var requestLine = writer.JsonLines().RequestLine("unmatched");
        Assert.Equal("unmatched", requestLine.Prop("path"));
        Assert.Equal("404", requestLine.Prop("status"));

        // The raw URL must not leak into the log when there is no route.
        var allOutput = string.Join('\n', writer.Lines);
        Assert.DoesNotContain("/v1/totally/unknown", allOutput);
    }
}
