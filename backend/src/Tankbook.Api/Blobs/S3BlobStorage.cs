using System.Net;
using Amazon.Runtime;
using Amazon.S3;
using Amazon.S3.Model;
using Microsoft.Extensions.Options;
using Tankbook.Api.Options;

namespace Tankbook.Api.Blobs;

/// <summary>
/// The real S3-compatible storage implementation (docs/SYNC.md: provider-agnostic
/// - MinIO locally, R2/B2/etc. in deployment, all behind the S3 API). Presigned
/// URLs are minted with the AWS SDK's local signer, so the ASP.NET server never
/// proxies file bytes. The credentials come from <see cref="S3Options"/> and are
/// server-side only (docs/SECURITY.md); nothing here leaves the process except
/// the short-lived URL handed to the authenticated caller.
/// </summary>
public sealed class S3BlobStorage : IBlobStorage
{
    private const int DeleteBatchSize = 1000;

    private readonly AmazonS3Client _client;
    private readonly string _bucket;
    private readonly TimeProvider _time;

    public S3BlobStorage(IOptions<S3Options> options, TimeProvider time)
    {
        var s3 = options.Value;
        if (string.IsNullOrWhiteSpace(s3.Endpoint) || string.IsNullOrWhiteSpace(s3.Bucket))
        {
            throw new InvalidOperationException(
                "S3:Endpoint and S3:Bucket must be configured to serve blobs.");
        }

        var credentials = new BasicAWSCredentials(s3.AccessKey ?? string.Empty, s3.SecretKey ?? string.Empty);
        var config = new AmazonS3Config
        {
            ServiceURL = s3.Endpoint,
            ForcePathStyle = true,
            UseHttp = !s3.UseSsl,
            AuthenticationRegion = "us-east-1",
        };

        _client = new AmazonS3Client(credentials, config);
        _bucket = s3.Bucket;
        _time = time;
    }

    public PresignedUrl CreateUploadUrl(string key, TimeSpan lifetime)
    {
        var expiresAt = _time.GetUtcNow().Add(lifetime);
        var request = new GetPreSignedUrlRequest
        {
            BucketName = _bucket,
            Key = key,
            Verb = HttpVerb.PUT,
            Expires = expiresAt.UtcDateTime,
        };
        return new PresignedUrl(_client.GetPreSignedURL(request), expiresAt);
    }

    public PresignedUrl CreateDownloadUrl(string key, TimeSpan lifetime)
    {
        var expiresAt = _time.GetUtcNow().Add(lifetime);
        var request = new GetPreSignedUrlRequest
        {
            BucketName = _bucket,
            Key = key,
            Verb = HttpVerb.GET,
            Expires = expiresAt.UtcDateTime,
        };
        return new PresignedUrl(_client.GetPreSignedURL(request), expiresAt);
    }

    public async Task<long?> GetObjectSizeAsync(string key, CancellationToken cancellationToken)
    {
        try
        {
            var metadata = await _client.GetObjectMetadataAsync(_bucket, key, cancellationToken);
            return metadata.ContentLength;
        }
        catch (AmazonS3Exception ex) when (ex.StatusCode == HttpStatusCode.NotFound)
        {
            return null;
        }
    }

    public async Task<IReadOnlyList<string>> ListKeysAsync(string prefix, CancellationToken cancellationToken)
    {
        var keys = new List<string>();
        string? token = null;
        ListObjectsV2Response response;
        do
        {
            response = await _client.ListObjectsV2Async(
                new ListObjectsV2Request
                {
                    BucketName = _bucket,
                    Prefix = prefix,
                    ContinuationToken = token,
                },
                cancellationToken);
            keys.AddRange(response.S3Objects.Select(o => o.Key));
            token = response.NextContinuationToken;
        }
        while (response.IsTruncated);

        return keys;
    }

    public Task DeleteAsync(string key, CancellationToken cancellationToken)
        => _client.DeleteObjectAsync(_bucket, key, cancellationToken);

    public async Task DeleteManyAsync(IReadOnlyList<string> keys, CancellationToken cancellationToken)
    {
        foreach (var chunk in keys.Chunk(DeleteBatchSize))
        {
            await _client.DeleteObjectsAsync(
                new DeleteObjectsRequest
                {
                    BucketName = _bucket,
                    Objects = chunk.Select(key => new KeyVersion { Key = key }).ToList(),
                },
                cancellationToken);
        }
    }
}
