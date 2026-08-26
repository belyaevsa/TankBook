using System.Net;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Tankbook.Api.Auth;

namespace Tankbook.Api.Notifications;

/// <summary>
/// The real APNs client (docs/NOTIFICATIONS.md): token-based (JWT, ES256) auth,
/// HTTP/2, and a body that is always the silent payload the caller supplied.
/// It never throws to the nudge layer - every failure resolves to an
/// <see cref="ApnsOutcome"/>, so a dead provider or a bad network minute can
/// never surface as a sync error. The provider token (team id + key id + signed
/// iat) is derived from server-side secrets that never leave this class
/// (docs/SECURITY.md). This implementation is not exercised by the suite - the
/// tests drive the <see cref="IApnsClient"/> seam with a recording double; no
/// real APNs credential is used anywhere.
/// </summary>
public sealed class ApnsClient : IApnsClient
{
    private readonly HttpClient _http;
    private readonly ApnsOptions _options;
    private readonly TimeProvider _time;
    private readonly ECDsa? _signingKey;

    public ApnsClient(IHttpClientFactory httpFactory, IOptions<ApnsOptions> options, TimeProvider time)
    {
        _options = options.Value;
        _time = time;
        _http = httpFactory.CreateClient("apns");
        if (_options.IsConfigured)
        {
            _signingKey = ECDsa.Create();
            _signingKey.ImportPkcs8PrivateKey(ParsePkcs8(_options.PrivateKey!), out _);
        }
    }

    public async Task<ApnsSendResult> SendAsync(string deviceToken, string payloadJson, CancellationToken cancellationToken)
    {
        if (_signingKey is null || string.IsNullOrWhiteSpace(_options.Topic))
        {
            return new ApnsSendResult(ApnsOutcome.TransientFailure, "not_configured");
        }

        try
        {
            using var request = new HttpRequestMessage(
                HttpMethod.Post,
                $"{_options.Endpoint.TrimEnd('/')}/3/device/{Uri.EscapeDataString(deviceToken)}");
            request.Version = HttpVersion.Version20;
            request.VersionPolicy = HttpVersionPolicy.RequestVersionExact;
            request.Headers.Authorization = new AuthenticationHeaderValue("bearer", ProviderToken());
            request.Headers.TryAddWithoutValidation("apns-topic", _options.Topic);
            request.Headers.TryAddWithoutValidation("apns-push-type", "background");
            request.Content = new StringContent(payloadJson, Encoding.UTF8, "application/json");

            using var response = await _http.SendAsync(request, cancellationToken);
            if (response.IsSuccessStatusCode)
            {
                return new ApnsSendResult(ApnsOutcome.Delivered);
            }

            var reason = await ReadReasonAsync(response, cancellationToken);
            return IsInvalidToken((int)response.StatusCode, reason)
                ? new ApnsSendResult(ApnsOutcome.InvalidToken, reason)
                : new ApnsSendResult(ApnsOutcome.TransientFailure, reason ?? $"http_{(int)response.StatusCode}");
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or OperationCanceledException)
        {
            return new ApnsSendResult(ApnsOutcome.TransientFailure, ex.GetType().Name);
        }
    }

    /// <summary>
    /// True when the response means the token will never work again, so the row
    /// must be cleared (docs/NOTIFICATIONS.md: "token invalidation just clears
    /// the row - the device falls back to polling"). Only the permanent,
    /// token-specific rejections qualify: 410 Unregistered, and the 400 reasons
    /// BadDeviceToken / Unregistered / DeviceTokenNotForTopic. A 403 provider-token
    /// problem, a 429, a 5xx or a timeout are all transient and must NOT clear
    /// the token - that would downgrade a healthy device to polling forever over
    /// one bad minute.
    /// </summary>
    private static bool IsInvalidToken(int status, string? reason)
    {
        if (status == StatusCodes.Status410Gone)
        {
            return true;
        }

        if (status != StatusCodes.Status400BadRequest)
        {
            return false;
        }

        return reason is "BadDeviceToken" or "Unregistered" or "DeviceTokenNotForTopic";
    }

    private string ProviderToken()
    {
        var now = _time.GetUtcNow();
        var header = JsonSerializer.Serialize(new { alg = "ES256", kid = _options.KeyId });
        var payload = JsonSerializer.Serialize(new { iss = _options.TeamId, iat = now.ToUnixTimeSeconds() });

        var headerB64 = JwtCodec.Base64UrlEncode(Encoding.UTF8.GetBytes(header));
        var payloadB64 = JwtCodec.Base64UrlEncode(Encoding.UTF8.GetBytes(payload));
        var signature = _signingKey!.SignData(
            Encoding.ASCII.GetBytes(headerB64 + "." + payloadB64),
            HashAlgorithmName.SHA256,
            DSASignatureFormat.IeeeP1363FixedFieldConcatenation);
        return headerB64 + "." + payloadB64 + "." + JwtCodec.Base64UrlEncode(signature);
    }

    private static async Task<string?> ReadReasonAsync(HttpResponseMessage response, CancellationToken cancellationToken)
    {
        try
        {
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
            return document.RootElement.ValueKind == JsonValueKind.Object &&
                   document.RootElement.TryGetProperty("reason", out var reason)
                ? reason.GetString()
                : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>Accepts a base64 PKCS#8 DER key or a PEM "PRIVATE KEY" block (the .p8 file Apple issues).</summary>
    private static byte[] ParsePkcs8(string key)
    {
        var trimmed = key.Trim();
        if (trimmed.Contains("BEGIN", StringComparison.Ordinal))
        {
            var body = trimmed
                .Replace("-----BEGIN PRIVATE KEY-----", string.Empty, StringComparison.Ordinal)
                .Replace("-----END PRIVATE KEY-----", string.Empty, StringComparison.Ordinal)
                .Replace("\r", string.Empty)
                .Replace("\n", string.Empty)
                .Trim();
            return Convert.FromBase64String(body);
        }

        return Convert.FromBase64String(trimmed);
    }
}
