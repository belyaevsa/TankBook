using System.Security.Claims;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Tankbook.Admin.Auth;
using Tankbook.Admin.Data;

namespace Tankbook.Admin.Tests;

/// <summary>
/// The service against the suite's database. A request carrying <c>X-Test-Passkey</c> is
/// signed in as that passkey label through a test scheme - the real WebAuthn ceremony
/// needs an authenticator; the cookie scheme stays registered for sign-in itself.
/// </summary>
public sealed class AdminFactory(AdminDatabase database) : WebApplicationFactory<Program>
{
    /// <summary>The bucket, in memory: key -> bytes.</summary>
    public Dictionary<string, byte[]> Blobs { get; } = new();

    public const string BootstrapToken = "test-bootstrap-token";
    public const string TestHeader = "X-Test-Passkey";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Development");
        builder.ConfigureAppConfiguration(config => config.AddInMemoryCollection(new Dictionary<string, string?>
        {
            ["ConnectionStrings:ApiRead"] = database.ApiRead,
            ["ConnectionStrings:AdminWrite"] = database.AdminWrite,
            ["Admin:BootstrapToken"] = BootstrapToken,
            ["Admin:SignInPermitsPerMinute"] = "1000",
        }));
        builder.ConfigureServices(services =>
        {
            services.AddSingleton<IBlobReader>(new MemoryBlobs(Blobs));
            services.AddAuthentication().AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("Test", _ => { });
            services.PostConfigure<AuthenticationOptions>(options =>
            {
                options.DefaultAuthenticateScheme = "Test";
                options.DefaultChallengeScheme = "Test";
            });
        });
    }

    private sealed class MemoryBlobs(Dictionary<string, byte[]> blobs) : IBlobReader
    {
        public Task<byte[]?> ReadAsync(string key, CancellationToken ct) =>
            Task.FromResult(blobs.TryGetValue(key, out var bytes) ? bytes : null);
    }

    private sealed class TestAuthHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger,
        UrlEncoder encoder) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
    {
        protected override Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            if (!Request.Headers.TryGetValue(TestHeader, out var label))
            {
                return Task.FromResult(AuthenticateResult.NoResult());
            }
            var identity = new ClaimsIdentity([new Claim(AuthEndpoints.LabelClaim, label.ToString())], "Test");
            return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), "Test")));
        }
    }
}
