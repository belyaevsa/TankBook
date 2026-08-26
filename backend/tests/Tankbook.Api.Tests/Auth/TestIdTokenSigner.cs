using System.Security.Cryptography;
using System.Text.Json;
using Tankbook.Api.Auth;

namespace Tankbook.Api.Tests.Auth;

/// <summary>
/// The test seam for idToken verification (docs/TESTING.md "mock the boundary"):
/// mints RS256 identity tokens with a throwaway key and verifies them with the
/// same key, so L2 tests exercise the real auth pipeline with no network and no
/// Apple/Google dependency.
/// </summary>
internal sealed class TestIdTokenSigner
{
    private readonly RSA _rsa = RSA.Create(2048);

    /// <summary>An <see cref="IIdTokenVerifier"/> that accepts only this signer's tokens.</summary>
    public IIdTokenVerifier Verifier => new TestVerifier(_rsa);

    public string Mint(
        string provider,
        string subject,
        string email,
        DateTimeOffset? expiresAt = null,
        DateTimeOffset? issuedAt = null,
        bool emailVerified = true)
    {
        var now = DateTimeOffset.UtcNow;
        var header = JsonSerializer.Serialize(new { alg = "RS256", typ = "JWT", kid = "test-key" });
        var payload = JsonSerializer.Serialize(new
        {
            iss = provider == "apple" ? "https://appleid.apple.com" : "https://accounts.google.com",
            aud = "tankbook",
            sub = subject,
            email,
            email_verified = emailVerified,
            iat = (issuedAt ?? now).ToUnixTimeSeconds(),
            exp = (expiresAt ?? now.AddHours(1)).ToUnixTimeSeconds(),
        });
        return JwtCodec.Sign(header, payload, _rsa);
    }

    public string MintExpired(string provider, string subject, string email)
        => Mint(provider, subject, email, expiresAt: DateTimeOffset.UtcNow.AddHours(-1));

    private sealed class TestVerifier : IIdTokenVerifier
    {
        private readonly RSA _rsa;

        public TestVerifier(RSA rsa) => _rsa = rsa;

        public Task<IdTokenVerificationResult> VerifyAsync(string provider, string idToken, CancellationToken cancellationToken)
        {
            if (provider is not ("apple" or "google"))
            {
                return Task.FromResult(IdTokenVerificationResult.Failed(IdTokenOutcome.UnsupportedProvider));
            }

            if (!JwtCodec.TryDecode(idToken, out _, out var payloadJson))
            {
                return Task.FromResult(IdTokenVerificationResult.Failed(IdTokenOutcome.Malformed));
            }

            if (!JwtCodec.VerifyRsa256(idToken, _rsa))
            {
                return Task.FromResult(IdTokenVerificationResult.Failed(IdTokenOutcome.InvalidSignature));
            }

            using var payload = JsonDocument.Parse(payloadJson);
            var root = payload.RootElement;
            var subject = root.GetProperty("sub").GetString() ?? "";
            var email = root.GetProperty("email").GetString() ?? "";
            var exp = root.GetProperty("exp").GetInt64();
            if (exp <= DateTimeOffset.UtcNow.ToUnixTimeSeconds())
            {
                return Task.FromResult(IdTokenVerificationResult.Failed(IdTokenOutcome.Expired));
            }

            return Task.FromResult(IdTokenVerificationResult.Ok(subject, email));
        }
    }
}
