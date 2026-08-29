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
using Tankbook.Api.Catalog;
using Tankbook.Api.Config;
using Tankbook.Api.Data;
using Tankbook.Api.Http;
using Tankbook.Api.Import;
using Tankbook.Api.Llm;
using Tankbook.Api.Logging;
using Tankbook.Api.Notifications;
using Tankbook.Api.Options;
using Tankbook.Api.RateLimiting;
using Tankbook.Api.Rates;
using Tankbook.Api.Sync;

var builder = WebApplication.CreateBuilder(args);

// Dapper needs a bridge for DateOnly (Npgsql supports it, Dapper's parameter
// engine does not). Registered before any database call; idempotent.
DapperTypeHandlers.Register();

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
builder.Services.Configure<RateOptions>(
    builder.Configuration.GetSection(RateOptions.SectionName));
builder.Services.Configure<LlmGatewayOptions>(
    builder.Configuration.GetSection(LlmGatewayOptions.SectionName));
builder.Services.Configure<CatalogOptions>(
    builder.Configuration.GetSection(CatalogOptions.SectionName));
builder.Services.Configure<ImportOptions>(
    builder.Configuration.GetSection(ImportOptions.SectionName));
builder.Services.Configure<RateLimitOptions>(
    builder.Configuration.GetSection(RateLimitOptions.SectionName));

// The Kestrel default body cap (30 MB) is below a maximal legal sync push batch
// (200 changes x 256 KB + envelope, docs/API.md "Request body caps"), so the
// server-level ceiling is raised to the largest legal body and every endpoint is
// then capped explicitly (BodySizeLimits, PR.17). An oversize body is a 413
// problem+json, never a bare connection reset.
builder.WebHost.ConfigureKestrel(options =>
    options.Limits.MaxRequestBodySize = BodySizeLimits.PushBytes);

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
    client.Timeout = HttpClientTimeouts.Apns;
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

// Vehicle catalog (docs/SYNC.md "Reference data", docs/API.md "Vehicle catalog").
// The publish service validates a pack against its schema and enforces the
// monotonic packVersion before anything is written; the endpoint gates it on the
// Catalog:AdminToken secret, never on a user account. The read side is public.
builder.Services.AddSingleton<CatalogSchemaValidator>();
builder.Services.AddScoped<CatalogRepository>();
builder.Services.AddScoped<CatalogPublishService>();

// Import parsing (docs/API.md "Import parsing", hard rule 9's named exception):
// the one endpoint that reads what a field means. The parser is a pure
// function - it returns candidate proposals and commits nothing. Stored parses
// are purged after 30 days on the same hosted-service pattern as the account
// purge; the timer is registered only outside test hosts so tests drive the
// purge directly.
builder.Services.AddScoped<ImportRepository>();
builder.Services.AddScoped<ImportService>();
builder.Services.AddScoped<ImportPurgeService>();
if (!builder.Environment.IsEnvironment("Testing"))
{
    builder.Services.AddHostedService<ImportPurgeHostedService>();
}

// Auth (docs/API.md Auth, docs/SECURITY.md). The idToken verifier fetches and
// caches Apple/Google JWKS behind IIdTokenVerifier - the seam L2 tests swap for
// a test-signer so they can mint tokens with no network. The access-token
// issuer mints/validates the server's own RS256 JWTs; the signing key is
// Auth:JwtSigningKeyBase64 (ephemeral dev fallback, see JwtAccessTokenIssuer).
builder.Services.AddMemoryCache();
// The bare default client remains for the LLM gateway (its own vendor contract,
// v2); the auth JWKS and the rate feeds each get a named client with a budget
// that fits their caller (docs/PRACTICES.md U6, HttpClientTimeouts) - a slow
// JWKS fetch stalls every sign-in behind it, and a slow feed pins a job thread.
builder.Services.AddHttpClient();
builder.Services.AddHttpClient("jwks", client => client.Timeout = HttpClientTimeouts.Jwks);
builder.Services.AddHttpClient("rates", client => client.Timeout = HttpClientTimeouts.RateFeed);
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
builder.Services.AddScoped<BlobSweepService>();
if (!builder.Environment.IsEnvironment("Testing"))
{
    // The orphan sweep (docs/PRACTICES.md S11, PR.18) runs hourly across every
    // account; like the account/import purges the timer is not registered in
    // test hosts, so tests drive BlobSweepService.SweepAllAsync directly.
    builder.Services.AddHostedService<BlobSweepHostedService>();
}

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

