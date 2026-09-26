using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using Microsoft.AspNetCore.Authentication;
using Microsoft.Extensions.Options;

namespace Tankbook.Admin.Auth;

/// <summary>
/// The owner's read key (hard rule 9's debug-cases amendment, docs/SECURITY.md -> "The
/// admin viewer"): a bearer key held on the owner's machine that reads ONE debug case by
/// its id, so a script can fetch what the phone sent. Only its SHA-256 is configured
/// (<c>Admin:ReadKeySha256s</c>, from the secret store). The scheme is accepted by the
/// case routes alone; every other route authenticates by passkey session only, so the key
/// opens nothing else. Each fetch writes an access-log row under the key's label.
/// </summary>
public sealed class ReadKeyHandler(IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger,
    UrlEncoder encoder, IOptions<AdminOptions> admin)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string Scheme = "ReadKey";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.Ordinal))
        {
            return Task.FromResult(AuthenticateResult.NoResult());
        }
        var presented = Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(header["Bearer ".Length..].Trim())));
        var match = admin.Value.ReadKeySha256s.FirstOrDefault(hash => FixedTimeEquals(hash, presented));
        if (match is null)
        {
            return Task.FromResult(AuthenticateResult.Fail("unknown read key"));
        }
        var identity = new ClaimsIdentity([new Claim(AuthEndpoints.LabelClaim, $"read-key:{presented[..8]}")], Scheme);
        return Task.FromResult(AuthenticateResult.Success(new AuthenticationTicket(new ClaimsPrincipal(identity), Scheme)));
    }

    private static bool FixedTimeEquals(string configured, string presented) =>
        CryptographicOperations.FixedTimeEquals(Encoding.ASCII.GetBytes(configured.Trim().ToLowerInvariant()),
                                                Encoding.ASCII.GetBytes(presented));
}
