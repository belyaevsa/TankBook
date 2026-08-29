using System.Net;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;

namespace Tankbook.Api.Tests;

/// <summary>
/// PR.34 (docs/SECURITY.md "Backend - secret management"): outside Development
/// a host must refuse to start with a committed placeholder or unset secret. A
/// warning is not a refusal - a server that boots hashing account ids with a
/// salt printed in this repo, or signing config with a keypair anyone can
/// reproduce, has already lost.
/// </summary>
public class StartupRefusalTests
{
    // A valid 32-byte Ed25519 seed that is NOT the committed placeholder.
    private const string ValidSeed = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

    private const string ValidSalt = "a-real-secret-salt-not-the-placeholder";

    // A valid PKCS#8 RSA private key, so a host that clears the guard can build
    // the bearer middleware (which parses this key) and answer /health.
    private static readonly string ValidJwtKey = GenerateJwtKey();

    [Fact]
    public void ProductionHost_WithDefaultSalt_RefusesToStart_NamingTheSetting()
    {
        var factory = Build(
            ("Config:SigningKey", ValidSeed),
            ("Auth:JwtSigningKeyBase64", ValidJwtKey));

        var ex = Assert.ThrowsAny<Exception>(() => factory.CreateClient());

        Assert.Contains("HashSalt", ex.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void ProductionHost_WithCommittedPlaceholderSigningKey_RefusesToStart_NamingTheSetting()
    {
        // Config:SigningKey is left as the committed placeholder from appsettings.json.
        var factory = Build(
            ("Tankbook:Logging:HashSalt", ValidSalt),
            ("Auth:JwtSigningKeyBase64", ValidJwtKey));

        var ex = Assert.ThrowsAny<Exception>(() => factory.CreateClient());

        Assert.Contains("SigningKey", ex.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public void ProductionHost_WithUnsetJwtSigningKey_RefusesToStart_NamingTheSetting()
    {
        var factory = Build(
            ("Tankbook:Logging:HashSalt", ValidSalt),
            ("Config:SigningKey", ValidSeed));

        var ex = Assert.ThrowsAny<Exception>(() => factory.CreateClient());

        Assert.Contains("JwtSigningKeyBase64", ex.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task ProductionHost_WithAllSecretsSet_Starts()
    {
        // The guard is a refusal on placeholders, not on production itself: with
        // every secret supplied the host boots (the smoke test only reaches the
        // liveness endpoint, so no database is needed).
        var factory = Build(
            ("Tankbook:Logging:HashSalt", ValidSalt),
            ("Config:SigningKey", ValidSeed),
            ("Auth:JwtSigningKeyBase64", ValidJwtKey));

        using var client = factory.CreateClient();
        var response = await client.GetAsync("/health");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    private static WebApplicationFactory<Program> Build(params (string Key, string? Value)[] settings)
    {
        return new WebApplicationFactory<Program>()
            .WithWebHostBuilder(b =>
            {
                b.UseEnvironment("Production");
                b.ConfigureAppConfiguration((_, cfg) => cfg.AddInMemoryCollection(
                    settings.Select(s => new KeyValuePair<string, string?>(s.Key, s.Value))));
            });
    }

    private static string GenerateJwtKey()
    {
        using var rsa = RSA.Create(2048);
        return Convert.ToBase64String(rsa.ExportPkcs8PrivateKey());
    }
}
