using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.Extensions.Options;
using Tankbook.Admin;
using Tankbook.Admin.Access;
using Tankbook.Admin.Auth;
using Tankbook.Admin.Content;
using Tankbook.Admin.Data;

// The admin viewer (docs/SECURITY.md -> "The admin viewer"): a separate service from the
// public API, sharing no project, port or credential with it. `--migrate` applies the
// viewer's own schema and exits.
var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<AdminOptions>(builder.Configuration.GetSection("Admin"));
var admin = builder.Configuration.GetSection("Admin").Get<AdminOptions>() ?? new AdminOptions();

builder.Services.AddSingleton<Db>();
builder.Services.AddSingleton<PasskeyStore>();
builder.Services.AddSingleton<BootstrapTokens>();
builder.Services.AddSingleton<IBlobReader, S3BlobReader>();
builder.Services.AddMemoryCache();

var fido = builder.Configuration.GetSection("Fido2");
builder.Services.AddFido2(options =>
{
    options.RPID = fido["ServerDomain"] ?? "localhost";
    options.RPName = fido["ServerName"] ?? "Tankbook admin";
    options.Origins = fido.GetSection("Origins").Get<string[]>()?.ToHashSet() ?? [];
    options.TimestampDriftTolerance = fido.GetValue("TimestampDriftTolerance", 300000);
});

builder.Services.AddAuthentication(CookieAuthenticationDefaults.AuthenticationScheme)
    .AddCookie(options =>
    {
        options.Cookie.Name = "tankbook_admin";
        options.Cookie.HttpOnly = true;
        options.Cookie.SameSite = SameSiteMode.Strict;
        options.Cookie.SecurePolicy = builder.Environment.IsDevelopment()
            ? CookieSecurePolicy.SameAsRequest
            : CookieSecurePolicy.Always;
        // An absolute lifetime: a session ends on time however busy it was.
        options.ExpireTimeSpan = TimeSpan.FromHours(admin.SessionHours);
        options.SlidingExpiration = false;
        // An API answers 401/403; it never redirects to a login page.
        options.Events.OnRedirectToLogin = context =>
        {
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return Task.CompletedTask;
        };
        options.Events.OnRedirectToAccessDenied = context =>
        {
            context.Response.StatusCode = StatusCodes.Status403Forbidden;
            return Task.CompletedTask;
        };
    })
    .AddScheme<AuthenticationSchemeOptions, ReadKeyHandler>(ReadKeyHandler.Scheme, _ => { });
builder.Services.AddAuthorization();

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy(AuthEndpoints.RateLimitPolicy, http => RateLimitPartition.GetFixedWindowLimiter(
        http.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = admin.SignInPermitsPerMinute, Window = TimeSpan.FromMinutes(1) }));
    options.AddPolicy(CaseEndpoints.RateLimitPolicy, http => RateLimitPartition.GetFixedWindowLimiter(
        http.Connection.RemoteIpAddress?.ToString() ?? "unknown",
        _ => new FixedWindowRateLimiterOptions { PermitLimit = admin.CaseReadsPerMinute, Window = TimeSpan.FromMinutes(1) }));
});

var app = builder.Build();

if (args.Contains("--migrate"))
{
    var applied = await Migrator.ApplyAsync(app.Services.GetRequiredService<Db>());
    app.Logger.LogInformation("admin.migrate {Applied}", applied);
    return;
}

await app.Services.GetRequiredService<BootstrapTokens>().SeedAsync();

app.Use(async (http, next) =>
{
    var headers = http.Response.Headers;
    headers["Content-Security-Policy"] = "default-src 'self'; img-src 'self' data: blob:; frame-ancestors 'none'";
    headers["X-Content-Type-Options"] = "nosniff";
    headers["Referrer-Policy"] = "no-referrer";
    headers["X-Frame-Options"] = "DENY";
    await next();
});

app.UseDefaultFiles();
app.UseStaticFiles();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.UseMiddleware<AccessLogMiddleware>();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
AuthEndpoints.Map(app);

// Debug cases by id: the passkey session or the owner's read key. The read key's scheme is
// named here and nowhere else, so it opens these routes alone - every other /api route
// authenticates with the default (session) scheme only.
var sessionScheme = app.Services.GetRequiredService<IOptions<AuthenticationOptions>>().Value.DefaultAuthenticateScheme
    ?? CookieAuthenticationDefaults.AuthenticationScheme;
var cases = app.MapGroup("/api/cases")
    .RequireAuthorization(policy => policy.AddAuthenticationSchemes(sessionScheme, ReadKeyHandler.Scheme)
        .RequireAuthenticatedUser())
    .RequireRateLimiting(CaseEndpoints.RateLimitPolicy);
CaseEndpoints.Map(cases);

var api = app.MapGroup("/api").RequireAuthorization();
api.MapGet("/me", (HttpContext http) => Results.Ok(new { label = AuthEndpoints.Actor(http.User) }));
AccountEndpoints.Map(api);
LlmCallEndpoints.Map(api);
AttachmentEndpoints.Map(api);
AccessLogEndpoints.Map(api);
// An unknown /api route is a 404, never the app's index page.
api.MapFallback(() => Results.NotFound());

app.MapFallbackToFile("index.html");

app.Run();

/// <summary>Exposed for the integration tests' <c>WebApplicationFactory</c>.</summary>
public partial class Program;
