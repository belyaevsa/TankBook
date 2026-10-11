using System.Security.Cryptography;
using Tankbook.Api.Auth;
using Tankbook.Api.Blobs;
using Tankbook.Api.Options;
using OptionsFactory = Microsoft.Extensions.Options.Options;

namespace Tankbook.Api.Tests.Blobs;

/// <summary>
/// Pins the REAL upload and download URLs, not the recording double (PR.18,
/// docs/PRACTICES.md S10). <c>Presign_UploadBindsDeclaredContentTypeAndLength</c>
/// proves the service hands the declared type and length across the interface;
/// this file proves the token actually carries them and refuses anything else,
/// and that a download URL can only read.
///
/// The clock is FIXED, and moved by hand, so expiry is asserted at the second.
/// </summary>
public class BlobUploadUrlTests
{
    private const string BaseUrl = "https://api.tankbook.test";
    private static readonly DateTimeOffset Now = new(2026, 10, 11, 12, 0, 0, TimeSpan.Zero);

    private sealed class MovableTime(DateTimeOffset now) : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = now;

        public override DateTimeOffset GetUtcNow() => Now;
    }

    private static string SigningKey()
    {
        using var rsa = RSA.Create(2048);
        return Convert.ToBase64String(rsa.ExportPkcs8PrivateKey());
    }

    private static BlobUploadTokens Tokens(string signingKey, TimeProvider time, string? baseUrl = BaseUrl) =>
        new(
            OptionsFactory.Create(new AuthOptions { JwtSigningKeyBase64 = signingKey }),
            OptionsFactory.Create(new BlobOptions { PublicBaseUrl = baseUrl }),
            time);

    private static string TokenOf(PresignedUrl url) => url.Url[(BaseUrl + "/v1/blobs/upload/").Length..];

    [Fact]
    public void UploadUrl_PointsAtTheApi_AndCarriesKeyTypeLengthAndExpiry()
    {
        var time = new MovableTime(Now);
        var tokens = Tokens(SigningKey(), time);

        var url = tokens.Create("acct/sha", "image/jpeg", 123_456, TimeSpan.FromMinutes(15));

        Assert.StartsWith(BaseUrl + "/v1/blobs/upload/", url.Url, StringComparison.Ordinal);
        Assert.Equal(Now.AddMinutes(15), url.ExpiresAt);
        var grant = tokens.Verify(TokenOf(url));
        Assert.NotNull(grant);
        Assert.Equal("acct/sha", grant.Key);
        Assert.Equal("image/jpeg", grant.ContentType);
        Assert.Equal(123_456L, grant.ContentLength);
    }

    /// <summary>The S3 presign this replaced signed the content type but not the
    /// length (SigV2). The token signs both: change either and it is refused.</summary>
    [Fact]
    public void TamperedToken_IsRefused()
    {
        var tokens = Tokens(SigningKey(), new MovableTime(Now));
        var token = TokenOf(tokens.Create("acct/sha", "image/jpeg", 100, TimeSpan.FromMinutes(15)));
        var dot = token.IndexOf('.', StringComparison.Ordinal);
        var other = TokenOf(tokens.Create("acct/sha", "image/jpeg", 999_999, TimeSpan.FromMinutes(15)));

        // Another grant's payload under this grant's signature.
        Assert.Null(tokens.Verify(other[..other.IndexOf('.', StringComparison.Ordinal)] + token[dot..]));
        Assert.Null(tokens.Verify(token[..^2] + (token[^2] == 'A' ? "BA" : "AA")));
        Assert.Null(tokens.Verify("not-a-token"));
        Assert.Null(tokens.Verify(""));
    }

    [Fact]
    public void ExpiredToken_IsRefused()
    {
        var time = new MovableTime(Now);
        var tokens = Tokens(SigningKey(), time);
        var token = TokenOf(tokens.Create("acct/sha", "image/jpeg", 100, TimeSpan.FromMinutes(15)));

        time.Now = Now.AddMinutes(15).AddSeconds(-1);
        Assert.NotNull(tokens.Verify(token));
        time.Now = Now.AddMinutes(15);
        Assert.Null(tokens.Verify(token));
    }

    /// <summary>Blue-green: the container that verifies is not always the one that
    /// minted. The same signing key verifies; a different one does not.</summary>
    [Fact]
    public void SameSigningKey_Verifies_DifferentKey_DoesNot()
    {
        var key = SigningKey();
        var time = new MovableTime(Now);
        var token = TokenOf(Tokens(key, time).Create("acct/sha", "image/jpeg", 100, TimeSpan.FromMinutes(15)));

        Assert.NotNull(Tokens(key, time).Verify(token));
        Assert.Null(Tokens(SigningKey(), time).Verify(token));
    }

    [Fact]
    public void WithoutAPublicBaseUrl_NoUploadUrlIsMinted()
    {
        var tokens = Tokens(SigningKey(), new MovableTime(Now), baseUrl: null);

        Assert.Throws<InvalidOperationException>(
            () => tokens.Create("acct/sha", "image/jpeg", 100, TimeSpan.FromMinutes(15)));
    }

    /// <summary>The download URL is an Azure SAS that can only read, and stops
    /// at the lifetime given. Signed locally from the Azurite well-known key; no
    /// network.</summary>
    [Fact]
    public void DownloadUrl_IsReadOnlySas_WithTheGivenExpiry()
    {
        var time = new MovableTime(Now);
        var storage = new AzureBlobStorage(
            OptionsFactory.Create(new AzureBlobOptions { ConnectionString = "UseDevelopmentStorage=true", Container = "tankbook-test" }),
            Tokens(SigningKey(), time),
            time);

        var url = storage.CreateDownloadUrl("acct/sha", TimeSpan.FromMinutes(10));
        var query = System.Web.HttpUtility.ParseQueryString(new Uri(url.Url).Query);

        Assert.Contains("/tankbook-test/acct/sha", url.Url, StringComparison.Ordinal);
        Assert.Equal("r", query["sp"]);
        Assert.Equal(Now.AddMinutes(10), DateTimeOffset.Parse(query["se"]!, System.Globalization.CultureInfo.InvariantCulture));
        Assert.Equal(Now.AddMinutes(10), url.ExpiresAt);
        Assert.False(string.IsNullOrEmpty(query["sig"]));
    }

    [Fact]
    public void UploadUrl_FromAzureStorage_IsTheApiToken_NotAnAzureSas()
    {
        var time = new MovableTime(Now);
        var storage = new AzureBlobStorage(
            OptionsFactory.Create(new AzureBlobOptions { ConnectionString = "UseDevelopmentStorage=true", Container = "tankbook-test" }),
            Tokens(SigningKey(), time),
            time);

        var url = storage.CreateUploadUrl("acct/sha", "image/jpeg", 100, TimeSpan.FromMinutes(15));

        Assert.StartsWith(BaseUrl + "/v1/blobs/upload/", url.Url, StringComparison.Ordinal);
    }
}
