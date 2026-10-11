using Azure;
using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using Azure.Storage.Sas;
using Microsoft.Extensions.Options;
using Tankbook.Api.Options;

namespace Tankbook.Api.Blobs;

/// <summary>
/// The real storage implementation: one Azure Blob Storage container (Azurite
/// locally). Uploads go through the API (<see cref="BlobUploadTokens"/>, because
/// an Azure SAS cannot bind a PUT's type and length); downloads are read-only SAS
/// URLs signed with the account key from <see cref="AzureBlobOptions"/>, so the
/// server never proxies a download. The connection string is server-side only
/// (docs/SECURITY.md); nothing here leaves the process except the short-lived URL
/// handed to the authenticated caller.
/// </summary>
public sealed class AzureBlobStorage : IBlobStorage
{
    private readonly BlobContainerClient _container;
    private readonly BlobUploadTokens _uploads;
    private readonly TimeProvider _time;
    private volatile bool _containerReady;

    public AzureBlobStorage(IOptions<AzureBlobOptions> options, BlobUploadTokens uploads, TimeProvider time)
    {
        var azure = options.Value;
        if (string.IsNullOrWhiteSpace(azure.ConnectionString) || string.IsNullOrWhiteSpace(azure.Container))
        {
            throw new InvalidOperationException(
                "AzureBlob:ConnectionString and AzureBlob:Container must be configured to serve blobs.");
        }

        _container = new BlobContainerClient(azure.ConnectionString, azure.Container);
        if (!_container.CanGenerateSasUri)
        {
            throw new InvalidOperationException(
                "AzureBlob:ConnectionString must carry the account key: download URLs are SAS signed with it.");
        }

        _uploads = uploads;
        _time = time;
    }

    public PresignedUrl CreateUploadUrl(string key, string contentType, long contentLength, TimeSpan lifetime)
        => _uploads.Create(key, contentType, contentLength, lifetime);

    public PresignedUrl CreateDownloadUrl(string key, TimeSpan lifetime)
    {
        var expiresAt = _time.GetUtcNow().Add(lifetime);
        var uri = _container.GetBlobClient(key).GenerateSasUri(BlobSasPermissions.Read, expiresAt);
        return new PresignedUrl(uri.ToString(), expiresAt);
    }

    public async Task WriteAsync(string key, Stream content, string contentType, CancellationToken cancellationToken)
    {
        // Production's container exists; a fresh Azurite has none. An idempotent
        // create before the first successful write covers both (a race is harmless).
        if (!_containerReady)
        {
            await _container.CreateIfNotExistsAsync(cancellationToken: cancellationToken);
            _containerReady = true;
        }

        await _container.GetBlobClient(key).UploadAsync(
            content,
            new BlobUploadOptions { HttpHeaders = new BlobHttpHeaders { ContentType = contentType } },
            cancellationToken);
    }

    public async Task PutObjectAsync(string key, byte[] bytes, string contentType, CancellationToken cancellationToken)
    {
        using var stream = new MemoryStream(bytes, writable: false);
        await WriteAsync(key, stream, contentType, cancellationToken);
    }

    public async Task<byte[]?> GetObjectAsync(string key, CancellationToken cancellationToken)
    {
        try
        {
            var response = await _container.GetBlobClient(key).DownloadContentAsync(cancellationToken);
            return response.Value.Content.ToArray();
        }
        catch (RequestFailedException ex) when (ex.Status == StatusCodes.Status404NotFound)
        {
            return null;
        }
    }

    public async Task<long?> GetObjectSizeAsync(string key, CancellationToken cancellationToken)
    {
        try
        {
            var properties = await _container.GetBlobClient(key).GetPropertiesAsync(cancellationToken: cancellationToken);
            return properties.Value.ContentLength;
        }
        catch (RequestFailedException ex) when (ex.Status == StatusCodes.Status404NotFound)
        {
            return null;
        }
    }

    public async Task<IReadOnlyList<string>> ListKeysAsync(string prefix, CancellationToken cancellationToken)
    {
        var keys = new List<string>();
        try
        {
            await foreach (var blob in _container.GetBlobsAsync(BlobTraits.None, BlobStates.None, prefix, cancellationToken))
            {
                keys.Add(blob.Name);
            }
        }
        catch (RequestFailedException ex) when (ex.Status == StatusCodes.Status404NotFound)
        {
            // No container yet (a fresh Azurite): nothing is stored under any prefix.
        }

        return keys;
    }

    public async Task DeleteAsync(string key, CancellationToken cancellationToken)
        => await _container.GetBlobClient(key).DeleteIfExistsAsync(cancellationToken: cancellationToken);

    public async Task DeleteManyAsync(IReadOnlyList<string> keys, CancellationToken cancellationToken)
    {
        foreach (var key in keys)
        {
            await DeleteAsync(key, cancellationToken);
        }
    }
}
