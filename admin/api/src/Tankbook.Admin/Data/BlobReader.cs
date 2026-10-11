using Azure;
using Azure.Storage.Blobs;

namespace Tankbook.Admin.Data;

/// <summary>
/// Reads the API's blob container with a read-only SAS (docs/SECURITY.md -> "The admin viewer").
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

/// <summary>
/// The API's container in Azure Blob Storage. <c>AzureBlob:ConnectionString</c> is a
/// SAS connection string whose SAS grants read only (a stored access policy on the
/// container, so it is revoked by deleting the policy); <c>AzureBlob:Container</c> is
/// the API's container. A key that could write never reaches the viewer.
/// </summary>
public sealed class AzureBlobReader : IBlobReader
{
    // Built on first read, so a viewer with no storage configured still boots
    // and only a file request fails.
    private readonly Lazy<BlobContainerClient> _container;

    public AzureBlobReader(IConfiguration configuration)
    {
        var azure = configuration.GetSection("AzureBlob");
        _container = new Lazy<BlobContainerClient>(() => new BlobContainerClient(azure["ConnectionString"], azure["Container"]));
    }

    public async Task<byte[]?> ReadAsync(string key, CancellationToken ct)
    {
        try
        {
            var response = await _container.Value.GetBlobClient(key).DownloadContentAsync(ct);
            return response.Value.Content.ToArray();
        }
        catch (RequestFailedException e) when (e.Status == StatusCodes.Status404NotFound)
        {
            return null;
        }
    }
}
