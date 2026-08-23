using System.Data;
using System.Reflection;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;
using Npgsql;
using Tankbook.Api.Config;
using Tankbook.Api.Data;
using Tankbook.Api.Logging;
using Tankbook.Api.Options;
using Tankbook.Api.Sync;

var builder = WebApplication.CreateBuilder(args);

// Options binding. No secrets ever ship in committed files: appsettings.json
// carries only empty placeholders, and appsettings.Development.json holds the
// local dev defaults (localhost Postgres + MinIO).
builder.Services.Configure<ConnectionStringsOptions>(
    builder.Configuration.GetSection(ConnectionStringsOptions.SectionName));
builder.Services.Configure<S3Options>(
    builder.Configuration.GetSection(S3Options.SectionName));
builder.Services.Configure<ConfigSigningOptions>(
    builder.Configuration.GetSection(ConfigSigningOptions.SectionName));

// Logging foundations (docs/LOGGING.md). One JSON object per line to stdout
// (human-readable only in Development), every line redacted through the
// TankbookRedactor so a careless call site cannot leak a Sensitive or Never
// value (docs/LOGGING.md §1, CLAUDE.md hard rule 11).
var loggingOptions = builder.Configuration
    .GetSection(LoggingOptions.SectionName)
    .Get<LoggingOptions>() ?? new LoggingOptions();
if (string.IsNullOrWhiteSpace(loggingOptions.Format))
{
    loggingOptions.Format = builder.Environment.IsDevelopment() ? "text" : "json";
}

builder.Services.AddSingleton(loggingOptions);
builder.Services.AddSingleton(new TankbookRedactor(loggingOptions.HashSalt, loggingOptions.RedactSensitiveValues));
builder.Services.AddSingleton(new LogRenderer(
    new TankbookRedactor(loggingOptions.HashSalt, loggingOptions.RedactSensitiveValues),
    AssemblyVersion(),
    loggingOptions.Format == "json"));
builder.Services.AddSingleton<ILogWriter>(new ConsoleLogWriter());

builder.Logging.ClearProviders();
builder.Services.AddSingleton<ILoggerProvider>(sp => new TankbookLoggerProvider(
    sp.GetRequiredService<LogRenderer>(),
    sp.GetRequiredService<ILogWriter>()));

// RFC 7807 problem+json errors, per docs/API.md conventions
// ({ type, title, status, detail }). The traceId extension member rides every
// error body so a support request maps to exact server lines (docs/LOGGING.md §2).
builder.Services.AddProblemDetails(options =>
{
    options.CustomizeProblemDetails = context =>
    {
        if (context.HttpContext.Items[TraceCorrelationMiddleware.TraceIdItemKey] is string traceId)
        {
            context.ProblemDetails.Extensions["traceId"] = traceId;
        }
    };
});

// Npgsql + Dapper are referenced and wired now but not yet used. The server
// stores opaque JSONB records (docs/SYNC.md), so a micro-ORM fits better than
// EF Core. Sync/auth/blob endpoints land in P4.
builder.Services.AddScoped<IDbConnection>(static sp =>
{
    var connectionString = sp
        .GetRequiredService<IOptions<ConnectionStringsOptions>>()
        .Value.Postgres;
    return new NpgsqlConnection(connectionString);
});

// Apply pending SQL migrations (docs/TASKS.md P0.9) at startup. Idempotent,
// self-healing: skips when no connection string is configured, retries with
// backoff until the database accepts the schema.
builder.Services.AddHostedService<MigrationHostedService>();

// Payload contract services (docs/SYNC.md "Payload contract and versioning").
// The validator reads the schema registry from the database, so the server
// validates payload structure without any per-entity C# type. Consumed by the
// /sync/push endpoint in P4.
builder.Services.AddSingleton<PayloadTransformEngine>();
builder.Services.AddScoped<IPayloadSchemaProvider, DatabasePayloadSchemaProvider>();
builder.Services.AddScoped<PayloadValidator>();
builder.Services.AddScoped<PayloadBackfillService>();

// Remote config (docs/CONFIG.md). The signer is a singleton built from the
// Config:SigningKey secret (empty placeholder in appsettings.json, dev default
// in appsettings.Development.json, real value in the platform secret store).
// The read/publish services are scoped over the same Npgsql connection the
// rest of the server uses.
builder.Services.AddSingleton(sp => new ConfigSigner(
    sp.GetRequiredService<IOptions<ConfigSigningOptions>>().Value.SigningKey));
builder.Services.AddSingleton<ConfigSchemaValidator>();
builder.Services.AddScoped<ConfigRepository>();
builder.Services.AddScoped<IConfigReadService, ConfigReadService>();
builder.Services.AddScoped<ConfigPublishService>();

var app = builder.Build();

if (!builder.Environment.IsDevelopment() &&
    (string.IsNullOrWhiteSpace(loggingOptions.HashSalt) ||
     loggingOptions.HashSalt == "tankbook-dev-hash-salt-change-me"))
{
    app.Logger.LogWarning(
        "Tankbook:Logging:HashSalt is unset or the dev placeholder; set it from secrets in production. accountHash is not reliable.");
}

// Trace correlation + the per-request line must wrap everything below so every
// log line for this request carries the traceId (docs/LOGGING.md §2).
app.UseMiddleware<TraceCorrelationMiddleware>();

// Errors become problem+json with the traceId extension member, and every
// ERROR line carries errorCode/exceptionType/message/stackTrace/traceId plus
// safe reproduction context (docs/LOGGING.md §3 Errors).
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

// Non-exception status codes (404/405/…) also render as problem+json with the
// traceId extension member.
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

// Ops: liveness, public, unauthenticated, unversioned (docs/API.md "Ops").
app.MapGet("/health", () => Results.Ok(new HealthResponse("ok", AssemblyVersion())));

// Versioned surface. Everything except /health lives under /v1 per docs/API.md;
// additive evolution within v1, breaking changes become /v2. Endpoints for
// auth, sync, blobs, reference data, feedback, LLM gateway, and account are
// added here in P4.
var v1 = app.MapGroup("/v1");

// Remote config (docs/API.md reference data, docs/CONFIG.md). Both endpoints
// are public - no auth, no account - because guests and signed-out users need
// config too. GET /config honours ETag/If-None-Match (304 when unchanged).
var config = v1.MapGroup("/config");
config.MapGet("", ConfigEndpoints.GetConfig);
config.MapGet("/public-key", ConfigEndpoints.GetPublicKey);

app.Run();

static string AssemblyVersion()
{
    var version = typeof(Program).Assembly
        .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?
        .InformationalVersion;
    if (version is null)
    {
        return "unknown";
    }

    // Strip the git hash suffix (+<sha>) that the SDK appends to InformationalVersion.
    var plus = version.IndexOf('+');
    return plus >= 0 ? version[..plus] : version;
}

internal sealed record HealthResponse(string Status, string Version);

public partial class Program;
