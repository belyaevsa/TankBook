using System.Net;
using System.Text.Json;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Tests;

/// <summary>
/// docs/LOGGING.md §7 correlation test: a client's traceId appears in the
/// server's request line, is echoed in the response header, and rides in the
/// problem+json body of an error response. Built as in-process units per
/// docs/TESTING.md - the middleware is invoked on a DefaultHttpContext and the
/// error path runs through an ApplicationBuilder pipeline, never a full host.
/// </summary>
public class CorrelationTests
{
    private const string Header = "X-Tankbook-Trace";

    [Fact]
    public async Task Request_WithTraceHeader_EchoesIdInResponseAndRequestLine()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        const string traceId = "7f3a5b1e-cd42-4f09-9a2b-1c2d3e4f5a6b";
        var context = LoggingTestHelpers.NewContext(services, path: "/health", traceId: traceId);
        LoggingTestHelpers.SetRoute(context, "/health");
        var middleware = LoggingTestHelpers.BuildMiddleware(services);

        await middleware.InvokeAsync(context);

        Assert.Equal(traceId, context.Response.Headers[Header].ToString());

        var requestLine = writer.JsonLines().RequestLine("/health");
        Assert.Equal(traceId, requestLine.Prop("traceId"));
    }

    [Fact]
    public async Task Request_WithoutTraceHeader_GeneratesTraceIdAndCarriesIt()
    {
        var (services, writer) = LoggingTestHelpers.BuildPipeline();
        var context = LoggingTestHelpers.NewContext(services, path: "/health");
        LoggingTestHelpers.SetRoute(context, "/health");
        var middleware = LoggingTestHelpers.BuildMiddleware(services);

        await middleware.InvokeAsync(context);

        var echoed = context.Response.Headers[Header].ToString();
        Assert.False(string.IsNullOrWhiteSpace(echoed));

        var requestLine = writer.JsonLines().RequestLine("/health");
        Assert.Equal(echoed, requestLine.Prop("traceId"));
    }

    [Fact]
    public async Task ErrorResponse_ProblemJsonBody_CarriesTheSameTraceId()
    {
        var (pipeline, services, writer) = LoggingTestHelpers.BuildRequestPipeline();
        const string traceId = "a1b2c3d4-1111-2222-3333-444455556666";
        var context = LoggingTestHelpers.NewContext(services, path: "/v1/does-not-exist", traceId: traceId);

        await pipeline(context);

        Assert.Equal((int)HttpStatusCode.NotFound, context.Response.StatusCode);

        var body = await LoggingTestHelpers.ReadBodyAsync(context);
        using var document = JsonDocument.Parse(body);
        Assert.Equal(traceId, document.RootElement.GetProperty("traceId").GetString());

        var requestLine = writer.JsonLines().RequestLine("unmatched");
        Assert.Equal(traceId, requestLine.Prop("traceId"));
    }

    [Fact]
    public async Task UnhandledException_ProducesProblemJson_WithTraceId()
    {
        var (pipeline, services, writer) = LoggingTestHelpers.BuildRequestPipeline(
            _ => throw new InvalidOperationException("boom"));
        const string traceId = "b2c3d4e5-2222-3333-4444-555566667777";
        var context = LoggingTestHelpers.NewContext(services, path: "/v1/explode", traceId: traceId);

        await pipeline(context);

        Assert.Equal((int)HttpStatusCode.InternalServerError, context.Response.StatusCode);

        var body = await LoggingTestHelpers.ReadBodyAsync(context);
        using var document = JsonDocument.Parse(body);
        Assert.Equal(traceId, document.RootElement.GetProperty("traceId").GetString());

        // The ERROR line for the unhandled exception carries the code + exception
        // type + stack trace + traceId, and the request line is still emitted.
        var errorLine = writer.JsonLines().First(l => l.Prop("event") == "error.unhandled");
        Assert.Equal(traceId, errorLine.Prop("traceId"));
        Assert.Equal("internal_error", errorLine.Prop("errorCode"));
        Assert.Equal("InvalidOperationException", errorLine.Prop("exceptionType"));
        Assert.False(string.IsNullOrWhiteSpace(errorLine.Prop("stackTrace")));

        var requestLine = writer.JsonLines().RequestLine("unmatched");
        Assert.Equal(traceId, requestLine.Prop("traceId"));
    }
}
