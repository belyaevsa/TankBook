using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;
using Tankbook.Api.Auth;

namespace Tankbook.Api.Tests.Auth;

/// <summary>
/// The REAL identity-token verifier, exercised directly.
/// </summary>
/// <remarks>
/// Written with SH.4 (2026-09-01). Until then this class had no tests at all:
/// every L2 endpoint test injects <c>TestIdTokenSigner.Verifier</c>, which is a
/// reimplementation that checks the signature and the expiry and nothing else -
/// so the audience, issuer and email_verified rules were unpinned in the one
/// place they are actually enforced. A double that stands in for the code under
/// test cannot test it.
///
/// The audience check is the load-bearing one. Apple's and Google's JWKS sign
/// identity tokens for **every** client on their platforms, so a signature alone
/// proves only that the provider minted the token - not that it was minted for
/// us. Without <c>aud</c>, anyone who ships an app with Google sign-in can
/// collect their own users' id tokens and replay them at
/// <c>POST /v1/auth/session</c> to take over the matching Tankbook account.
/// </remarks>
public sealed class AppleGoogleIdTokenVerifierTests
{
    private const string GoogleClient = "1234567890-abcdef.apps.googleusercontent.com";
    private const string AppleBundleId = "app.tankbook.Tankbook";

    private readonly RSA _rsa = RSA.Create(2048);

