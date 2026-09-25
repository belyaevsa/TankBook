using System.Security.Claims;
using System.Security.Cryptography;
using Fido2NetLib;
using Fido2NetLib.Objects;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.Extensions.Caching.Memory;

namespace Tankbook.Admin.Auth;

/// <summary>
/// Passkey registration and sign-in (WebAuthn, docs/SECURITY.md -> "The admin viewer").
/// A ceremony's options are held server-side for five minutes under a random id the client
/// echoes back; nothing about a ceremony lives in a cookie. There is no password path.
/// </summary>
public static class AuthEndpoints
{
    public const string LabelClaim = "tankbook:passkey-label";
    public const string PasskeyIdClaim = "tankbook:passkey-id";
    public const string RateLimitPolicy = "signin";

    private static readonly TimeSpan CeremonyLifetime = TimeSpan.FromMinutes(5);

    public sealed record RegisterOptionsRequest(string? BootstrapToken, string? Label);
    public sealed record CeremonyReply(string CeremonyId, object Options);
    public sealed record RegisterVerifyRequest(string CeremonyId, AuthenticatorAttestationRawResponse Response);
    public sealed record LoginVerifyRequest(string CeremonyId, AuthenticatorAssertionRawResponse Response);

    private sealed record PendingRegistration(CredentialCreateOptions Options, string Label, string? BootstrapToken);

    public static void Map(WebApplication app)
    {
        var auth = app.MapGroup("/auth").RequireRateLimiting(RateLimitPolicy);
        auth.MapPost("/register/options", RegisterOptions);
        auth.MapPost("/register/verify", RegisterVerify);
        auth.MapPost("/login/options", LoginOptions);
        auth.MapPost("/login/verify", LoginVerify);
        auth.MapPost("/logout", async (HttpContext http) =>
        {
            await http.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            return Results.NoContent();
        });
    }

