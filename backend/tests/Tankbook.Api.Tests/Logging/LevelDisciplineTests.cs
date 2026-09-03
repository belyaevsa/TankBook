using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Configuration;
using Tankbook.Api.Logging;
using Tankbook.Api.Rates;

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
    // ------------------------------------------------------------------
    // RV.13: the OUTBOUND HttpClient lines.
    // ------------------------------------------------------------------

    /// <summary>
    /// The four lines every outbound call used to emit at Information -
    /// and, on a throw, the <c>RequestFailed</c>/<c>RequestPipelineFailed</c>
    /// pair that replaces the End pair, also at Information -
    /// <c>RequestPipelineStart</c>/<c>End</c> from
    /// <c>System.Net.Http.HttpClient.&lt;name&gt;.LogicalHandler</c> and
    /// <c>RequestStart</c>/<c>End</c> from <c>...ClientHandler</c>. Matched by
    /// BOTH the event name and the message text, because either alone would let
    /// a framework rename slip a whole pair back into the stream unnoticed.
    ///
    /// The message text is matched as a prefix, deliberately: the templates read
    /// "Start processing HTTP request {HttpMethod} {Uri}", and <b>{Uri} does not
    /// render</b> - an outbound URI is a domain value and hard rule 12 forbids
    /// logging it, so the redactor drops it. That unrendered placeholder is
    /// correct and must stay unrendered; RV.13 removes the lines, it does not
    /// fill them in.
    /// </summary>
    private static bool IsOutboundHttpClientLine(JsonElement line)
    {
        var eventName = line.Prop("event") ?? string.Empty;
        if (eventName is "RequestPipelineStart" or "RequestPipelineEnd" or "RequestStart" or "RequestEnd"
            or "RequestPipelineFailed" or "RequestFailed")
        {
            return true;
        }

        var message = line.Prop("message") ?? string.Empty;
        return message.StartsWith("Start processing HTTP request", StringComparison.Ordinal) ||
               message.StartsWith("End processing HTTP request", StringComparison.Ordinal) ||
               message.StartsWith("Sending HTTP request", StringComparison.Ordinal) ||
               message.StartsWith("Received HTTP response headers", StringComparison.Ordinal) ||
               message.StartsWith("HTTP request failed after", StringComparison.Ordinal);
    }

    /// <summary>
    /// The logging pipeline built over the <b>shipped configuration</b> -
    /// <c>appsettings.template.json</c>, the committed source of the gitignored
    /// <c>appsettings.json</c> the server actually reads.
    ///
    /// Reading that file is the whole point. RV.13 is a bug in CONFIGURATION,
    /// not in a call site: nothing in C# emitted those four lines, they fell
    /// through <c>Logging:LogLevel</c> to <c>Default: Information</c> because no
    /// entry covered the category. A test that constructed its own filters (or
    /// called <c>SetMinimumLevel</c>, as the inbound tests above legitimately do)
    /// would pass forever whatever the template says, which is exactly the
    /// vacuous assertion this file must not contain.
    /// </summary>
    private static (ServiceProvider Services, InMemoryLogWriter Writer) BuildFromShippedConfiguration(
        Func<HttpRequestMessage, HttpResponseMessage> respond)
    {
        var templatePath = Path.Combine(
            DocPaths.RepositoryRoot, "backend", "src", "Tankbook.Api", "appsettings.template.json");
        var configuration = new ConfigurationBuilder().AddJsonFile(templatePath, optional: false).Build();

        var writer = new InMemoryLogWriter([]);
        var services = new ServiceCollection();
        services.AddLogging(builder =>
        {
            builder.ClearProviders();
            builder.AddConfiguration(configuration.GetSection("Logging"));
            builder.Services.AddSingleton<ILoggerProvider>(sp => new TankbookLoggerProvider(
                sp.GetRequiredService<LogRenderer>(),
                sp.GetRequiredService<ILogWriter>()));
            builder.Services.AddSingleton(new LogRenderer(
                new TankbookRedactor("test-salt"),
                "0.1.0-test",
                json: true));
            builder.Services.AddSingleton<ILogWriter>(writer);
        });

        // The "rates" client exactly as Program.cs registers it, with the network
        // replaced at the primary handler (docs/TESTING.md "mock the boundary").
        services.AddHttpClient("rates").ConfigurePrimaryHttpMessageHandler(() => new StubPrimaryHandler(respond));

        return (services.BuildServiceProvider(), writer);
    }

    /// <summary>
    /// A SUCCESSFUL outbound call emits none of the four
    /// <c>System.Net.Http.HttpClient</c> Information lines.
    ///
    /// Measured in production on 2026-09-02/03: four per call, so one /extract
    /// cost eight, and they carried nothing a reader can use - an unrendered
    /// {Uri}, a serialized HttpMethod object, a duration the caller's own line
    /// already reports. Same failure as the inbound noise above, from the
    /// outbound direction.
    ///
    /// The app's own rates.fetch line is asserted PRESENT in the same window, so
    /// the test cannot pass against a pipeline that emits nothing at all - which
    /// is the only way "quiet" and "broken" look alike here.
    /// </summary>
    [Fact]
    public async Task SuccessfulOutboundCall_EmitsNoHttpClientInformationLine()
    {
        var (services, writer) = BuildFromShippedConfiguration(
            _ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("<ValCurs/>") });
        await using var _ = services;

        using var response = await services.GetRequiredService<IHttpClientFactory>()
            .CreateClient("rates")
            .GetAsync("https://rates.example/daily", CancellationToken.None);
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        TankbookLog.RatesFetch(
            services.GetRequiredService<ILoggerFactory>().CreateLogger<RatesJobService>(),
            "2026-09-03",
            published: 1,
            carriedForward: 0,
            sourcesFailed: 0);

        var lines = writer.JsonLines().ToList();
        Assert.Contains(lines, l => l.Prop("event") == "rates.fetch" && l.Prop("level") == "Information");
        Assert.DoesNotContain(lines, IsOutboundHttpClientLine);
    }

    /// <summary>
    /// The other half, and the half that decides whether silencing the category
    /// is safe: a FAILED outbound call is still visible, because the caller logs
    /// its own outcome. This is the assertion that made silencing the category
    /// safe to do at all: the handlers DO narrate a throw
    /// (<c>RequestFailed</c>/<c>RequestPipelineFailed</c>, with the exception),
    /// but they narrate it at Information, so raising the category to Warning
    /// takes those lines with the rest. Every outbound caller was checked for
    /// its own failure line before the change - rates logs this Warning, the LLM
    /// gateway logs llm.extract/provider_failed at Error, APNs failures are
    /// counted onto sync.nudge, and a JWKS fetch that throws reaches the global
    /// handler as error.unhandled at Error. Not one of them depended on the
    /// HttpClient line.
    ///
    /// The failure is produced by the real <see cref="CisRateFeed"/> over a
    /// primary handler that refuses the connection, and the Warning is the one
    /// RatesJobService emits verbatim for that catch.
    /// </summary>
    [Fact]
    public async Task FailedOutboundCall_StillSurfacesTheCallersOwnWarning()
    {
        var (services, writer) = BuildFromShippedConfiguration(
            _ => throw new HttpRequestException("connection refused"));
        await using var _ = services;

        var feed = new CisRateFeed(services.GetRequiredService<IHttpClientFactory>());
        var date = new DateOnly(2026, 9, 3);

        var thrown = await Assert.ThrowsAsync<HttpRequestException>(
            () => feed.FetchAsync(date, "EUR", CancellationToken.None));

        // Verbatim what Rates/RatesJobService.cs logs when a feed throws.
        services.GetRequiredService<ILoggerFactory>().CreateLogger<RatesJobService>()
            .LogWarning(thrown, "Rate feed {Source} failed for {Date} / {Base}.", feed.Source, date, "EUR");

        var lines = writer.JsonLines().ToList();
        var failure = Assert.Single(lines, l => l.Prop("level") == "Warning");
        Assert.Equal("cis", failure.Prop("Source"));
        Assert.DoesNotContain(lines, IsOutboundHttpClientLine);
    }

    /// <summary>A primary handler that answers - or refuses - without a network.</summary>
    private sealed class StubPrimaryHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, HttpResponseMessage> _respond;

        public StubPrimaryHandler(Func<HttpRequestMessage, HttpResponseMessage> respond) => _respond = respond;

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request, CancellationToken cancellationToken)
            => Task.FromResult(_respond(request));
    }
}
