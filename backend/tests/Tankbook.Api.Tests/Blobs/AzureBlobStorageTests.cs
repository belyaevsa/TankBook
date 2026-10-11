using System.Net.Sockets;
using System.Security.Cryptography;
using Tankbook.Api.Auth;
using Tankbook.Api.Blobs;
using Tankbook.Api.Options;
using OptionsFactory = Microsoft.Extensions.Options.Options;

namespace Tankbook.Api.Tests.Blobs;

/// <summary>
/// <see cref="AzureBlobStorage"/> against a real Azurite (backend/scripts/dev-up.sh
/// starts one on 127.0.0.1:10000): write, size, read, list, a SAS download fetched
/// over plain HTTP the way the app follows the redirect, and delete. Skipped when
/// no Azurite is listening, like the Postgres suites without Docker.
/// </summary>
public class AzureBlobStorageTests
{
    private static bool AzuriteListening()
    {
        try
        {
            using var client = new TcpClient();
            return client.ConnectAsync("127.0.0.1", 10000).Wait(TimeSpan.FromMilliseconds(500));
        }
        catch (Exception ex) when (ex is SocketException or AggregateException)
        {
            return false;
        }
    }

    private static AzureBlobStorage Storage(string container)
    {
        using var rsa = RSA.Create(2048);
        var tokens = new BlobUploadTokens(
            OptionsFactory.Create(new AuthOptions { JwtSigningKeyBase64 = Convert.ToBase64String(rsa.ExportPkcs8PrivateKey()) }),
            OptionsFactory.Create(new BlobOptions { PublicBaseUrl = "http://localhost" }),
            TimeProvider.System);
        return new AzureBlobStorage(
            OptionsFactory.Create(new AzureBlobOptions { ConnectionString = "UseDevelopmentStorage=true", Container = container }),
            tokens,
            TimeProvider.System);
    }

    [SkippableFact]
    public async Task RoundTrip_WriteReadListDownloadDelete()
    {
        Skip.IfNot(AzuriteListening(), "no Azurite on 127.0.0.1:10000 (backend/scripts/dev-up.sh)");
        var storage = Storage($"test-{Guid.NewGuid():N}");
        var bytes = RandomNumberGenerator.GetBytes(5000);
        var ct = CancellationToken.None;

        Assert.Empty(await storage.ListKeysAsync("acct/", ct));
        Assert.Null(await storage.GetObjectSizeAsync("acct/missing", ct));
        Assert.Null(await storage.GetObjectAsync("acct/missing", ct));

        // A request body cannot seek, so the upload must not need to.
        await storage.WriteAsync("acct/a", new ForwardOnly(new MemoryStream(bytes)), "image/jpeg", ct);
        await storage.PutObjectAsync("acct/llm/b", [1, 2, 3], "application/json", ct);

        Assert.Equal(5000L, await storage.GetObjectSizeAsync("acct/a", ct));
        Assert.Equal(bytes, await storage.GetObjectAsync("acct/a", ct));
        Assert.Equal(["acct/a", "acct/llm/b"], (await storage.ListKeysAsync("acct/", ct)).Order());

        using var http = new HttpClient();
        var download = await http.GetAsync(storage.CreateDownloadUrl("acct/a", TimeSpan.FromMinutes(10)).Url, ct);
        Assert.True(download.IsSuccessStatusCode, $"SAS download answered {(int)download.StatusCode}");
        Assert.Equal(bytes, await download.Content.ReadAsByteArrayAsync(ct));
        Assert.Equal("image/jpeg", download.Content.Headers.ContentType?.MediaType);

        // The SAS is read-only: a PUT on the same URL is refused.
        var put = await http.PutAsync(storage.CreateDownloadUrl("acct/a", TimeSpan.FromMinutes(10)).Url, new ByteArrayContent([0]), ct);
        Assert.False(put.IsSuccessStatusCode);

        await storage.DeleteManyAsync(["acct/a", "acct/llm/b", "acct/never-written"], ct);
        await storage.DeleteAsync("acct/a", ct);
        Assert.Empty(await storage.ListKeysAsync("acct/", ct));
    }

    private sealed class ForwardOnly(Stream inner) : Stream
    {
        public override bool CanRead => true;

        public override bool CanSeek => false;

        public override bool CanWrite => false;

        public override long Length => throw new NotSupportedException();

        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }

        public override int Read(byte[] buffer, int offset, int count) => inner.Read(buffer, offset, count);

        public override void Flush() { }

        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();

        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