    [Fact]
    public async Task ValidGoogleToken_IsAccepted()
    {
        var verifier = CreateVerifier();
        var token = Mint("google", audience: GoogleClient);

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.Valid, result.Outcome);
        Assert.Equal("sub-1", result.Subject);
        Assert.Equal("driver@example.com", result.Email);
    }

    [Fact]
    public async Task ValidAppleToken_IsAccepted()
    {
        var verifier = CreateVerifier();
        var token = Mint("apple", audience: AppleBundleId);

        var result = await verifier.VerifyAsync("apple", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.Valid, result.Outcome);
    }

    /// <summary>
    /// The takeover case, stated as a test: a correctly signed, unexpired,
    /// email-verified Google token minted for somebody else's OAuth client.
    /// Everything about it is genuine except who it was issued to.
    /// </summary>
    [Fact]
    public async Task TokenMintedForAnotherClient_IsRejected()
    {
        var verifier = CreateVerifier();
        var token = Mint("google", audience: "999-attacker.apps.googleusercontent.com");

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.WrongAudience, result.Outcome);
        Assert.Null(result.Subject);
    }

    /// <summary>
    /// The two providers' audiences are separate allowlists: an Apple token
    /// carrying the Google client id is not ours either.
    /// </summary>
    [Fact]
    public async Task AudiencesDoNotCrossProviders()
    {
        var verifier = CreateVerifier();
        var token = Mint("apple", audience: GoogleClient);

        var result = await verifier.VerifyAsync("apple", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.WrongAudience, result.Outcome);
    }

    /// <summary>
    /// RFC 7519 allows `aud` to be an array, and both providers have used both
    /// shapes. Reading only the string form would reject a legitimate token for
    /// a reason unrelated to who minted it.
    /// </summary>
    [Fact]
    public async Task AudienceArrayContainingOurClient_IsAccepted()
    {
        var verifier = CreateVerifier();
        var token = Mint("google", audiences: ["someone-else", GoogleClient]);

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.Valid, result.Outcome);
    }

    [Fact]
    public async Task AudienceArrayWithoutOurClient_IsRejected()
    {
        var verifier = CreateVerifier();
        var token = Mint("google", audiences: ["someone-else", "another"]);

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.WrongAudience, result.Outcome);
    }

    [Fact]
    public async Task TokenWithNoAudienceClaim_IsRejected()
    {
        var verifier = CreateVerifier();
        var token = Mint("google", audience: null);

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.WrongAudience, result.Outcome);
    }

    /// <summary>
    /// An unconfigured audience must fail CLOSED. If an empty allowlist meant
    /// "accept anything", the entire check could be disabled by forgetting to
    /// deploy one setting - and it would look like it was working.
    /// </summary>
    [Fact]
    public async Task NoConfiguredAudience_RefusesEveryToken()
    {
        var verifier = CreateVerifier(googleAudiences: []);
        var token = Mint("google", audience: GoogleClient);

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.AudienceNotConfigured, result.Outcome);
    }

    [Fact]
    public async Task TokenFromAnotherIssuer_IsRejected()
    {
        var verifier = CreateVerifier();
        var token = Mint("google", audience: GoogleClient, issuer: "https://evil.example.com");

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.WrongIssuer, result.Outcome);
    }

    /// <summary>Google documents both forms of its issuer, and mints both.</summary>
    [Theory]
    [InlineData("https://accounts.google.com")]
    [InlineData("accounts.google.com")]
    public async Task BothGoogleIssuerFormsAreAccepted(string issuer)
    {
        var verifier = CreateVerifier();
        var token = Mint("google", audience: GoogleClient, issuer: issuer);

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.Valid, result.Outcome);
    }

    /// <summary>
    /// The audience is checked before the payload is otherwise trusted, so a
    /// token that is BOTH foreign and expired reports the audience - the more
    /// serious of the two, and the one that does not go away by waiting.
    /// </summary>
    [Fact]
    public async Task WrongAudienceIsReportedAheadOfExpiry()
    {
        var verifier = CreateVerifier();
        var token = Mint(
            "google",
            audience: "999-attacker.apps.googleusercontent.com",
            expiresAt: DateTimeOffset.UtcNow.AddHours(-1));

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.WrongAudience, result.Outcome);
    }

    [Fact]
    public async Task UnverifiedEmail_IsRejected()
    {
        var verifier = CreateVerifier();
        var token = Mint("google", audience: GoogleClient, emailVerified: false);

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.EmailNotVerified, result.Outcome);
    }

    /// <summary>
    /// A token signed with a key that is not in the JWKS. The signature check is
    /// the floor everything else rests on, and it had no test either.
    /// </summary>
    [Fact]
    public async Task TokenSignedByAnotherKey_IsRejected()
    {
        var verifier = CreateVerifier();
        using var other = RSA.Create(2048);
        var token = Mint("google", audience: GoogleClient, signingKey: other);

        var result = await verifier.VerifyAsync("google", token, CancellationToken.None);

        Assert.Equal(IdTokenOutcome.InvalidSignature, result.Outcome);
    }

    // ---- helpers -------------------------------------------------------

    private AppleGoogleIdTokenVerifier CreateVerifier(
        string[]? googleAudiences = null,
        string[]? appleAudiences = null)
    {
        var options = new AuthOptions
        {
            GoogleAudiences = googleAudiences ?? [GoogleClient],
            AppleAudiences = appleAudiences ?? [AppleBundleId],
        };
        return new AppleGoogleIdTokenVerifier(
            new StubHttpClientFactory(Jwks()),
            new MemoryCache(new MemoryCacheOptions()),
            Microsoft.Extensions.Options.Options.Create(options),
            TimeProvider.System);
    }

    private string Mint(
        string provider,
        string? audience = null,
        string[]? audiences = null,
        string? issuer = null,
        bool emailVerified = true,
        DateTimeOffset? expiresAt = null,
        RSA? signingKey = null)
    {
        var now = DateTimeOffset.UtcNow;
        var header = JsonSerializer.Serialize(new { alg = "RS256", typ = "JWT", kid = "test-key" });

        var claims = new Dictionary<string, object>
        {
            ["iss"] = issuer ?? (provider == "apple" ? "https://appleid.apple.com" : "https://accounts.google.com"),
            ["sub"] = "sub-1",
            ["email"] = "driver@example.com",
            ["email_verified"] = emailVerified,
            ["iat"] = now.ToUnixTimeSeconds(),
            ["exp"] = (expiresAt ?? now.AddHours(1)).ToUnixTimeSeconds(),
        };
        if (audiences is not null)
        {
            claims["aud"] = audiences;
        }
        else if (audience is not null)
        {
            claims["aud"] = audience;
        }

        return JwtCodec.Sign(header, JsonSerializer.Serialize(claims), signingKey ?? _rsa);
    }

    private string Jwks()
    {
        var parameters = _rsa.ExportParameters(false);
        return JsonSerializer.Serialize(new
        {
            keys = new[]
            {
                new
                {
                    kid = "test-key",
                    kty = "RSA",
                    alg = "RS256",
                    n = JwtCodec.Base64UrlEncode(parameters.Modulus!),
                    e = JwtCodec.Base64UrlEncode(parameters.Exponent!),
                },
            },
        });
    }

    /// <summary>Serves one JWKS document to every request; no network.</summary>
    private sealed class StubHttpClientFactory : IHttpClientFactory
    {
        private readonly string _jwks;

        public StubHttpClientFactory(string jwks) => _jwks = jwks;

        public HttpClient CreateClient(string name) => new(new StubHandler(_jwks));

        private sealed class StubHandler : HttpMessageHandler
        {
            private readonly string _jwks;

            public StubHandler(string jwks) => _jwks = jwks;

            protected override Task<HttpResponseMessage> SendAsync(
                HttpRequestMessage request, CancellationToken cancellationToken)
                => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(_jwks),
                });
        }
    }
}