    private static async Task<IResult> RegisterOptions(RegisterOptionsRequest body, HttpContext http, IFido2 fido2,
        PasskeyStore passkeys, BootstrapTokens tokens, IMemoryCache cache, ILoggerFactory loggers)
    {
        var log = loggers.CreateLogger("admin.register");
        var signedIn = http.User.Identity?.IsAuthenticated == true;
        if (!signedIn && !await tokens.IsValidAsync(body.BootstrapToken))
        {
            log.LogInformation("admin.register {Outcome}", "refused");
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        }
        var label = string.IsNullOrWhiteSpace(body.Label) ? "passkey" : body.Label.Trim()[..Math.Min(body.Label.Trim().Length, 40)];
        var existing = await passkeys.AllAsync();
        // One owner: every passkey shares the owner's user handle, so a second device's
        // passkey signs in as the same person.
        var userHandle = existing.FirstOrDefault()?.UserHandle ?? RandomNumberGenerator.GetBytes(32);
        var options = fido2.RequestNewCredential(new RequestNewCredentialParams
        {
            User = new Fido2User { Id = userHandle, Name = "owner", DisplayName = "Tankbook owner" },
            ExcludeCredentials = existing.Select(p => new PublicKeyCredentialDescriptor(p.CredentialId)).ToList(),
            AuthenticatorSelection = new AuthenticatorSelection
            {
                ResidentKey = ResidentKeyRequirement.Required,
                UserVerification = UserVerificationRequirement.Required,
            },
            AttestationPreference = AttestationConveyancePreference.None,
        });
        var ceremonyId = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(16));
        cache.Set(ceremonyId, new PendingRegistration(options, label, signedIn ? null : body.BootstrapToken), CeremonyLifetime);
        return Results.Json(new CeremonyReply(ceremonyId, options));
    }

    private static async Task<IResult> RegisterVerify(RegisterVerifyRequest body, HttpContext http, IFido2 fido2,
        PasskeyStore passkeys, BootstrapTokens tokens, IMemoryCache cache, ILoggerFactory loggers, CancellationToken ct)
    {
        var log = loggers.CreateLogger("admin.register");
        if (!cache.TryGetValue(body.CeremonyId, out PendingRegistration? pending) || pending is null)
        {
            return Results.BadRequest();
        }
        cache.Remove(body.CeremonyId);
        // The token is re-checked here: it may have been consumed by another ceremony since.
        if (pending.BootstrapToken is not null && !await tokens.IsValidAsync(pending.BootstrapToken))
        {
            log.LogInformation("admin.register {Outcome}", "refused");
            return Results.StatusCode(StatusCodes.Status403Forbidden);
        }
        RegisteredPublicKeyCredential credential;
        try
        {
            credential = await fido2.MakeNewCredentialAsync(new MakeNewCredentialParams
            {
                AttestationResponse = body.Response,
                OriginalOptions = pending.Options,
                IsCredentialIdUniqueToUserCallback = async (args, _) => await passkeys.FindAsync(args.CredentialId) is null,
            }, ct);
        }
        catch (Fido2VerificationException)
        {
            log.LogInformation("admin.register {Outcome}", "invalid");
            return Results.BadRequest();
        }
        var passkey = new Passkey(Guid.NewGuid(), credential.Id, credential.PublicKey, credential.SignCount,
            pending.Options.User.Id, pending.Label);
        await passkeys.AddAsync(passkey);
        if (pending.BootstrapToken is not null)
        {
            await tokens.ConsumeAsync(pending.BootstrapToken);
        }
        log.LogInformation("admin.register {Outcome}", "ok");
        await SignInAsync(http, passkey);
        return Results.Ok(new { label = passkey.Label });
    }

    private static async Task<IResult> LoginOptions(IFido2 fido2, PasskeyStore passkeys, IMemoryCache cache)
    {
        var options = fido2.GetAssertionOptions(new GetAssertionOptionsParams
        {
            AllowedCredentials = (await passkeys.AllAsync())
                .Select(p => new PublicKeyCredentialDescriptor(p.CredentialId)).ToList(),
            UserVerification = UserVerificationRequirement.Required,
        });
        var ceremonyId = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(16));
        cache.Set(ceremonyId, options, CeremonyLifetime);
        return Results.Json(new CeremonyReply(ceremonyId, options));
    }

    private static async Task<IResult> LoginVerify(LoginVerifyRequest body, HttpContext http, IFido2 fido2,
        PasskeyStore passkeys, IMemoryCache cache, ILoggerFactory loggers, CancellationToken ct)
    {
        var log = loggers.CreateLogger("admin.signin");
        if (!cache.TryGetValue(body.CeremonyId, out AssertionOptions? options) || options is null)
        {
            return Results.BadRequest();
        }
        cache.Remove(body.CeremonyId);
        var passkey = await passkeys.FindAsync(body.Response.RawId);
        if (passkey is null)
        {
            log.LogInformation("admin.signin {Outcome}", "unknown");
            return Results.Unauthorized();
        }
        try
        {
            var result = await fido2.MakeAssertionAsync(new MakeAssertionParams
            {
                AssertionResponse = body.Response,
                OriginalOptions = options,
                StoredPublicKey = passkey.PublicKey,
                StoredSignatureCounter = (uint)passkey.SignCount,
                IsUserHandleOwnerOfCredentialIdCallback = (args, _) =>
                    Task.FromResult(args.UserHandle.AsSpan().SequenceEqual(passkey.UserHandle)),
            }, ct);
            await passkeys.TouchAsync(passkey.Id, result.SignCount);
        }
        catch (Fido2VerificationException)
        {
            // Includes a signature counter that went backwards - a cloned authenticator.
            log.LogInformation("admin.signin {Outcome}", "invalid");
            return Results.Unauthorized();
        }
        log.LogInformation("admin.signin {Outcome}", "ok");
        await SignInAsync(http, passkey);
        return Results.Ok(new { label = passkey.Label });
    }

    private static Task SignInAsync(HttpContext http, Passkey passkey)
    {
        var identity = new ClaimsIdentity(
            [new Claim(LabelClaim, passkey.Label), new Claim(PasskeyIdClaim, passkey.Id.ToString())],
            CookieAuthenticationDefaults.AuthenticationScheme);
        return http.SignInAsync(CookieAuthenticationDefaults.AuthenticationScheme, new ClaimsPrincipal(identity),
            new AuthenticationProperties { IsPersistent = false });
    }

    /// <summary>The actor the access log records: the passkey's label, never an email.</summary>
    public static string Actor(ClaimsPrincipal user) =>
        user.FindFirst(LabelClaim)?.Value ?? user.Identity?.Name ?? "unknown";
}
