using System.Globalization;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Tankbook.Api.Auth;
using Tankbook.Api.Http;
using Tankbook.Api.Logging;
using Tankbook.Api.Options;

namespace Tankbook.Api.RateLimiting;

/// <summary>
/// Wires the ASP.NET rate limiter (docs/API.md "Rate limits", docs/PRACTICES.md
/// S9, PR.17). Per-IP policies for the unauthenticated mutating surfaces (auth,
/// import, operator publish) and per-device policies for the bearer mutating
/// surfaces (extract, sync push, blob begin). A rejected request is a 429
/// problem+json carrying Retry-After and the traceId - never a bare 503 and
/// never a 429 without a next step (hard rule 7).
/// </summary>
public static class RateLimitingSetup
{
    public const string AuthSession = "auth-session";
    public const string AuthRefresh = "auth-refresh";
    public const string ImportParse = "import-parse";
    public const string Extract = "extract";
    public const string SyncPush = "sync-push";
    public const string BlobBegin = "blob-begin";
    public const string Feedback = "feedback";

    /// <summary>Registers the rate limiter and its named policies.</summary>
    public static IServiceCollection AddTankbookRateLimiting(this IServiceCollection services, RateLimitOptions limits)
    {
        services.AddRateLimiter(options =>
        {
            options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
            options.OnRejected = OnRejectedAsync;

            options.AddPolicy(AuthSession, PerIp(limits.AuthSessionPerMinute));
            options.AddPolicy(AuthRefresh, PerIp(limits.AuthRefreshPerMinute));
            options.AddPolicy(ImportParse, PerIp(limits.ImportParsePerMinute));
            options.AddPolicy(Extract, PerDevice(limits.ExtractPerMinute));
            options.AddPolicy(SyncPush, PerDevice(limits.SyncPushPerMinute));
            options.AddPolicy(BlobBegin, PerDevice(limits.BlobBeginPerMinute));
            options.AddPolicy(Feedback, PerDevice(limits.FeedbackPerMinute));
        });

        return services;
    }

    /// <summary>
    /// A one-minute fixed window partitioned by client IP. A fixed window is
    /// deliberately simple: the requirement is a flood guard, not fairness, and
    /// a busy human never crosses a window boundary twice in a minute.
    /// </summary>
    private static Func<HttpContext, RateLimitPartition<string>> PerIp(int permitLimit)
        => context => RateLimitPartition.GetFixedWindowLimiter(
            ClientIp(context),
            _ => WindowOptions(permitLimit));

    /// <summary>
    /// A one-minute fixed window partitioned by device. The device identity is
    /// the authenticated device (bearer endpoints set it before the rate
    /// limiter runs), falling back to the X-Device-Id header, then to the IP.
    /// </summary>
    private static Func<HttpContext, RateLimitPartition<string>> PerDevice(int permitLimit)
        => context => RateLimitPartition.GetFixedWindowLimiter(
            DeviceKey(context),
            _ => WindowOptions(permitLimit));

    private static FixedWindowRateLimiterOptions WindowOptions(int permitLimit)
        => new()
        {
            PermitLimit = permitLimit,
            Window = RateLimitOptions.Window,
            QueueLimit = 0,
            QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
        };

    private static async ValueTask OnRejectedAsync(OnRejectedContext context, CancellationToken cancellationToken)
    {
        var http = context.HttpContext;
        http.Response.StatusCode = StatusCodes.Status429TooManyRequests;

        if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
        {
            http.Response.Headers.RetryAfter =
                ((int)Math.Ceiling(retryAfter.TotalSeconds)).ToString(CultureInfo.InvariantCulture);
        }

        var traceId = http.Items[TraceCorrelationMiddleware.TraceIdItemKey] as string;
        var problem = new ProblemDetails
        {
            Status = StatusCodes.Status429TooManyRequests,
            Title = "Too many requests.",
            Type = "about:blank",
            Detail = "Too many requests; wait for the delay named by the Retry-After header before retrying.",
        };
        problem.Extensions[ProblemResponses.ErrorEnvelopeCodeKey] = TankbookErrorCodes.RateLimited;
        if (traceId is not null)
        {
            problem.Extensions["traceId"] = traceId;
        }

        // Written through IProblemDetailsService so the body is problem+json,
        // like every other error surface.
        var problemService = http.RequestServices.GetService<IProblemDetailsService>();
        if (problemService is not null)
        {
            await problemService.TryWriteAsync(new ProblemDetailsContext
            {
                HttpContext = http,
                ProblemDetails = problem,
            });
            return;
        }

        await http.Response.WriteAsJsonAsync(problem, cancellationToken);
    }

    /// <summary>The client IP, or a stable stand-in when the server cannot determine one (test hosts).</summary>
    private static string ClientIp(HttpContext context)
        => context.Connection.RemoteIpAddress?.ToString() ?? "unknown";

    /// <summary>The device identity: bearer token device, else X-Device-Id, else IP.</summary>
    private static string DeviceKey(HttpContext context)
    {
        if (context.Items[AuthContext.DeviceIdKey] is Guid deviceId)
        {
            return deviceId.ToString();
        }

        var header = context.Request.Headers["X-Device-Id"].FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(header))
        {
            return header;
        }

        return ClientIp(context);
    }
}
