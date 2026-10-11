using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Options;
using Tankbook.Api.Auth;

namespace Tankbook.Api.Blobs;

/// <summary>What a valid upload token lets its bearer write.</summary>
public sealed record BlobUploadGrant(string Key, string ContentType, long ContentLength, DateTimeOffset ExpiresAt);

/// <summary>
/// The upload URL the server hands out from <c>POST /blobs/begin</c>. Azure's own
/// SAS cannot bind a PUT to a content type and length, and an Azure PUT also needs
/// an <c>x-ms-blob-type</c> header the shipped apps do not send - so the URL
/// points at our own <c>PUT /v1/blobs/upload/{token}</c> instead, and the token
/// carries what the S3 presign used to sign: the key, the content type, the exact
/// length and the expiry (docs/PRACTICES.md S10, PR.18). The token is an
/// HMAC-SHA256 over those fields with a key derived from the JWT signing key, so
/// it needs no secret of its own and every blue-green container verifies the
/// other's tokens.
/// </summary>
public sealed class BlobUploadTokens
{
    private const string Route = "/v1/blobs/upload/";
    private static readonly byte[] KeyLabel = Encoding.UTF8.GetBytes("tankbook-blob-upload-v1");

    private readonly byte[] _key;
    private readonly string? _baseUrl;
    private readonly TimeProvider _time;

    public BlobUploadTokens(IOptions<AuthOptions> auth, IOptions<BlobOptions> blobs, TimeProvider time)
    {
        var signing = auth.Value.JwtSigningKeyBase64;

        // Without a configured signing key the JWT issuer runs on an ephemeral
        // key (dev only), and so do upload tokens: they die with the process.
        _key = string.IsNullOrWhiteSpace(signing)
            ? RandomNumberGenerator.GetBytes(32)
            : HMACSHA256.HashData(Convert.FromBase64String(signing), KeyLabel);
        _baseUrl = blobs.Value.PublicBaseUrl?.TrimEnd('/');
        _time = time;
    }

    public PresignedUrl Create(string key, string contentType, long contentLength, TimeSpan lifetime)
    {
        if (string.IsNullOrWhiteSpace(_baseUrl))
        {
            throw new InvalidOperationException("Blob:PublicBaseUrl must be configured to mint upload URLs.");
        }

        var expiresAt = _time.GetUtcNow().Add(lifetime);
        var payload = string.Join(
            '\n',
            key,
            contentType,
            contentLength.ToString(CultureInfo.InvariantCulture),
            expiresAt.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture));
        var body = Encoding.UTF8.GetBytes(payload);
        var token = $"{Base64Url(body)}.{Base64Url(HMACSHA256.HashData(_key, body))}";
        return new PresignedUrl($"{_baseUrl}{Route}{token}", expiresAt);
    }

    /// <summary>
    /// The grant a token carries, or null when it is malformed, tampered with or
    /// expired. The signature is compared in constant time.
    /// </summary>
    public BlobUploadGrant? Verify(string token)
    {
        var dot = token.IndexOf('.', StringComparison.Ordinal);
        if (dot <= 0 || !TryBase64Url(token[..dot], out var body) || !TryBase64Url(token[(dot + 1)..], out var mac))
        {
            return null;
        }

        if (!CryptographicOperations.FixedTimeEquals(mac, HMACSHA256.HashData(_key, body)))
        {
            return null;
        }

        var fields = Encoding.UTF8.GetString(body).Split('\n');
        if (fields.Length != 4
            || !long.TryParse(fields[2], NumberStyles.None, CultureInfo.InvariantCulture, out var length)
            || !long.TryParse(fields[3], NumberStyles.None, CultureInfo.InvariantCulture, out var expiry))
        {
            return null;
        }

        var expiresAt = DateTimeOffset.FromUnixTimeSeconds(expiry);
        return expiresAt <= _time.GetUtcNow() ? null : new BlobUploadGrant(fields[0], fields[1], length, expiresAt);
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static bool TryBase64Url(string text, out byte[] bytes)
    {
        var padded = text.Replace('-', '+').Replace('_', '/');
        padded += new string('=', (4 - (padded.Length % 4)) % 4);
        var buffer = new byte[padded.Length];
        if (!Convert.TryFromBase64String(padded, buffer, out var written))
        {
            bytes = [];
            return false;
        }

        bytes = buffer[..written];
        return true;
    }
}
