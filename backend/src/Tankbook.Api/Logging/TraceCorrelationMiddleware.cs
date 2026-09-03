using System.Diagnostics;

namespace Tankbook.Api.Logging;

/// <summary>
/// Trace correlation (docs/LOGGING.md §2): reads X-Tankbook-Trace (generating
/// a UUIDv7 when absent), echoes it in the response header, pushes it into the
/// log scope for the whole request, times the request, and emits the per-request
/// line with the route template (never the raw path, so ids stay out of logged
/// paths). The request line also carries the client-supplied correlation fields
/// (clientVersion, accountHash, deviceId, schemaVersion) that
/// <see cref="LogScopeEnrichmentMiddleware"/> wrote into context.Items - its
/// own scope is disposed before this finally runs. Health routes log at DEBUG
/// only so they do not drown the stream.
/// </summary>
public sealed class TraceCorrelationMiddleware
{
    public const string Header = "X-Tankbook-Trace";
    public const string TraceIdItemKey = "Tankbook.TraceId";

    /// <summary>
    /// The route value logged when no endpoint matched. A named constant rather
    /// than a repeated literal because the log LEVEL now turns on it (RV.16):
    /// a typo would silently restore the Information-level flood it exists to
    /// stop, and nothing would fail.
    /// </summary>
    public const string UnmatchedRoute = "unmatched";

    private readonly RequestDelegate _next;
    private readonly ILogger<TraceCorrelationMiddleware> _logger;

    public TraceCorrelationMiddleware(RequestDelegate next, ILogger<TraceCorrelationMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var traceId = context.Request.Headers[Header].FirstOrDefault();
        if (string.IsNullOrWhiteSpace(traceId))
        {
            // PR.8: the fallback is a UUIDv7 too, so the server-generated id has
            // the same time-ordered shape as the client's (docs/LOGGING.md §2).
            traceId = Guid.CreateVersion7().ToString();
        }

        context.Items[TraceIdItemKey] = traceId;
        context.Response.Headers[Header] = traceId;

        using var scope = _logger.BeginScope(new Dictionary<string, object?>
        {
            ["TraceId"] = traceId,
        });

        var originalBody = context.Response.Body;
        var counting = new CountingWriteStream(originalBody);
        context.Response.Body = counting;

        var stopwatch = Stopwatch.StartNew();
        try
        {
            await _next(context);
        }
        finally
        {
            stopwatch.Stop();
            context.Response.Body = originalBody;

            var endpoint = context.GetEndpoint();
            var routeTemplate = endpoint is RouteEndpoint route && !string.IsNullOrWhiteSpace(route.RoutePattern.RawText)
                ? "/" + route.RoutePattern.RawText.TrimStart('/')
                : UnmatchedRoute;

            // A SUCCESSFUL request is Debug; anything else is worth reading
            // (2026-09-02). The per-request line was Information for every
            // request, which buried the lines that say what actually happened -
            // auth.session, sync.push, blob.commit, llm.extract - under one
            // http.request per call, several per screen. The domain events are
            // the information; http.request is the audit trail underneath them.
            //
            // Nothing is lost, it is re-levelled: set Logging:LogLevel:Default
            // to Debug to get every request back. Failures stay visible - 4xx at
            // Information, 5xx at Warning - so the log still shows what went
            // wrong without showing everything that went right.
            //
            // RV.16 (2026-09-03): an UNMATCHED route is Debug, even though it is
            // a 4xx. The rule above is right for a client getting a real
            // endpoint wrong; it was wrong for "no endpoint exists", which on a
            // public IP is not a client at all but internet scanning. Measured
            // in production: ~250 Information lines in 90 seconds, sustained -
            // POSTs of 5 KB and 67 KB bodies to routes this app has never had,
            // with no accountHash, deviceId or clientVersion on any of them.
            // That is ~260k lines a day of pure noise, and for those 90 seconds
            // it buried sync.push, blob.commit and llm.extract completely -
            // exactly the failure the re-levelling above exists to prevent,
            // arriving from a direction it did not cover.
            //
            // The distinction is real and the middleware already knows it:
            // `routeTemplate` is the literal "unmatched" when no endpoint
            // matched. A 404 from a REAL endpoint - a blob that is not there, an
            // account that does not exist - still logs at Information, because
            // that one is a client of ours getting an answer it may need help
            // with. Nothing is lost either way: Logging:LogLevel:Default at
            // Debug brings the scanning back when someone is actually looking
            // for it.
            var isHealth = routeTemplate.StartsWith("/health", StringComparison.OrdinalIgnoreCase);
            var isUnmatched = routeTemplate == UnmatchedRoute;
            var level = (isHealth, isUnmatched, status: context.Response.StatusCode) switch
            {
                (true, _, _) => LogLevel.Debug,
                (_, _, >= 500) => LogLevel.Warning,
                (_, true, _) => LogLevel.Debug,
                (_, _, >= 400) => LogLevel.Information,
                _ => LogLevel.Debug,
            };

            var enrichment = context.Items[LogScopeEnrichmentMiddleware.EnrichmentItemKey] as IReadOnlyDictionary<string, object?>;

            TankbookLog.HttpRequest(
                _logger,
                level,
                context.Request.Method,
                routeTemplate,
                context.Response.StatusCode,
                stopwatch.Elapsed.TotalMilliseconds,
                context.Request.ContentLength ?? 0,
                counting.BytesWritten,
                enrichment);
        }
    }
}

/// <summary>Counts bytes written to the response so the request line can carry responseBytes.</summary>
internal sealed class CountingWriteStream : Stream
{
    private readonly Stream _inner;

    public CountingWriteStream(Stream inner) => _inner = inner;

    public long BytesWritten { get; private set; }

    public override bool CanRead => false;
    public override bool CanSeek => false;
    public override bool CanWrite => true;
    public override long Length => throw new NotSupportedException();
    public override long Position
    {
        get => throw new NotSupportedException();
        set => throw new NotSupportedException();
    }

    public override void Flush() => _inner.Flush();

    public override Task FlushAsync(CancellationToken cancellationToken) => _inner.FlushAsync(cancellationToken);

    public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();

    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

    public override void SetLength(long value) => throw new NotSupportedException();

    public override void Write(byte[] buffer, int offset, int count)
    {
        _inner.Write(buffer, offset, count);
        BytesWritten += count;
    }

    public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        BytesWritten += count;
        return _inner.WriteAsync(buffer, offset, count, cancellationToken);
    }

    public override ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken cancellationToken = default)
    {
        BytesWritten += buffer.Length;
        return _inner.WriteAsync(buffer, cancellationToken);
    }

    public override void WriteByte(byte value)
    {
        _inner.WriteByte(value);
        BytesWritten += 1;
    }

    // The underlying response body belongs to the server; never dispose it here.
    public override void Close() { }
}
