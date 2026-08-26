using System.Data;
using System.Net;
using System.Reflection;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;
using Npgsql;
using Tankbook.Api.Account;
using Tankbook.Api.Auth;
using Tankbook.Api.Blobs;
using Tankbook.Api.Config;
using Tankbook.Api.Data;
using Tankbook.Api.Logging;
using Tankbook.Api.Notifications;
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
builder.Services.Configure<BlobOptions>(
    builder.Configuration.GetSection(BlobOptions.SectionName));
builder.Services.Configure<ConfigSigningOptions>(
    builder.Configuration.GetSection(ConfigSigningOptions.SectionName));
builder.Services.Configure<AuthOptions>(
    builder.Configuration.GetSection(AuthOptions.SectionName));
builder.Services.Configure<AccountOptions>(
    builder.Configuration.GetSection(AccountOptions.SectionName));
builder.Services.Configure<ApnsOptions>(
    builder.Configuration.GetSection(ApnsOptions.SectionName));
builder.Services.Configure<NudgeOptions>(
    builder.Configuration.GetSection(NudgeOptions.SectionName));

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
builder.Services.AddScoped<SyncRepository>();
builder.Services.AddScoped<SyncService>();

// Silent sync nudges (docs/NOTIFICATIONS.md). IApnsClient is the APNs seam:
// ApnsClient talks HTTP/2 to Apple (token-based JWT auth), and L2 tests swap in
// a recording double (the same seam IBlobStorage uses). The factory is lazy - an
// app with no Apns config still boots - and the client reports "not configured"
// as a transient failure, so a nudge degrades to polling instead of erroring.
builder.Services.AddHttpClient("apns", client =>
{
    client.DefaultRequestVersion = HttpVersion.Version20;
    client.DefaultVersionPolicy = HttpVersionPolicy.RequestVersionExact;
});
builder.Services.AddSingleton<IApnsClient>(sp =>
    new ApnsClient(
        sp.GetRequiredService<IHttpClientFactory>(),
        sp.GetRequiredService<IOptions<ApnsOptions>>(),
        sp.GetRequiredService<TimeProvider>()));
builder.Services.AddScoped<NudgeRepository>();
builder.Services.AddScoped<SyncNudgeService>();

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

// Auth (docs/API.md Auth, docs/SECURITY.md). The idToken verifier fetches and
// caches Apple/Google JWKS behind IIdTokenVerifier - the seam L2 tests swap for
// a test-signer so they can mint tokens with no network. The access-token
// issuer mints/validates the server's own RS256 JWTs; the signing key is
// Auth:JwtSigningKeyBase64 (ephemeral dev fallback, see JwtAccessTokenIssuer).
builder.Services.AddMemoryCache();
builder.Services.AddHttpClient();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<JwtAccessTokenIssuer>();
builder.Services.AddSingleton<AppleGoogleIdTokenVerifier>();
builder.Services.AddSingleton<IIdTokenVerifier>(sp => sp.GetRequiredService<AppleGoogleIdTokenVerifier>());
builder.Services.AddScoped<AuthRepository>();
builder.Services.AddScoped<AuthService>();

// Blob pipeline (docs/API.md "Attachments", docs/SYNC.md "Attachments: the blob
// pipeline"). IBlobStorage is the storage seam: S3BlobStorage talks the S3 API
// (MinIO locally, R2/B2/etc. in deployment - the credentials are server-side,
// docs/SECURITY.md) and L2 tests swap in a recording double so presign generation
// and expiry are assertable without a running container (the same seam
// IPayloadSchemaProvider uses). The factory is lazy: an app with no S3 config
// still boots, and only fails if a blob endpoint is actually called.
builder.Services.AddSingleton<IBlobStorage>(sp =>
    new S3BlobStorage(
        sp.GetRequiredService<IOptions<S3Options>>(),
        sp.GetRequiredService<TimeProvider>()));
builder.Services.AddScoped<BlobRepository>();
builder.Services.AddScoped<BlobService>();

// Account & devices (docs/API.md "Account & devices") and the grace purge job
// (docs/SYNC.md "Offline & failure behavior"). The purge is a scoped service so
// tests resolve it and drive one pass directly; the hosted timer that runs it on
// a schedule is registered only outside test hosts (the timer must not run
// inside WebApplicationFactory - P4.3 declined to add one for exactly that reason).
builder.Services.AddScoped<AccountRepository>();
builder.Services.AddScoped<AccountService>();
builder.Services.AddScoped<AccountPurgeService>();
if (!builder.Environment.IsEnvironment("Testing"))
{
    builder.Services.AddHostedService<AccountPurgeHostedService>();
}

var app = builder.Build();

if (!builder.Environment.IsDevelopment() &&
    (string.IsNullOrWhiteSpace(loggingOptions.HashSalt) ||
     loggingOptions.HashSalt == "tankbook-dev-hash-salt-change-me"))
{
    app.Logger.LogWarning(
        "Tankbook:Logging:HashSalt is unset or the dev placeholder; set it from secrets in production. accountHash is not reliable.");
}

if (!builder.Environment.IsDevelopment() &&
    string.IsNullOrWhiteSpace(builder.Configuration["Auth:JwtSigningKeyBase64"]))
{
    app.Logger.LogWarning(
        "Auth:JwtSigningKeyBase64 is unset; access tokens are signed with an ephemeral key and will not survive a restart. Set it from secrets in production.");
}

// Trace correlation + the per-request line must wrap everything below so every
// log line for this request carries the traceId (docs/LOGGING.md §2).
app.UseMiddleware<TraceCorrelationMiddleware>();

// Bearer authentication (docs/API.md Auth, adopted by sync/blobs in P4.2/P4.3):
// validates an Authorization header when present and exposes the account/device
// identity via AuthContext. Public endpoints simply see no identity.
app.UseMiddleware<BearerAuthenticationMiddleware>();

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

// Auth (docs/API.md Auth): session exchange, refresh rotation, sign-out.
var auth = v1.MapGroup("/auth");
auth.MapPost("/session", AuthEndpoints.CreateSession);
auth.MapPost("/refresh", AuthEndpoints.Refresh);
auth.MapDelete("/session", AuthEndpoints.SignOut);

// Sync (docs/API.md Sync, docs/SYNC.md): push and pull over the record stream.
// Both bearer endpoints; fetching the latest data is pulling from 0.
var sync = v1.MapGroup("/sync");
sync.MapGet("/pull", SyncEndpoints.Pull);
sync.MapPost("/push", SyncEndpoints.Push);

// Attachments (docs/API.md "Attachments"): the content-addressed blob pipeline.
// All three bearer endpoints; the server never proxies file bytes - it only
// mints presigned URLs and keeps the index.
var blobs = v1.MapGroup("/blobs");
blobs.MapPost("/begin", BlobEndpoints.Begin);
blobs.MapPost("/commit", BlobEndpoints.Commit);
blobs.MapGet("/{sha256}", BlobEndpoints.Get);

// Account & devices (docs/API.md "Account & devices"): the manage-devices
// screen, push-token registration, per-device revocation, and account deletion.
var account = v1.MapGroup("/account");
account.MapGet("/devices", AccountEndpoints.GetDevices);
account.MapPut("/devices/{id}/push-token", AccountEndpoints.SetPushToken);
account.MapDelete("/devices/{id}", AccountEndpoints.DeleteDevice);
account.MapDelete("", AccountEndpoints.DeleteAccount);

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
