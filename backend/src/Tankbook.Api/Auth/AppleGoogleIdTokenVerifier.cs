using System.Text.Json;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Options;

namespace Tankbook.Api.Auth;

/// <summary>
/// Verifies Sign in with Apple / Google identity tokens against the provider's
/// fetched-and-cached JWKS (docs/SECURITY.md). The keys are public but the
/// signature is always checked: a token is never trusted on its claims alone.
/// RS256 only, key selected by the header's kid, exp/iat/nbf checked with the
/// configured clock skew.
/// </summary>
public sealed class AppleGoogleIdTokenVerifier : IIdTokenVerifier
{
    private static readonly string[] SupportedProviders = ["apple", "google"];

    private readonly HttpClient _http;
    private readonly IMemoryCache _cache;
    private readonly AuthOptions _options;
    private readonly TimeProvider _time;

    public AppleGoogleIdTokenVerifier(
        IHttpClientFactory httpFactory,
        IMemoryCache cache,
        IOptions<AuthOptions> options,
        TimeProvider time)
    {
        _http = httpFactory.CreateClient();
        _cache = cache;
        _options = options.Value;
        _time = time;
    }

    public AppleGoogleIdTokenVerifier(
        IHttpClientFactory httpFactory,
        IMemoryCache cache,
        IOptions<AuthOptions> options)
        : this(httpFactory, cache, options, TimeProvider.System)
    {
    }

    public async Task<IdTokenVerificationResult> VerifyAsync(string provider, string idToken, CancellationToken cancellationToken)
    {
        if (!SupportedProviders.Contains(provider, StringComparer.Ordinal))
        {
            return IdTokenVerificationResult.Failed(IdTokenOutcome.UnsupportedProvider);
        }

        if (!JwtCodec.TryDecode(idToken, out var headerJson, out var payloadJson))
        {
            return IdTokenVerificationResult.Failed(IdTokenOutcome.Malformed);
        }

        JsonDocument header;
        JsonDocument payload;
        try
        {
            header = JsonDocument.Parse(headerJson);
            payload = JsonDocument.Parse(payloadJson);
        }
        catch (JsonException)
        {
            return IdTokenVerificationResult.Failed(IdTokenOutcome.Malformed);
        }

        using (header)
        using (payload)
        {
            var kid = header.RootElement.TryGetProperty("kid", out var kidElement)
                ? kidElement.GetString()
                : null;
            var alg = header.RootElement.TryGetProperty("alg", out var algElement)
                ? algElement.GetString()
                : null;
            if (alg != "RS256" || string.IsNullOrEmpty(kid))
            {
                return IdTokenVerificationResult.Failed(IdTokenOutcome.Malformed);
            }

            var jwks = await GetJwksAsync(provider, cancellationToken);
            var key = jwks?.Keys.FirstOrDefault(k => k.Kid == kid);
            if (key is null)
            {
                return IdTokenVerificationResult.Failed(IdTokenOutcome.UnknownKey);
            }

            if (!JwtCodec.VerifyRsa256(idToken, key.ToRsa()))
            {
                return IdTokenVerificationResult.Failed(IdTokenOutcome.InvalidSignature);
            }

            var now = _time.GetUtcNow();
            if (!TryGetUnixSeconds(payload.RootElement, "exp", out var exp) ||
                exp <= now.AddSeconds(-_options.ClockSkewSeconds).ToUnixTimeSeconds())
            {
                return IdTokenVerificationResult.Failed(IdTokenOutcome.Expired);
            }

            if ((TryGetUnixSeconds(payload.RootElement, "iat", out var iat) &&
                 iat > now.AddSeconds(_options.ClockSkewSeconds).ToUnixTimeSeconds()) ||
                (TryGetUnixSeconds(payload.RootElement, "nbf", out var nbf) &&
                 nbf > now.AddSeconds(_options.ClockSkewSeconds).ToUnixTimeSeconds()))
            {
                return IdTokenVerificationResult.Failed(IdTokenOutcome.ClockSkew);
            }

            var subject = payload.RootElement.TryGetProperty("sub", out var subElement)
                ? subElement.GetString()
                : null;
            if (string.IsNullOrEmpty(subject))
            {
                return IdTokenVerificationResult.Failed(IdTokenOutcome.Malformed);
            }

            var email = payload.RootElement.TryGetProperty("email", out var emailElement)
                ? emailElement.GetString()
                : null;
            if (string.IsNullOrEmpty(email))
            {
                return IdTokenVerificationResult.Failed(IdTokenOutcome.MissingEmail);
            }

            if (_options.RequireEmailVerified && !IsEmailVerified(payload.RootElement))
            {
                return IdTokenVerificationResult.Failed(IdTokenOutcome.EmailNotVerified);
            }

            return IdTokenVerificationResult.Ok(subject, email);
        }
    }

    private async Task<JwksDocument?> GetJwksAsync(string provider, CancellationToken cancellationToken)
    {
        var url = provider == "apple" ? _options.AppleJwksUrl : _options.GoogleJwksUrl;
        if (_cache.TryGetValue<JwksDocument>(url, out var cached) && cached is not null)
        {
            return cached;
        }

        var json = await _http.GetStringAsync(url, cancellationToken);
        var document = JwksDocument.Parse(json);
        _cache.Set(url, document, TimeSpan.FromMinutes(_options.JwksCacheMinutes));
        return document;
    }

    private static bool TryGetUnixSeconds(JsonElement element, string name, out long seconds)
    {
        seconds = 0;
        if (!element.TryGetProperty(name, out var value))
        {
            return false;
        }

        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out seconds))
        {
            return true;
        }

        return false;
    }

    private static bool IsEmailVerified(JsonElement payload)
    {
        if (!payload.TryGetProperty("email_verified", out var value))
        {
            return false;
        }

        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.String => bool.TryParse(value.GetString(), out var parsed) && parsed,
            _ => false,
        };
    }
}
