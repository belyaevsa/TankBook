using System.Diagnostics;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Routing;
using Microsoft.AspNetCore.Routing.Patterns;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Tankbook.Api.Logging;

namespace Tankbook.Api.Tests;

/// <summary>In-memory log writer so tests assert on the real emitted output of the pipeline.</summary>
public sealed class InMemoryLogWriter : ILogWriter
{
    private readonly List<string> _lines;
    private readonly object _gate = new();

    public InMemoryLogWriter(List<string> lines) => _lines = lines;

    public IReadOnlyList<string> Lines
    {
        get
        {
            lock (_gate)
            {
                return _lines.ToList();
            }
        }
    }

    public void WriteLine(string line)
    {
        lock (_gate)
        {
            _lines.Add(line);
        }
    }
}

/// <summary>
/// Shared setup for the logging tests. Per docs/TESTING.md "Standing rule:
/// mock the boundary, don't boot the world", everything here runs in-process:
/// a real ServiceCollection, a real DefaultHttpContext, and a real middleware
/// pipeline built with ApplicationBuilder - never a WebApplicationFactory, a
/// route table, a database, or a network.
/// </summary>
internal static class LoggingTestHelpers
{
    /// <summary>
    /// Builds the logging pipeline exactly as Program wires it (same provider,
    /// same redactor, same renderer) over an in-memory writer. Returns the
    /// service provider and the captured output.
    /// </summary>
    public static (IServiceProvider Services, InMemoryLogWriter Writer) BuildPipeline()
    {
        var (services, writer) = CreateServices(new InMemoryLogWriter([]));
        return (services.BuildServiceProvider(), writer);
    }

    private static (ServiceCollection Services, InMemoryLogWriter Writer) CreateServices(InMemoryLogWriter writer)
    {
        var services = new ServiceCollection();

        services.AddLogging(builder =>
        {
            builder.ClearProviders();
            builder.SetMinimumLevel(LogLevel.Trace);
            builder.Services.AddSingleton<ILoggerProvider>(sp => new TankbookLoggerProvider(
                sp.GetRequiredService<LogRenderer>(),
                sp.GetRequiredService<ILogWriter>()));
            builder.Services.AddSingleton(new LogRenderer(
                new TankbookRedactor("test-salt"),
                "0.1.0-test",
                json: true));
            builder.Services.AddSingleton<ILogWriter>(writer);
        });
        // The log-scope enrichment middleware resolves LoggingOptions for the
        // account-hash salt, exactly as Program.cs registers it.
        services.AddSingleton(new LoggingOptions { HashSalt = "test-salt" });

        return (services, writer);
    }

    /// <summary>
    /// An in-process request pipeline mirroring Program.cs's middleware chain:
    /// trace correlation, the exception handler (error.unhandled + problem+json),
    /// status-code pages, and a terminal delegate (404 by default, or whatever
    /// the caller supplies). No host is booted; the pipeline is composed from
    /// ApplicationBuilder over the same service provider as <see cref="BuildPipeline"/>.
    /// </summary>
    public static (RequestDelegate Pipeline, IServiceProvider Services, InMemoryLogWriter Writer) BuildRequestPipeline(
        RequestDelegate? terminal = null)
    {
        var (services, writer) = CreateServices(new InMemoryLogWriter([]));

        // Services the exception-handler middleware needs outside a full host.
        services.AddMetrics();
        services.AddSingleton(new DiagnosticListener("Tankbook.Api.Tests"));
        services.AddSingleton<IOptions<ExceptionHandlerOptions>>(_ =>
            Microsoft.Extensions.Options.Options.Create(new ExceptionHandlerOptions()));

        services.AddProblemDetails(options =>
        {
            options.CustomizeProblemDetails = context =>
            {
                if (context.HttpContext.Items[TraceCorrelationMiddleware.TraceIdItemKey] is string traceId)
                {
                    context.ProblemDetails.Extensions["traceId"] = traceId;
                }
            };
        });

        var sp = services.BuildServiceProvider();

        var app = new ApplicationBuilder(sp);
        app.UseMiddleware<TraceCorrelationMiddleware>();
        app.UseExceptionHandler(errorApp =>
        {
            errorApp.Run(async context =>
            {
                var exception = context.Features.Get<IExceptionHandlerFeature>()?.Error;
                if (exception is not null)
                {
                    var logger = context.RequestServices
                        .GetRequiredService<ILoggerFactory>()
                        .CreateLogger("Tankbook.Api");
                    var endpoint = context.GetEndpoint() is RouteEndpoint route && !string.IsNullOrWhiteSpace(route.RoutePattern.RawText)
                        ? "/" + route.RoutePattern.RawText.TrimStart('/')
                        : "unmatched";
                    TankbookLog.UnhandledException(logger, exception, endpoint);
                }

                var problemService = context.RequestServices.GetService<IProblemDetailsService>();
                if (problemService is not null)
                {
                    var problem = new ProblemDetails
                    {
                        Status = StatusCodes.Status500InternalServerError,
                        Title = "An internal error occurred while processing the request.",
                        Type = "about:blank",
                    };
                    await problemService.TryWriteAsync(new ProblemDetailsContext
                    {
                        HttpContext = context,
                        ProblemDetails = problem,
                    });
                }
            });
        });
        app.UseStatusCodePages(async statusCodeContext =>
        {
            var problemService = statusCodeContext.HttpContext.RequestServices.GetService<IProblemDetailsService>();
            if (problemService is null)
            {
                return;
            }

            var status = statusCodeContext.HttpContext.Response.StatusCode;
            var problem = new ProblemDetails
            {
                Status = status,
                Title = ReasonPhrases.GetReasonPhrase(status),
                Type = "about:blank",
            };
            await problemService.TryWriteAsync(new ProblemDetailsContext
            {
                HttpContext = statusCodeContext.HttpContext,
                ProblemDetails = problem,
            });
        });
        app.Run(terminal ?? (context =>
        {
            context.Response.StatusCode = 404;
            return Task.CompletedTask;
        }));

        return (app.Build(), sp, writer);
    }

