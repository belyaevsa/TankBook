using Amazon.S3;
using Amazon.S3.Model;

namespace Tankbook.Admin.Data;

/// <summary>
/// Reads the API's blob bucket with a read-only key (docs/SECURITY.md -> "The admin viewer").
/// The keys are the API's own layout: a synced blob at <c>{account:N}/{sha256}</c>
/// (<c>blobs.storage_ref</c>), an LLM prompt rendition at <c>{account:N}/llm/{sha256}</c>.
/// </summary>
public interface IBlobReader
{
    /// <summary>The object's bytes, or null when it does not exist (purged, never written).</summary>
    Task<byte[]?> ReadAsync(string key, CancellationToken ct);
}

public static class BlobKeys
{
    public static string LlmPrompt(Guid accountId, string sha256) => $"{accountId:N}/llm/{sha256}";
}

public sealed class S3BlobReader : IBlobReader, IDisposable
{
    private readonly AmazonS3Client _client;
    private readonly string _bucket;

    public S3BlobReader(IConfiguration configuration)
    {
        var s3 = configuration.GetSection("S3");
        _bucket = s3["Bucket"] ?? "";
        _client = new AmazonS3Client(s3["AccessKey"], s3["SecretKey"], new AmazonS3Config
        {
            ServiceURL = s3["Endpoint"],
            ForcePathStyle = true,
        });
    }

    public async Task<byte[]?> ReadAsync(string key, CancellationToken ct)
    {
        try
        {
            using var response = await _client.GetObjectAsync(new GetObjectRequest { BucketName = _bucket, Key = key }, ct);
            using var memory = new MemoryStream();
            await response.ResponseStream.CopyToAsync(memory, ct);
            return memory.ToArray();
        }
        catch (AmazonS3Exception e) when (e.StatusCode == System.Net.HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public void Dispose() => _client.Dispose();
}
