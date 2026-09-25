using System.Diagnostics;
using Dapper;
using Tankbook.Admin.Auth;
using Tankbook.Admin.Data;

namespace Tankbook.Admin.Access;

/// <summary>
/// Marks an endpoint as returning user content. <see cref="AccessLogMiddleware"/> writes one
/// <c>admin.access_log</c> row for every request to such an endpoint - including one that
/// found nothing, because a look is a look (docs/SECURITY.md -> "The admin viewer").
/// </summary>
/// <param name="Kind">What was looked at: <c>account</c>, <c>lookup</c>, ...</param>
/// <param name="TargetParameter">The route value or query key naming the target id.</param>
public sealed record AccessLoggedAttribute(string Kind, string TargetParameter);

public static class AccessLogExtensions
{
    /// <summary>Opts an endpoint into the access log.</summary>
    public static TBuilder AccessLogged<TBuilder>(this TBuilder builder, string kind, string targetParameter)
        where TBuilder : IEndpointConventionBuilder =>
        builder.WithMetadata(new AccessLoggedAttribute(kind, targetParameter));
}

public sealed class AccessLogMiddleware(RequestDelegate next)
{
    public async Task InvokeAsync(HttpContext http, Db db, ILogger<AccessLogMiddleware> log)
    {
        var marker = http.GetEndpoint()?.Metadata.GetMetadata<AccessLoggedAttribute>();
        if (marker is null)
        {
            await next(http);
            return;
        }
        var clock = Stopwatch.StartNew();
        await next(http);
        // An unauthenticated request never reached the content, so there is no look to log.
        if (http.User.Identity?.IsAuthenticated != true)
        {
            return;
        }
        var target = http.Request.RouteValues.TryGetValue(marker.TargetParameter, out var routeValue)
            ? routeValue?.ToString()
            : http.Request.Query[marker.TargetParameter].ToString();
        var route = (http.GetEndpoint() as RouteEndpoint)?.RoutePattern.RawText ?? http.Request.Path.Value ?? "";
        await using (var c = db.AdminWrite())
        {
            await c.ExecuteAsync(
                "INSERT INTO admin.access_log (actor, kind, target_id, route, status) VALUES (@actor, @kind, @target, @route, @status)",
                new { actor = AuthEndpoints.Actor(http.User), kind = marker.Kind, target, route, status = http.Response.StatusCode });
        }
        // Shape only: the kind, the id and the status - never what the page showed.
        log.LogInformation("admin.view {Kind} {TargetId} {Status} {DurationMs}",
            marker.Kind, target, http.Response.StatusCode, clock.ElapsedMilliseconds);
    }
}