    /// <summary>
    /// A DefaultHttpContext with RequestServices wired (needed by the error /
    /// status-code handlers) and a readable response body, ready for a
    /// middleware or pipeline invocation.
    /// </summary>
    public static DefaultHttpContext NewContext(
        IServiceProvider services,
        string method = "GET",
        string path = "/",
        string? traceId = null)
    {
        var context = new DefaultHttpContext { RequestServices = services };
        context.Request.Method = method;
        context.Request.Path = path;
        if (traceId is not null)
        {
            context.Request.Headers[TraceCorrelationMiddleware.Header] = traceId;
        }

        context.Response.Body = new MemoryStream();
        return context;
    }

    /// <summary>
    /// Attaches a matched route to the context so the middleware resolves a
    /// route template instead of "unmatched". The route pattern is the whole
    /// point: the logged path must be the template, never a concrete id.
    /// </summary>
    public static void SetRoute(HttpContext context, string pattern)
    {
        context.SetEndpoint(new RouteEndpoint(
            _ => Task.CompletedTask,
            RoutePatternFactory.Parse(pattern),
            order: 0,
            new EndpointMetadataCollection(new RouteNameMetadata(pattern)),
            pattern));
    }

    /// <summary>The request-logging middleware with a stub next and the test logger.</summary>
    public static TraceCorrelationMiddleware BuildMiddleware(IServiceProvider services, RequestDelegate? next = null)
        => new(
            next ?? (_ => Task.CompletedTask),
            services.GetRequiredService<ILoggerFactory>().CreateLogger<TraceCorrelationMiddleware>());

    /// <summary>Re-reads the response body that the pipeline or middleware wrote.</summary>
    public static async Task<string> ReadBodyAsync(HttpContext context)
    {
        context.Response.Body.Position = 0;
        return await new StreamReader(context.Response.Body).ReadToEndAsync();
    }

    public static IEnumerable<JsonElement> JsonLines(this InMemoryLogWriter writer)
    {
        foreach (var line in writer.Lines)
        {
            yield return JsonDocument.Parse(line).RootElement.Clone();
        }
    }

    /// <summary>
    /// Case-insensitive property lookup, matching the docs' lowercase field
    /// names (docs/LOGGING.md §2/§3) against the emitted keys, which keep their
    /// original casing (Path, Status, ...). On duplicate keys (RV.63: the redactor
    /// masks an email under the distinct emailHash key, so accountHash can no
    /// longer be duplicated by a renamed email - a state AccountHash would override
    /// the scope's) the last occurrence wins, mirroring JsonElement.TryGetProperty.
    /// </summary>
    /// <summary>
    /// Rendered log output with the <b>free-running machine-generated numbers</b>
    /// blanked, for the substring sweeps that assert a domain value never reached
    /// the log (hard rule 12).
    ///
    /// Two fields vary on every run and can coincidentally spell a value the sweep
    /// asserts is absent:
    /// <list type="bullet">
    /// <item><c>timestamp</c> renders seconds as <c>SS.mmm</c>, so <c>...:42.317Z</c>
    /// contains "42.3" and <c>...:12.342Z</c> contains "12.34" - both needles in
    /// <c>RedactionTests</c>. On the clock alone that is a red run roughly once in
    /// 600.</item>
    /// <item><c>DurationMs</c> is <c>TimeSpan.TotalMilliseconds</c>, an unbounded
    /// decimal, so a 9.87-second request renders <c>9876.5432</c> and contains
    /// "9876.54" - the secret-amount needle in <c>SyncEndpointTests</c>.</item>
    /// </list>
    ///
    /// Both are machine metadata that can never legitimately carry user data, so
    /// removing them costs the sweep nothing. **Identifiers (traceId, deviceId,
    /// accountHash) are deliberately left in**: they are also machine-generated,
    /// but leaving them means a domain value wrongly routed into one is still
    /// caught, and a hex id colliding with a decimal needle is not a real risk.
    ///
    /// A failure caused by the clock is a red that says nothing about redaction,
    /// and the fix is to stop sweeping the clock - never to loosen the assertion.
    /// </summary>
    public static string WithoutMachineFields(this string rendered)
    {
        var timeout = TimeSpan.FromSeconds(1);
        var swept = Regex.Replace(
            rendered, "\"timestamp\":\"[^\"]*\"", "\"timestamp\":\"\"", RegexOptions.None, timeout);
        return Regex.Replace(
            swept, "\"[Dd]urationMs\":[0-9.eE+-]*", "\"DurationMs\":0", RegexOptions.None, timeout);
    }

    public static string? Prop(this JsonElement element, string name)
    {
        string? result = null;
        var found = false;
        foreach (var property in element.EnumerateObject())
        {
            if (string.Equals(property.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                result = property.Value.ValueKind == JsonValueKind.Null ? null : property.Value.ToString();
                found = true;
            }
        }

        return found ? result : null;
    }
}

internal static class CorrelationTestExtensions
{
    public static IEnumerable<JsonElement> RequestLines(this IEnumerable<JsonElement> lines) =>
        lines.Where(l => l.Prop("event") == "http.request");

    public static JsonElement RequestLine(this IEnumerable<JsonElement> lines, string path)
    {
        var match = lines.RequestLines().SingleOrDefault(l => l.Prop("path") == path);
        Assert.True(match.ValueKind != JsonValueKind.Undefined, $"No http.request line for {path}");
        return match;
    }
}
