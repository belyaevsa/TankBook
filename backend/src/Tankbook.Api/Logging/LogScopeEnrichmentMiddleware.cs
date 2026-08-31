using Tankbook.Api.Auth;

namespace Tankbook.Api.Logging;

/// <summary>
/// Pushes the client-supplied identity into the log scope (docs/LOGGING.md §2):
/// the app version, platform and payload schema version the request announced
/// (PR.8 wire headers) plus the authenticated account/device. Runs after bearer
/// auth so <see cref="AuthContext"/> is populated; the scope is active for the
/// rest of the pipeline, so every line for the request carries the fields.
///
/// The per-request <c>http.request</c> line is emitted by the OUTER
/// <see cref="TraceCorrelationMiddleware"/>'s finally, after this scope is
/// disposed, so this middleware also writes the fields into
/// <c>context.Items</c> and the trace middleware merges them into that line's
/// state - one source, both paths, same rendered fields.
/// </summary>
public sealed class LogScopeEnrichmentMiddleware
{
    public const string AppVersionHeader = "X-Tankbook-App";
    public const string PlatformHeader = "X-Tankbook-Platform";
    public const string SchemaVersionHeader = "X-Tankbook-Schema-Version";
    public const string EnrichmentItemKey = "Tankbook.LogScope";

    private readonly RequestDelegate _next;
    private readonly ILogger<LogScopeEnrichmentMiddleware> _logger;
    private readonly string _hashSalt;

    public LogScopeEnrichmentMiddleware(
        RequestDelegate next,
        ILogger<LogScopeEnrichmentMiddleware> logger,
        LoggingOptions loggingOptions)
    {
        _next = next;
        _logger = logger;
        _hashSalt = loggingOptions.HashSalt;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var fields = BuildFields(context);
        if (fields.Count == 0)
        {
            await _next(context);
            return;
        }

        context.Items[EnrichmentItemKey] = fields;
        using var scope = _logger.BeginScope(fields);
        await _next(context);
    }

    private Dictionary<string, object?> BuildFields(HttpContext context)
    {
        var fields = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);

        var appVersion = context.Request.Headers[AppVersionHeader].FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(appVersion))
        {
            fields["ClientVersion"] = appVersion.Trim();
        }

        var platform = context.Request.Headers[PlatformHeader].FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(platform))
        {
            fields["ClientPlatform"] = platform.Trim();
        }

        var schemaVersion = context.Request.Headers[SchemaVersionHeader].FirstOrDefault();
        if (int.TryParse(schemaVersion, out var parsed))
        {
            fields["SchemaVersion"] = parsed;
        }

        // Only an authenticated request has an identity to push; public routes
        // (health, config, rates, catalog) simply leave accountHash/deviceId null.
        if (AuthContext.From(context) is { } identity)
        {
            fields["AccountHash"] = AccountHash.ForAccount(identity.AccountId, _hashSalt);
            fields["DeviceId"] = identity.DeviceId.ToString();
        }

        return fields;
    }
}