// Exchange rates (docs/SCHEMA.md "Reference data -> Exchange rates"). IRateFeed
// is the feed seam: the daily job talks to ECB/CIS only through it, and L2 tests
// swap in a recording double so the suite never touches a live feed. The real
// HTTP implementations sit behind the interface unexercised. The job is a scoped
// service so tests drive RunAsync directly; the hosted timer that runs it on a
// schedule is registered only outside test hosts (the timer must not run inside
// WebApplicationFactory - the same reason the purge timer is gated).
builder.Services.AddSingleton<IRateFeed>(sp => new EcbRateFeed(sp.GetRequiredService<IHttpClientFactory>()));
builder.Services.AddSingleton<IRateFeed>(sp => new CisRateFeed(sp.GetRequiredService<IHttpClientFactory>()));
builder.Services.AddScoped<RateRepository>();
builder.Services.AddScoped<RatesJobService>();
if (!builder.Environment.IsEnvironment("Testing"))
{
    builder.Services.AddHostedService<RatesHostedService>();
}

// LLM gateway (docs/API.md "LLM gateway (Pro)", docs/EXTRACTION.md). ILlmProvider
// is the model seam: OpenAiCompatibleLlmProvider talks the chat-completions wire
// to the configured base URL (key server-side, docs/SECURITY.md), and L2 tests
// swap in a recording double so the suite never makes a paid call (the same seam
// IBlobStorage / IApnsClient / IRateFeed use). The factory is lazy - an app with
// no Llm config still boots and only fails if /extract is actually called.
builder.Services.AddSingleton<ILlmProvider>(sp =>
    new OpenAiCompatibleLlmProvider(
        sp.GetRequiredService<IHttpClientFactory>(),
        sp.GetRequiredService<IOptions<LlmGatewayOptions>>()));
builder.Services.AddScoped<LlmRepository>();
builder.Services.AddScoped<LlmService>();

// Rate limiting (docs/API.md "Rate limits", PR.17): per-IP on the unauth
// mutating surfaces, per-device on the bearer mutating surfaces. A rejection is
// a 429 problem+json with Retry-After and the traceId (hard rule 7).
builder.Services.AddTankbookRateLimiting(
    builder.Configuration.GetSection(RateLimitOptions.SectionName).Get<RateLimitOptions>() ?? new RateLimitOptions());

var app = builder.Build();

// Startup secrets guard (docs/SECURITY.md, PR.34): a production-like host must
// refuse to start with any committed placeholder or unset secret. A warning is
// not a refusal - a server that boots hashing account ids with a salt printed
// in this repo, or signing config documents with a keypair anyone reading this
// repo can reproduce and forge, has already lost. The message names the setting
// and how to supply it (hard rule 7 applies to operators too).
if (!builder.Environment.IsDevelopment() && !builder.Environment.IsEnvironment("Testing"))
{
    var problems = new List<string>();

    if (string.IsNullOrWhiteSpace(builder.Configuration["Tankbook:Logging:HashSalt"]) ||
        builder.Configuration["Tankbook:Logging:HashSalt"] == LoggingOptions.DevHashSalt)
    {
        problems.Add(
            "Tankbook:Logging:HashSalt is unset or the committed dev placeholder; set it from the platform secret store.");
    }

    if (string.IsNullOrWhiteSpace(builder.Configuration["Config:SigningKey"]) ||
        builder.Configuration["Config:SigningKey"] == ConfigSigningOptions.DevPlaceholderSeed)
    {
        problems.Add(
            "Config:SigningKey is unset or the committed dev placeholder; set it from the platform secret store.");
    }

    if (string.IsNullOrWhiteSpace(builder.Configuration["Auth:JwtSigningKeyBase64"]))
    {
        problems.Add(
            "Auth:JwtSigningKeyBase64 is unset; set it from the platform secret store so access tokens survive a restart and are not signed with an ephemeral key.");
    }

    if (problems.Count > 0)
    {
        throw new InvalidOperationException(
            "Refusing to start outside Development with unsafe secret configuration: " + string.Join(" ", problems));
    }
}

// Trace correlation + the per-request line must wrap everything below so every
// log line for this request carries the traceId (docs/LOGGING.md §2).
app.UseMiddleware<TraceCorrelationMiddleware>();

// Bearer authentication (docs/API.md Auth, adopted by sync/blobs in P4.2/P4.3):
// validates an Authorization header when present and exposes the account/device
// identity via AuthContext. Public endpoints simply see no identity.
app.UseMiddleware<BearerAuthenticationMiddleware>();

// Routing must run before the rate limiter so the per-endpoint policies are
// visible; the rate limiter must run after bearer auth so per-device policies
// can key on the authenticated device (docs/API.md "Rate limits", PR.17).
app.UseRouting();
app.UseRateLimiter();

// Per-endpoint request-body caps (docs/API.md "Request body caps", PR.17):
// enforced after routing so the endpoint's declared cap is visible.
app.UseMiddleware<BodySizeLimitMiddleware>();

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

