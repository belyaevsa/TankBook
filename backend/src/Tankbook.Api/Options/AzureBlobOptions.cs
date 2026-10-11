namespace Tankbook.Api.Options;

/// <summary>
/// Azure Blob Storage configuration (docs/SYNC.md "Attachments: the blob
/// pipeline"; Azurite for local dev). Bound from the "AzureBlob" configuration
/// section; environment variables use the AzureBlob__ConnectionString,
/// AzureBlob__Container form. The connection string carries the account key,
/// which also signs the read SAS URLs, so it is a server-side secret
/// (docs/SECURITY.md) and never leaves the process.
/// </summary>
public sealed class AzureBlobOptions
{
    public const string SectionName = "AzureBlob";

    public string? ConnectionString { get; set; }

    public string? Container { get; set; }
}