// Exchange rates (docs/API.md reference data, docs/SCHEMA.md). Both endpoints
// are public - no auth, no account - because guests and signed-out users need
// rates too. Past dates are served immutable; today is revalidatable.
var rates = v1.MapGroup("/rates");
rates.MapGet("", RateEndpoints.GetRates);
rates.MapGet("/pack", RateEndpoints.GetRatesPack);

// Vehicle catalog (docs/API.md "Vehicle catalog", docs/SYNC.md "Reference data").
// GET is public - no auth, no account - because a signed-out user's Add-car
// autocomplete needs the dictionary too. POST /publish is an OPERATOR surface
// gated on the Catalog:AdminToken secret, never on a user account.
var catalog = v1.MapGroup("/catalog");
catalog.MapGet("", CatalogEndpoints.GetCatalog);
catalog.MapPost("/publish", CatalogEndpoints.Publish)
    .RequireRateLimiting(RateLimitingSetup.CatalogPublish)
    .WithBodySizeLimit(BodySizeLimits.CatalogPublishBytes);

// Import parsing (docs/API.md "Import parsing"): the one endpoint that reads
// what a field means, plus the public format list and the stored-parse read and
// drop. GET /formats is public and ETag'd like the other reference data; POST
// and the {importId} routes are public with the bearer optional - import must
// work signed out (hard rule 1's exception covers the network, not a sign-in).
var import = v1.MapGroup("/import");
import.MapGet("/formats", ImportEndpoints.Formats);
// The parse endpoint is a public multipart upload consumed by the native app -
// there are no browser cookies to protect, so the anti-forgery metadata that
// [FromForm] would otherwise attach is disabled (docs/API.md "Import parsing").
import.MapPost("/parse", ImportEndpoints.Parse)
    .DisableAntiforgery()
    .RequireRateLimiting(RateLimitingSetup.ImportParse)
    .WithBodySizeLimit(BodySizeLimits.ImportBytes);
import.MapGet("/{importId:guid}", ImportEndpoints.Get);
import.MapDelete("/{importId:guid}", ImportEndpoints.Delete);

// Auth (docs/API.md Auth): session exchange, refresh rotation, sign-out.
var auth = v1.MapGroup("/auth");
auth.MapPost("/session", AuthEndpoints.CreateSession)
    .RequireRateLimiting(RateLimitingSetup.AuthSession)
    .WithBodySizeLimit(BodySizeLimits.DefaultBytes);
auth.MapPost("/refresh", AuthEndpoints.Refresh)
    .RequireRateLimiting(RateLimitingSetup.AuthRefresh)
    .WithBodySizeLimit(BodySizeLimits.DefaultBytes);
auth.MapDelete("/session", AuthEndpoints.SignOut);

// Sync (docs/API.md Sync, docs/SYNC.md): push and pull over the record stream.
// Both bearer endpoints; fetching the latest data is pulling from 0.
var sync = v1.MapGroup("/sync");
sync.MapGet("/pull", SyncEndpoints.Pull);
sync.MapPost("/push", SyncEndpoints.Push)
    .RequireRateLimiting(RateLimitingSetup.SyncPush)
    .WithBodySizeLimit(BodySizeLimits.PushBytes);

// Attachments (docs/API.md "Attachments"): the content-addressed blob pipeline.
// All three bearer endpoints; the server never proxies file bytes - it only
// mints presigned URLs and keeps the index.
var blobs = v1.MapGroup("/blobs");
blobs.MapPost("/begin", BlobEndpoints.Begin)
    .RequireRateLimiting(RateLimitingSetup.BlobBegin)
    .WithBodySizeLimit(BodySizeLimits.DefaultBytes);
blobs.MapPost("/commit", BlobEndpoints.Commit)
    .WithBodySizeLimit(BodySizeLimits.DefaultBytes);
blobs.MapGet("/{sha256}", BlobEndpoints.Get);

// Account & devices (docs/API.md "Account & devices"): the manage-devices
// screen, push-token registration, per-device revocation, and account deletion.
var account = v1.MapGroup("/account");
account.MapGet("/devices", AccountEndpoints.GetDevices);
account.MapPut("/devices/{id}/push-token", AccountEndpoints.SetPushToken)
    .WithBodySizeLimit(BodySizeLimits.DefaultBytes);
account.MapDelete("/devices/{id}", AccountEndpoints.DeleteDevice);
account.MapDelete("", AccountEndpoints.DeleteAccount);

// LLM gateway (docs/API.md "LLM gateway (Pro)"): POST /v1/extract, bearer.
v1.MapPost("/extract", ExtractEndpoints.Extract)
    .RequireRateLimiting(RateLimitingSetup.Extract)
    .WithBodySizeLimit(BodySizeLimits.ExtractBytes);

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
